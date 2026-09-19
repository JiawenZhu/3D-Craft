# 3D Craft User-Authorized API Keys

User-authorized account API keys allow external coding agents (Claude, ChatGPT, Muse, or custom automation scripts) to utilize 3D Craft's Gemini prompt planning, concept image generation, and cloud 3D reconstruction pipeline.

Token spending is charged directly to the authorizing user's 3D Craft wallet.

---

## 1. Security & Storage Architecture

1. **Bearer Token Format**: High-entropy cryptographically random string starting with `craft_live_` (e.g. `craft_live_b82a...`).
2. **One-Time Plaintext Issuance**: The secret plaintext key is returned strictly once upon generation. It is **never** saved to Firebase, browser persistent storage, local logs, or git.
3. **Server-Side Storage**: Firestore stores only the SHA-256 cryptographic hash (`keyHash`) in the server-only collection `/apiKeys/{keyHash}` along with non-sensitive metadata (truncated prefix `craft_live_xxxxxx...`, user-assigned name, owner UID, scopes, timestamps, revoked status).
4. **Firestore Security Rules**: Direct client SDK reads and writes to `/apiKeys` and `/rateQuotas` are denied completely (`allow read, write: if false;`). Key management is only possible through server endpoints verifying the user's Firebase ID token.
5. **Atomic Concurrency Protection**: Each account is bounded to a maximum of **5 active keys**. Enforcement uses an atomic Firestore transaction against `/users/{uid}/private/apiKeysIndex`.
6. **Distributed Rate Quotas**: Cloud Run safe rate limiting is tracked per key in Firestore (`/rateQuotas/{keyHash}`) using transactional minute-window counters (60 requests/minute default).
7. **Authentication & Fail-Closed**: Every request validates:
   - Key exists and is not revoked.
   - Key is not expired.
   - Owner UID is not in `/accountDeletions/{uid}` (fail closed).
   - Owner Firebase Auth user exists and is not disabled (`auth.get_user`).
   - Key possesses the required scope for the route.
8. **Owner Isolation**: Keys resolve to the owner's Firebase UID (`firebase:<uid>`). All creation, project, and asset access is strictly isolated to the owning UID.
9. **Production Billing**: API keys spend the production ledger; client keys cannot turn on sandbox mode. Only accounts listed in the server's `CRAFT_API_SANDBOX_UIDS` (internal testers) follow their TestFlight billing context instead.
10. **Permanent Deletion Is Opt-In**: `assets:delete` is never implied by full access (`*`). A key can only delete if it was created with that scope.
11. **Account Deletion**: When an account deletion is processed, all keys and rate quota records for the owner UID are deleted.

---

## 2. Key Management Contract (For Claude Code Web & iOS UI)

All key management endpoints **require a verified Firebase ID Token** (`Authorization: Bearer <firebase_id_token>`).
API keys (`craft_live_...`) are strictly prohibited from calling these endpoints (fails with `403 Forbidden`).

### Create Key
- **Endpoint**: `POST /api/keys`
- **Headers**:
  - `Authorization: Bearer <Firebase_ID_Token>`
  - `Content-Type: application/json`
- **Request Body**:
  ```json
  {
    "name": "Claude Agent Key",
    "scopes": ["*"],
    "expiresInDays": 90
  }
  ```
  *(Note: `expiresInDays` is optional or `null` for no expiration).*
- **Response** (`200 OK` - **Only time plaintext is returned**):
  ```json
  {
    "key": "craft_live_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
    "id": "key_1a2b3c4d5e6f7a8b",
    "name": "Claude Agent Key",
    "prefix": "craft_live_ab12cd...",
    "scopes": ["*"],
    "createdAt": 1740000000.0,
    "expiresAt": 1747776000.0,
    "warning": "Store this key securely now. You will not be able to view it again. Requests authenticated with this key use your account Tokens."
  }
  ```

### List Key Metadata
- **Endpoint**: `GET /api/keys`
- **Headers**: `Authorization: Bearer <Firebase_ID_Token>`
- **Response** (`200 OK`):
  ```json
  {
    "keys": [
      {
        "id": "key_1a2b3c4d5e6f7a8b",
        "name": "Claude Agent Key",
        "prefix": "craft_live_ab12cd...",
        "scopes": ["*"],
        "createdAt": 1740000000.0,
        "expiresAt": 1747776000.0,
        "revoked": false,
        "revokedAt": null,
        "lastUsedAt": 1740000120.0
      }
    ]
  }
  ```

### Revoke Key
- **Endpoint**: `DELETE /api/keys/{key_id}` (or `POST /api/keys/{key_id}/revoke`)
- **Headers**: `Authorization: Bearer <Firebase_ID_Token>`
- **Response** (`200 OK`):
  ```json
  {
    "status": "revoked",
    "id": "key_1a2b3c4d5e6f7a8b"
  }
  ```

