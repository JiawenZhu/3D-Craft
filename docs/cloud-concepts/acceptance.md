# Cloud concept generation acceptance

The authenticated concept and refinement routes now run through `https://3d-craft.web.app`, using Firestore jobs, Cloud Tasks and private Firebase Storage. Cloud Run revision `craft-api-00015-2xc` receives 100% of traffic. Its image is `us-central1-docker.pkg.dev/forma-studio-2026/craft-cloud/api:c43d1270-c5a8-4b22-91a6-51907f99a254`; Cloud Build succeeded.

## Implemented behavior

- Gemini 3 Pro Image generates 2K concepts from text or an owned image reference. References retain up to 2K detail. Text-only requests receive a brief from the cloud planner. Refinement preserves the user's explicit edit instructions and records the parent concept.
- The authenticated catalog supplies expiring maximum Token reservations for one to four images. The native confirmation displays the maximum and explains that unused Tokens return. Actual verified provider usage settles once, with the existing commerce policy.
- Durable stages resume across worker restarts. Unknown paid responses are not sent again automatically. Saved output bytes and usage can recover before publication; partial jobs keep delivered images and release unused Tokens. Expired staged outputs cannot publish dangling library records after cleanup.
- Outputs and shared library metadata belong to the authenticated Firebase user. Account-deletion barriers apply before reservation, publication and settlement. User clients cannot forge provider output metadata.
- Account-connected ChatGPT image generation is still unavailable in this cloud service. It does not silently fall back to a paid model.

## Verification

- 73 focused backend checks passed, including usage accounting, price bounds, authentication and existing billing, planning, model, project, community and deletion checks.
- Disposable real Firestore tests passed: concurrent request replay creates one reservation, complete and partial settlement, recovery of saved output without another provider call, expired-output rejection, ownership and deletion barriers. Fixtures were removed.
- Native Release build succeeded using the existing installed Xcode. This is build evidence, not phone UI acceptance.
- Real canonical API generation produced four private 2048×2048 images and charged **67 Tokens** in total. Replaying the same request charged nothing more; no reservation remained. Authenticated image retrieval succeeded and anonymous retrieval was rejected.
- A real refinement changed the swing canopy to yellow while retaining the red frame and wooden bench. It produced one private 2K image, recorded its parent and charged **16 Tokens** once. The image was visually inspected. This refinement ran after deployment of the final revision above. Disposable cloud records, files and the test account were removed.

## Quality limits and remaining acceptance

The four-image test did **not** pass camera consistency. The model produced three-quarter views and an incorrect side view instead of the requested exact front/back/left/right set. The independent audit correctly returned `usable=false` with those mismatches. Individual images remain available for review; this is not proof of an aligned multiview reconstruction input or accurate face scanning.

Physical-phone confirmation, interrupted-network recovery, full reference-to-3D rendering/export and account-connected AI remain open. Overall `generationReady` remains false. No phone installation or App Store submission is claimed by these tests.

Local evidence: `/tmp/craft-concept-tests-final.log`, `/tmp/craft-concepts-recovery-complete.log`, `/tmp/craft-concepts-canonical.log`, `/tmp/craft-concepts-ios-final.log`, `/tmp/craft-concepts-complete-build.log` and `/tmp/craft-concepts-complete-deploy.log`. Temporary logs are machine-local and may later expire.

## Native retry verification — September 15

A pending concept request now retains its original approved `maxTokens`, including preserving the absence of this field on historical requests. Refreshing the catalog cannot change the identity or authorized amount of a retry. New requests still use the current price. Nineteen native simulator checks passed across account/model selection and source selection, including replay after a changed price and legacy-body preservation. Evidence: `/tmp/craft-cloud-native-tests.log`. This does not replace physical-device or complete UI acceptance.
