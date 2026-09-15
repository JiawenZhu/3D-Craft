# Creation waiting and private image preview fixes

The 3D confirmation sheet and generation journey now use the authenticated
image cache already used by concept cards. The confirmation action still waits
for a decoded preview and submits the captured concept ID; preview resizing does
not replace the original source used by the cloud generation service.

Queued and running jobs display an orbiting ring, sparkles and a breathing halo
around the selected reference (or a creation icon for text-only requests).
English/Chinese labels distinguish queuing from generation. Motion follows the
existing Reduce Motion, background, low-power and contrast gates; the percentage
still comes exclusively from the job. Finished/failed jobs remove the activity
panel. The cloud worker now publishes its running stage when it claims work,
rather than leaving the UI queued until an image has been produced.

Provider errors now identify planning versus image generation and distinguish
temporary capacity/server failures. Logs include only model, method and HTTP
status, never provider response bodies or input content. Paid requests are not
automatically retried. Existing idempotency and Token settlement remain intact.

## Verification

- 8 focused native cache/source-activity tests passed on the iOS simulator.
- A temporary hosting test rendered the real queued journey for visual inspection;
  the temporary test was removed. Preview: `/tmp/craft-queued-animation.png`.
- 11 concept/planning tests passed, including worker stage publication, completed
  job/lease guards, no fabricated progress and no automatic paid retries.
- Disposable real Firestore/Storage integration passed reservation/replay,
  four-view publication, partial and saved-output recovery, exact settlement,
  private library and deletion barriers. Provider output was stubbed for this
  recovery test, and all disposable records were removed.
- The earlier failed reference-planning payload returned HTTP 200 and STOP on a
  fresh diagnostic call. This used the authenticated developer identity, not
  the Cloud Run identity. Historical failure status was not recorded, so its
  specific cause is unconfirmed; no user job was replayed or balance modified.
- Cloud Build `bbfe832b-88f3-4c47-b997-f056f11f6575` succeeded. Cloud Run revision
  `craft-api-00020-kcr` serves all traffic. Canonical `/api/health` returned
  `status=ok`, `generationReady=true`.
- The native app built, installed and launched on the connected iPhone, with
  `https://3d-craft.web.app` verified in the installed app configuration.

A complete new paid image-to-3D run and the animation on the physical phone
still require user acceptance. App Store build 15 already waiting for review
has not been replaced with this native update.