---

## 3. External Agent Pipeline API (`/api/v1/`)

API keys are accepted **ONLY** on explicit `/api/v1/` routes. They cannot access `/api/mobile/**`, `/api/billing/**`, `/api/purchases/**`, or admin/deletion endpoints.

### Allowed Routes & Scopes

| Method | Endpoint | Required Scope | Description |
|---|---|---|---|
| `GET` | `/api/v1/wallet` | `wallet:read` | Check account Token balance & ledger (production only). |
| `GET` | `/api/v1/image-models` | `assets:read` | List concept image generation models & token quotes. |
| `GET` | `/api/v1/planning/quote` | `assets:read` | Get token quote for prompt assistance. |
| `GET` | `/api/v1/pricing` | `assets:read` | Complete pipeline pricing catalog. |
| `GET` | `/api/v1/projects` | `assets:read` | List user's studio projects. |
| `POST` | `/api/v1/projects` | `concepts:write` | Create a new project (Form: `prompt`, `name`, `style`, `image`). |
| `POST` | `/api/v1/projects/{id}/references` | `prompt:write` | Add reference image to project. |
| `POST` | `/api/v1/projects/{id}/concepts` | `concepts:write` | Generate concept images (JSON: `ConceptRequest`). |
| `POST` | `/api/v1/concepts/{id}/refine` | `concepts:write` | Refine existing concept image. |
| `POST` | `/api/v1/concepts/{id}/model-prompt` | `prompt:write` | Gemini 3.8 Flash prompt planning for 3D model (from image). |
| `POST` | `/api/v1/planning/prompt` | `prompt:write` | Gemini standalone text prompt planning (no image required). |
| `POST` | `/api/v1/projects/{id}/chat` | `prompt:write` | Creative thinking prompt conversation. |
| `GET` | `/api/v1/planning/{job_id}` | `assets:read` | Get status/result of prompt planning job. |
| `POST` | `/api/v1/concepts/{id}/model` | `models:write` | Submit 3D reconstruction job (JSON: `ModelRequest`). Requires `models:write`. |
| `GET` | `/api/v1/jobs` | `assets:read` | List reconstruction and concept jobs. |
| `GET` | `/api/v1/jobs/{ident}` | `assets:read` | Poll job status, progress, and download GLB model URL. |
| `GET` | `/api/v1/assets` | `assets:read` | List owned 3D assets with downloadable GLB links and `downloadUrl`. |
| `GET` | `/api/v1/assets/{asset_id}/download` | `assets:read` | **Direct bearer-key download** for 3D model (`.glb`) or preview. |
| `GET` | `/api/v1/creations/quote` | `assets:read` | Maximum Tokens for one image + one 3D model. |
| `POST` | `/api/v1/creations` | `models:write` | **One step**: prompt → concept image → 3D model. `projectId` reprompts an existing project. |
| `GET` | `/api/v1/creations/{id}` | `assets:read` | Poll stage (`concepts` → `model` → `done`/`failed`), progress and download links. |
| `GET` | `/api/v1/projects/{id}` | `assets:read` | One project with its images, conversation, jobs and 3D models. |
| `PATCH` | `/api/v1/projects/{id}` | `concepts:write` | Rename a project (JSON: `{"name": "..."}`). |
| `GET` | `/api/v1/concepts/{id}/image` | `assets:read` | **Direct bearer-key download** of a concept image (JPEG). |
| `DELETE` | `/api/v1/projects/{id}` | `assets:delete` | **Permanently** delete a project with all its images, jobs and 3D models. |
| `DELETE` | `/api/v1/concepts/{id}` | `assets:delete` | **Permanently** delete one image. 3D models made from it keep working. |
| `DELETE` | `/api/v1/assets/{id}` | `assets:delete` | **Permanently** delete one 3D object. Its source image is kept. |
| `GET` | `/api/v1/animations/quote` | `assets:read` | Tokens for one looping character animation. |
| `POST` | `/api/v1/concepts/{id}/animation` | `models:write` | **Animate a character**: a short silent MP4 loop from one of your images. |
| `GET` | `/api/v1/openapi.json` | None | Full OpenAPI 3.1.0 schema with schemas. |

Everything created through the API appears in the user's 3D Craft app exactly like work made there: the prompt, images and 3D result show in the project's conversation. `GET /api/v1/assets` lists newest first.

Deletes return `409` while a creation in that project is still running; retry once it finishes.

---

## 4. Curl Examples for External Agents

