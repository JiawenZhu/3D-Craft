# Privacy inventory — release reconciliation required

This is an engineering inventory, not a completed App Privacy declaration or a substitute for the published policy.

| Data | Observed handling | Remaining verification |
| --- | --- | --- |
| Account email and Firebase UID | Firebase authentication; user identity scopes private creations | Cloud deletion and stale-token rejection verified; physical-device confirmation remains |
| Reference photos, concepts and 3D files | Firebase Storage; private user paths and authorized access | Owner-only uploads, model output and disposable deletion verified; retention/backups review remains |
| Prompts, project metadata, conversations and jobs | Owner-scoped Firestore records migrated from local storage | Cloud projects/models are implemented; concepts/chat and provider retention review remain |
| Purchase identifiers and Token balance | RevenueCat verification, transactional pack/subscription wallets and webhook are deployed | Cloud transaction retention, refunds, expiry and privacy disclosures |
| Community links, votes, reports and blocks | Cloud API stores pending submissions, private reports and blocking preferences; approval is operator-only; see ../../community/moderation.md | Live API and deletion acceptance passed; physical-device UI and ongoing moderation operations remain |
| Exported files | Explicit user-selected iOS share destination | Release build verification |
| Optional AI account credentials | Earlier implementation uses a local bridge | Do not represent local account bridging as a ready cloud feature |

Inventory the exact distribution binary's SDKs and privacy manifests. Do not select “Data Not Collected” merely because the app has no advertising UI. Match App Privacy answers to actual collection, user linkage, purposes and third-party processing. Obtain and verify the necessary user consent before reference content is sent to third-party AI services.

Published policy URL: https://3d-craft.web.app/privacy
Official reference: https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
