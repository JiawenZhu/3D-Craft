# Firebase schema

Nothing here is wired up yet — the studio runs entirely on localhost. This is the
target shape, written now so the local store already matches it and the move is a
change of **transport**, not of model.

Three files carry the same shape today:

| | |
|---|---|
| `server/pipelines.py` | writes `server/runs/<id>/run.json` |
| `server/jobs.py` | writes `server/storage/assets.json` |
| `src/types/index.ts` | the TypeScript the browser reads them as |

Keep them in step. A field added to one and not the others is a migration bug
you get to find twice.

---

## 1. Collections

```
users/{uid}                       profile, quota, preferences
  private/account                 billing + BYOK keys — server-only, see §4
assets/{assetId}                  one finished 3D project
  likes/{uid}                     who liked it (existence IS the like)
runs/{runId}                      one concept-pipeline run, nodes inline
gallery/{imageId}                 curated starting images (today: public/images/explore/)
```

### Why these are top-level and not nested under `users/{uid}`

EXPLORE is a cross-user read: "every public 3D project, newest first". Nested
under an owner that is a collection-group query with a composite index, on every
page load, forever. Top-level with an `ownerId` field is one ordinary query, and
the rules in §4 still keep private work private.

---

## 2. Documents

### `assets/{assetId}`

Produced by `server/jobs.py`. The client **never writes this** — see §4.

```ts
{
  id: string,
  ownerId: string,              // uid; "local" until auth exists
  name: string,
  prompt: string,
  engine: 'trellis-2' | 'hunyuan3d-2.1' | 'rodin' | 'hybrid',
  createdAt: Timestamp,

  // Cloud Storage paths, NOT download URLs. URLs carry tokens that expire and
  // go stale in the document; resolve them at read time instead.
  modelPath: string,            // assets/{assetId}/model.glb
  thumbPath: string | null,
  splatPath: string | null,

  // measured server-side from the GLB so the info panel fills instantly
  faces: number,
  vertices: number,
  meshes: number,
  materials: number,
  dimensions: [number, number, number],
  textureRes: number,
  fileSizeMb: number,

  visibility: 'public' | 'private',
  likes: number,                // denormalised count; see the note below
  provider: string,             // 'api' | 'local' | 'space'
  note: string,

  runId: string | null,         // the concept run that produced it, if any
  sourceRef: string | null,     // the image it was reconstructed from
}
```

`likes` is a counter **and** a subcollection. The counter is what the grid
renders — 40 cards must not mean 40 subcollection reads. The subcollection is
what makes a like idempotent and lets someone see their own likes. Keep them
consistent with a transaction, or a `likes/{uid}` onWrite trigger; do not let a
client write the counter directly.

### `runs/{runId}`

Produced by `server/pipelines.py`. Matches `run.json` field for field.

```ts
{
  id: string,
  ownerId: string,
  title: string,
  status: 'running' | 'done' | 'failed',
  createdAt: Timestamp,
  updatedAt: Timestamp,

  input: {
    prompt: string,             // the user's own words
    imagePath: string | null,   // runs/{runId}/source.jpg
    sourceRef: string | null,   // gallery path, when they started from one
  },
  settings: { engine, effort, targetFaces, texture, quadRemesh, seed, steps, guidance, isPrivate },

  nodes: [                      // exactly four, in order, ALWAYS read together
    { id, kind: 'source',  status, startedAt, finishedAt, error, imagePath, text },
    { id, kind: 'prompt',  status, ..., text, subject, notes, model, ms },
    { id, kind: 'concept', status, ..., imagePath, model, ms, sizeKb },
    { id, kind: 'model3d', status, ..., jobId, progress, message, assetId, faces, provider },
  ],

  assetId: string | null,
  error: string | null,
}
```

**Nodes stay an array inside the document, not a subcollection.** There are four
of them, they are never read apart, and the whole point is that the board
re-renders as a unit. As a subcollection every stage transition would cost a
listener and the board would tear — one node updating a beat before its
neighbour. One document also means `onSnapshot` on `runs/{runId}` replaces the
`GET /api/pipelines/{id}` poll outright, which is the single biggest thing
Firestore buys this feature.

The local `server/runs/index.json` **disappears** in the move. It exists because
reading 200 JSON files to draw a history strip is absurd; Firestore answers
`where('ownerId','==',uid).orderBy('createdAt','desc').limit(30)` directly.

### `gallery/{imageId}`

The curated starting images. Today they are files in `public/images/explore/`
and `GET /api/inbox` lists them off disk.

```ts
{
  id: string,
  name: string,
  path: string,                 // gallery/{imageId}.jpg
  direction: 'unknown' | 'front' | 'back' | ...,
  sizeKb: number,
  createdAt: Timestamp,
  builtAssetId: string | null,  // set once someone reconstructs it
}
```

