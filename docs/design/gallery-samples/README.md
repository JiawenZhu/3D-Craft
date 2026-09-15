# Twenty finished gallery examples

All **20 reviewed concepts and 20 real textured Rodin GLBs** are complete. Every
model is registered as a curated example in the running local studio API, with
its original full-quality concept available in the native detail view.

[Manifest](manifest.json) records source and model checksums, exact job IDs,
asset IDs, generation settings, timestamps and validation. [Catalog](catalog.json)
contains the reviewed names and descriptions. GLB links below require the local
API at `http://127.0.0.1:8001`.

| # | Example | Kind | Concept | Real model | Triangles | Texture px |
|---|---|---|---|---|---:|---:|
| 1 | Lantern Explorer | character | [PNG](lantern-explorer.png) | `a-a44cd03b47` · [GLB](http://127.0.0.1:8001/files/a-a44cd03b47/model.glb) | 96,377 | 2048 |
| 2 | Cloud Dragon | flying | [PNG](cloud-dragon.png) | `a-0db52d58fb` · [GLB](http://127.0.0.1:8001/files/a-0db52d58fb/model.glb) | 91,878 | 2048 |
| 3 | Mint Racer | vehicle | [PNG](mint-racer.png) | `a-bc1cebd0f9` · [GLB](http://127.0.0.1:8001/files/a-bc1cebd0f9/model.glb) | 98,089 | 2048 |
| 4 | Coconut Island | world | [PNG](coconut-island.png) | `a-d9e847e983` · [GLB](http://127.0.0.1:8001/files/a-d9e847e983/model.glb) | 95,211 | 2048 |
| 5 | Woodland Cottage | world | [PNG](woodland-cottage.png) | `a-f53c8f3516` · [GLB](http://127.0.0.1:8001/files/a-f53c8f3516/model.glb) | 98,101 | 2048 |
| 6 | Crystal Falls | world | [PNG](waterfall-diorama.png) | `a-3586c66b6f` · [GLB](http://127.0.0.1:8001/files/a-3586c66b6f/model.glb) | 91,776 | 2048 |
| 7 | Moss Robot | character | [PNG](moss-robot.png) | `a-8da54c1701` · [GLB](http://127.0.0.1:8001/files/a-8da54c1701/model.glb) | 98,885 | 2048 |
| 8 | Moon Fox | character | [PNG](moon-fox.png) | `a-d62341c1e9` · [GLB](http://127.0.0.1:8001/files/a-d62341c1e9/model.glb) | 95,816 | 2048 |
| 9 | Ancient Oak | world | [PNG](ancient-oak.png) | `a-61b05b69fa` · [GLB](http://127.0.0.1:8001/files/a-61b05b69fa/model.glb) | 90,777 | 2048 |
| 10 | Sunblade | prop | [PNG](sunblade.png) | `a-f1a2d9cac8` · [GLB](http://127.0.0.1:8001/files/a-f1a2d9cac8/model.glb) | 96,860 | 2048 |
| 11 | Forest Shield | prop | [PNG](forest-shield.png) | `a-522fefabc7` · [GLB](http://127.0.0.1:8001/files/a-522fefabc7/model.glb) | 95,028 | 2048 |
| 12 | Ranger Bow | prop | [PNG](ranger-bow.png) | `a-a64fdb33b1` · [GLB](http://127.0.0.1:8001/files/a-a64fdb33b1/model.glb) | 93,095 | 2048 |
| 13 | Starlight Robe | prop | [PNG](starlight-robe.png) | `a-564699b014` · [GLB](http://127.0.0.1:8001/files/a-564699b014/model.glb) | 92,127 | 2048 |
| 14 | Ranger Outfit | prop | [PNG](ranger-outfit.png) | `a-dff4a535f1` · [GLB](http://127.0.0.1:8001/files/a-dff4a535f1/model.glb) | 99,073 | 2048 |
| 15 | Sunforge Helmet | prop | [PNG](sunforge-helmet.png) | `a-cd4c60f2b3` · [GLB](http://127.0.0.1:8001/files/a-cd4c60f2b3/model.glb) | 93,161 | 2048 |
| 16 | Trail Boots | prop | [PNG](trail-boots.png) | `a-81b69e9b39` · [GLB](http://127.0.0.1:8001/files/a-81b69e9b39/model.glb) | 92,964 | 2048 |
| 17 | Bunny Knight | character | [PNG](bunny-knight.png) | `a-04cde34041` · [GLB](http://127.0.0.1:8001/files/a-04cde34041/model.glb) | 97,212 | 2048 |
| 18 | Panda Chef | character | [PNG](panda-chef.png) | `a-5903ac9183` · [GLB](http://127.0.0.1:8001/files/a-5903ac9183/model.glb) | 94,096 | 2048 |
| 19 | Star Skiff | vehicle | [PNG](star-skiff.png) | `a-1b5bcde995` · [GLB](http://127.0.0.1:8001/files/a-1b5bcde995/model.glb) | 97,485 | 2048 |
| 20 | Treasure Chest | prop | [PNG](treasure-chest.png) | `a-31b67c7860` · [GLB](http://127.0.0.1:8001/files/a-31b67c7860/model.glb) | 95,476 | 2048 |

## Actual generation settings

The batch used the existing `/api/generate` endpoint and its Rodin adapter:
`fal-ai/hyper3d/rodin`, quality **high**, tier **Regular**, material **PBR**,
condition mode **concat**, requested seed **42**, geometry format **GLB**,
one reviewed reference per model, and batch size **1**. No T/A-pose or Hyper mode
was requested. References pass through the existing 1024-pixel normalization;
the full-resolution original PNG remains unchanged and separately accessible.

The request records `targetFaces=100000`; the current Rodin adapter controls
mesh density through its high quality tier, not an exact face-count parameter.
The table reports measured output triangles and texture resolution.

The configured estimate is **20 × $0.40 = $8.00**. This is an estimate based on
the repository's configured provider price, **not a verified provider invoice**.
Exactly 20 distinct jobs were submitted; there were no automatic retries or
extra generation requests.

## Verification

- All 20 assets contain real GLB v2 triangle geometry and materials, with source
  and model SHA-256 checksums preserved in the manifest.
- All 20 original concept URLs and all 20 model URLs return successful HTTP
  responses. All 20 GLBs contain normal maps and 2048-pixel texture output.
- The authenticated mobile example response contains only the 20 explicitly
  curated public assets. User-generated assets remain solely in their owner's
  collection; older uncurated assets are not included in the example feed.
- Five offline tests pass: durable pre-submit recording, no duplicate POST after
  an ambiguous response, existing-asset reconciliation, rejecting a missing mesh
  as completion, annotation scope/hash checks, curated-only examples and unchanged owned assets.
- [Native acceptance](design-qa.md) records four passing gallery UI checks and
  the passing cache-metadata unit check. Screenshot spot checks covered a character, island
  and robe. This is sample visual review, not a claim that all 20 models received
  a full visual or gameplay inspection.

## Reproducible helper

```sh
venv/bin/python scripts/generate_gallery_samples.py
venv/bin/python scripts/generate_gallery_samples.py --wait
venv/bin/python -m unittest discover -s tests -p 'test_gallery_samples.py'
```

Default invocation prints status only. `--submit` acts only on never-attempted
reviewed entries; it writes a durable attempted marker before a cost-bearing
request. Submitted, running, uncertain, failed and completed entries are never
automatically regenerated. `--wait` resumes observation of the same jobs and
reconciles an asset by its exact submission marker. A manifest file lock prevents
concurrent production helpers from submitting the same batch.

Original concepts are copied unchanged to `server/storage/gallery-samples/`.
The loopback gallery annotation route verifies the submission marker and source
hash, then updates asset metadata through the running API's existing index lock.
The backend's job registry is in memory: do not restart it while any future batch
is active. Investigate uncertain or failed jobs before authorizing another paid
attempt.
