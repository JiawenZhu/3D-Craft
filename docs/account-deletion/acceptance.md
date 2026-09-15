# Account deletion acceptance — 14 September 2026

## Deployed and tested

- Cloud Run revision `craft-api-00004-9dw` serves 100% of API traffic. Image build `4efc2411-17ac-46b2-9cc9-8368c7c5bafa` succeeded.
- Firestore and Storage deletion-barrier rules compiled and were deployed. Live authenticated reads verified the required Storage-to-Firestore service permission.
- A new disposable Firebase account successfully accessed the canonical API wallet, Firestore document and private Storage file (all HTTP 200).
- Owner-authenticated deletion was accepted with HTTP 202. The old token then received HTTP 403 for wallet access, Firestore writes and Storage uploads.
- The worker removed Firebase authentication, the user document and nested project data, all files under its private Storage prefix, its community submission and its vote on a control submission. The control submission stayed intact and its aggregate decreased from 2 to 1.
- The first provider cleanup attempt exposed that the existing RevenueCat credential was a public SDK key. A separate V2 customer-only credential was stored in Secret Manager, and the same durable task retried successfully after deployment.
- A disposable RevenueCat customer was created and read (201/200), then removed by the worker; its subsequent lookup returned 404. The Firestore deletion marker reached `completed`.
- The temporary control submission was removed after verification. No real customer account or purchase was deleted; no purchase was made.
- Updated `/privacy` and `/delete-account` pages are deployed at `https://3d-craft.web.app`. The deletion page rendered its new instructions in the authenticated browser workspace.

## Local checks

- 25 focused backend tests passed across account deletion, authenticated cloud API, Firebase billing and Firebase creation storage.
- Three native image-cache tests passed in the iPhone simulator, including cancellation of an active download and removal of the cache directory.
- The Release iPhone target compiled successfully with the installed Xcode. This is local compilation evidence, not an App Store submission.
- Website type-check and production build passed. Existing bundle-size advisory remains.

## Not claimed

The deletion confirmation UI has not yet been exercised end-to-end on the physical phone. The new native changes must be included in a later App Store build; the already attached build 3 predates them. Cloud generation, subscription renewal/expiry and community moderation remain separate release blockers. No final review submission was made.