`builtAssetId` is the field that makes EXPLORE cheap. The studio currently
derives it in the browser by scanning every asset's `sourceRef` — fine at 14
assets, not at 14,000.

### `users/{uid}`

```ts
{
  displayName: string,
  photoURL: string | null,
  createdAt: Timestamp,
  credits: number,              // authoritative copy lives server-side, see §4
}
```

---

## 3. Cloud Storage layout

Mirrors the folders on disk now, so the upload script is a `walk` and a `put`.

```
assets/{assetId}/model.glb          server/storage/{assetId}/model.glb
assets/{assetId}/thumb.png
runs/{runId}/source.jpg             server/runs/{runId}/source.jpg
runs/{runId}/concept.jpg            server/runs/{runId}/concept.jpg
gallery/{imageId}.jpg               public/images/explore/*.jpg
```

Exports (`server/exports/`) do **not** move. They are OBJ/PLY/STL conversions of
a GLB that is already stored; regenerating one is a second of CPU and storing
every format for every asset is four times the bill for nothing.

---

## 4. Security rules

The important decision: **clients never write `assets` or `runs`.**

Every document in those collections is the receipt for something that cost real
money — a fal generation, a Gemini render. If a browser can create one it can
mint itself unlimited free assets, and if it can update one it can flip
`visibility`, rewrite `likes`, or repoint `modelPath` at somebody else's mesh.
All writes go through the API with the Admin SDK, which ignores rules.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() { return request.auth != null; }
    function isOwner(doc) { return signedIn() && request.auth.uid == doc.ownerId; }

    match /users/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      // A user may edit their profile but NOT their credits — that field is the
      // billing balance, and owner-writable billing is a self-service refund.
      allow update: if signedIn() && request.auth.uid == uid
                    && !request.resource.data.diff(resource.data).affectedKeys()
                         .hasAny(['credits', 'plan']);
      allow create, delete: if false;

      // Keys and billing. Denied to every client outright: the Admin SDK
      // ignores rules, so the API still reaches it.
      match /private/{doc} { allow read, write: if false; }
    }

    match /assets/{assetId} {
      allow read: if resource.data.visibility == 'public' || isOwner(resource.data);
      allow write: if false;                    // server only

      match /likes/{uid} {
        allow read: if signedIn();
        // One like, yours, no payload — nothing to forge.
        allow create, delete: if signedIn() && request.auth.uid == uid;
        allow update: if false;
      }
    }

    match /runs/{runId} {
      allow read: if isOwner(resource.data);    // runs are never public
      allow write: if false;                    // server only
    }

    match /gallery/{imageId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

Storage rules follow the same split — public meshes readable, everything written
by the server:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /gallery/{file}       { allow read: if true;        allow write: if false; }
    match /assets/{assetId}/{f} { allow read: if true;        allow write: if false; }
    match /runs/{runId}/{f}     { allow read: if request.auth != null; allow write: if false; }
  }
}
```

`runs/*` is auth-gated rather than public because a source image is a photo the
user uploaded, and the concept is derived from it. Neither is gallery content
unless they publish the mesh.

---

## 5. Indexes

```json
{
  "indexes": [
    { "collectionGroup": "assets", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "visibility", "order": "ASCENDING" },
      { "fieldPath": "createdAt",  "order": "DESCENDING" } ] },

    { "collectionGroup": "assets", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "ownerId",   "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "DESCENDING" } ] },

    { "collectionGroup": "assets", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "visibility", "order": "ASCENDING" },
      { "fieldPath": "likes",      "order": "DESCENDING" } ] },

    { "collectionGroup": "runs", "queryScope": "COLLECTION", "fields": [
      { "fieldPath": "ownerId",   "order": "ASCENDING" },
      { "fieldPath": "createdAt", "order": "DESCENDING" } ] }
  ]
}
```

Three of the four exist because of the shelf's own filter menu: EXPLORE sorts by
newest and by most-liked, ASSET sorts by newest within one owner. The fourth is
the run-history strip.

---

## 6. What actually changes in the code

Small, and deliberately so.

| Today | After |
|---|---|
| `GET /api/assets` | `onSnapshot(query(assets, where visibility == 'public'))` |
| `GET /api/pipelines/{id}` every 1.2s | `onSnapshot(doc(runs, runId))` — the poll disappears |
| `GET /api/inbox` every 5s | `onSnapshot(gallery)` — the poll disappears |
| `imageSrc()` resolving `/files/...` | `getDownloadURL()`, cached per path |
| `ownerId: "local"` | `request.auth.uid` |

The two polls are the honest reason to do this. They exist because a file on
disk cannot tell anyone it changed, and both are load-bearing: the pipeline
board and the hand-off folder are the two places where something appears without
the user having asked for it.

`server/pipelines.py` keeps its structure exactly — `_write(doc)` becomes
`db.collection('runs').document(run_id).set(doc)`, and every `_set(...)` call
site stays as it is. That is the whole reason the local store was written as a
document in the first place.