### Quick start: prompt to a downloaded 3D model
```bash
KEY=craft_live_YOUR_KEY_HERE; API=https://3d-craft.web.app

# 1. Price cap for one image + one 3D model
CAP=$(curl -s "$API/api/v1/creations/quote" -H "Authorization: Bearer $KEY" | jq .maxTokens)

# 2. Create (use a new idempotencyKey per creation; retrying the same key never charges twice)
ID=$(curl -s -X POST "$API/api/v1/creations" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"idempotencyKey\":\"agent-$(date +%s)\",\"prompt\":\"A small fire dragon toy\",\"maxTokens\":$CAP}" | jq -r .id)

# 3. Poll until stage is done or failed (about 2-4 minutes)
until curl -s "$API/api/v1/creations/$ID" -H "Authorization: Bearer $KEY" | tee /tmp/c.json | jq -e '.stage=="done" or .stage=="failed"' >/dev/null; do sleep 10; done

# 4. Download the model and its concept image
curl -s "$API$(jq -r .asset.downloadUrl /tmp/c.json)" -H "Authorization: Bearer $KEY" -o dragon.glb
curl -s "$API$(jq -r '.concepts[0].imageUrl' /tmp/c.json)" -H "Authorization: Bearer $KEY" -o dragon.jpg
```

### Animate a character into a looping clip
```bash
# Price first (square 480p 4s is the cheapest shape)
curl -s "$API/api/v1/animations/quote" -H "Authorization: Bearer $KEY"

# Animate an image you already own; poll /jobs/{id} until status is done
curl -s -X POST "$API/api/v1/concepts/CONCEPT_ID/animation" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"idempotencyKey":"agent-anim-0001","motion":"it waves and smiles","maxTokens":54}'

# The finished loop downloads like any other creation
curl -s "$API/api/v1/assets/ANIMATION_JOB_ID/download" -H "Authorization: Bearer $KEY" -o character.mp4
```

### Reprompt, rename and delete
```bash
# Reprompt: a new image + 3D model in the same project (it shows as the next step of that conversation)
curl -s -X POST "$API/api/v1/creations" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"idempotencyKey":"agent-reprompt-0001","projectId":"PROJECT_ID","prompt":"Same dragon, but blue ice","maxTokens":CAP}'

# Rename
curl -s -X PATCH "$API/api/v1/projects/PROJECT_ID" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"name":"Ice dragon"}'

# Permanently delete (key must have the assets:delete scope)
curl -s -X DELETE "$API/api/v1/projects/PROJECT_ID" -H "Authorization: Bearer $KEY"
```

### 1. Check Wallet Balance
```bash
curl -s -X GET "https://3d-craft.web.app/api/v1/wallet" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE"
```

### 2. Standalone Text Prompt Planning
```bash
curl -s -X POST "https://3d-craft.web.app/api/v1/planning/prompt" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "agent-plan-0001",
    "prompt": "A mechanical steampunk owl with brass clockwork wings and amber eyes",
    "maxTokens": 10
  }'
```

### 3. Generate Concept Images
```bash
curl -s -X POST "https://3d-craft.web.app/api/v1/projects/PROJECT_ID/concepts" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "agent-concept-0001",
    "prompt": "A stylized stone dragon guardian, clean 3D silhouette, game ready",
    "count": 1,
    "maxTokens": 40
  }'
```

### 4. Submit 3D Reconstruction
```bash
curl -s -X POST "https://3d-craft.web.app/api/v1/concepts/CONCEPT_ID/model" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "idempotencyKey": "agent-model-0001",
    "engine": "rodin",
    "quality": "default",
    "effort": "high"
  }'
```

### 5. Check Job Status
```bash
curl -s -X GET "https://3d-craft.web.app/api/v1/jobs/JOB_ID" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE"
```

### 6. List Owned Assets & Direct Binary Download
```bash
# List assets
curl -s -X GET "https://3d-craft.web.app/api/v1/assets" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE"

# Direct bearer-key binary download of the .glb model
curl -s -L -X GET "https://3d-craft.web.app/api/v1/assets/ASSET_ID/download" \
  -H "Authorization: Bearer craft_live_YOUR_KEY_HERE" \
  -o model.glb
```

---

## 5. Third-Party Agent Integration Notes

- **Claude / OpenAI Custom GPT**: Import the OpenAPI schema directly from `https://3d-craft.web.app/api/v1/openapi.json`. Set authentication to `Bearer <API Key>`.
- **Muse**: [Muse from Meta](https://muse.ai/join) does not currently document an arbitrary consumer API key gateway. Direct integration compatibility is unverified. Third-party agents should use standard HTTP clients or custom tool declarations with the provided OpenAPI contract.

---

## 6. Required Deployment Commands

When ready to deploy (to be executed by parent/deployer):

1. **Deploy Firestore Rules**:
   ```bash
   firebase deploy --only firestore:rules
   ```
2. **Build and Deploy Cloud Run API (`craft-api`)**:
   ```bash
   gcloud builds submit --config=deploy/cloud-api/cloudbuild.yaml .
   ```
