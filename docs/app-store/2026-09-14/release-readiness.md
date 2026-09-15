# Release evidence and blockers

Assessment: 15 September 2026. **Gemini cloud creation is verified and ready for phone acceptance. App Review submission is still pending the checks below.**

## Current verified state

- Physical device Jiawen's iPhone is paired and available through Apple's device tools.
- The canonical cloud API passed a complete text → Gemini concept → Hunyuan white-model test, charging 17 + 19 Tokens with no remaining reservation. See gemini-release-acceptance.md. The release readiness signal now requires concept, planning and 3D generation to be enabled; it does not represent completed phone QA or App Review.
- iOS connection source is fixed to https://3d-craft.web.app; saved local/LAN addresses cannot override it.
- The deployed server/firebase_api.py reads owner-scoped Firebase records and creates projects/reference uploads without SQLite. Uploads publish shared library metadata transactionally and have durable orphan cleanup; see ../../cloud-projects/acceptance.md. The bootstrap now lists four cloud 3D engines; image-to-3D worker acceptance is recorded in ../../cloud-models/acceptance.md. Image-conditioned prompt improvement now has durable cloud jobs and actual-usage settlement (../../cloud-planning/acceptance.md). Conversational chat now uses the same durable cloud planning service with owner-scoped history, reference-image understanding and actual-usage settlement (../../cloud-planning/chat-acceptance.md). Concept generation and image refinement now have durable cloud jobs, private 2K outputs and actual-usage settlement (../../cloud-concepts/acceptance.md). The user approved releasing with Gemini first. Own-account ChatGPT connection is deferred and hidden in this release; external model-sharing to ChatGPT / Claude Code remains available.
- Update: verified consumable Token-pack delivery is now deployed through RevenueCat to Firestore, with separate production and sandbox wallets. A live existing sandbox receipt credited 200 Tokens; retry credited 0. Subscription periods now reconcile in Firestore; full Gemini-to-3D cloud acceptance has passed. See ../../business/cloud-subscription-acceptance-2026-09-14.md for scope and remaining billing acceptance.
- Earlier migration evidence records 77 library creations, including 28 models, and 204 referenced cloud files with none missing. These counts are a migration snapshot, not a fresh census.
- The phone installer checks cloud readiness before installation. Source f6c1255 was built, installed and launched on the physical iPhone after reconnection; full interactive phone acceptance remains.

## Required implementation and acceptance

1. Complete physical-device acceptance for the deployed authenticated concept, refinement, prompt-improvement and conversational chat flows. Project/reference upload and four single-image 3D engines now have durable jobs, private output storage and transactional reservation settlement; real provider acceptance passed (../../cloud-models/acceptance.md). Multi-view live acceptance, complete phone rendering/export, remain open. Own-account ChatGPT is deferred beyond v1 by the user; it is not a launch requirement. Local thread pools and SQLite are not a Cloud Run durability solution.
2. Transactional cloud wallet and RevenueCat delivery: verified receipts, unique transaction ownership, idempotent grants, retries, renewal/expiry, refunds and isolated sandbox behavior. Consumables now use server/firebase_billing.py in the cloud. Subscription periods now reconcile in the cloud API, with separate expiring allowances, receipt ownership checks, and a verified RevenueCat webhook. Fresh phone subscription/renewal acceptance, historical refund coverage, and refund reversal remain open; do not treat the transport test as lifecycle acceptance.
3. Cloud community and account lifecycle: deployed submissions, reporting/blocking, moderation controls and deletion of the associated cloud data now pass disposable-account live acceptance; see ../../community/acceptance.md. Physical-device UI acceptance, the human moderation routine and rights/review reconciliation for the old examples remain open.
4. Complete physical-device acceptance with the Mac service off, including independent-network generation and sandbox purchases.
5. Review final privacy disclosures, AI data-sharing consent, retention/deletion policy and SDK privacy manifests against the actual distribution archive.

## App Store Connect finish list

- Align the release version with the App Store version, assign an unused build number, archive with an Apple-supported distribution toolchain and validate signing.
- Completed: Xcode Cloud Builds 3–11 uploaded and processed as version 1.0, VALID / APP_STORE_ELIGIBLE. Build 11 (source f1b44a9) completed Build and Archive with zero errors/warnings and is attached to version 1.0. Its build ID is d9be9a74-ccdf-40d4-8154-583c340fb869. Upload success does not satisfy the implementation and acceptance requirements above. The retry-price fix is included in processed Build 12. Gemini-first source f6c1255 completed Build 13 with no errors/warnings, processed as VALID, and is now attached to version 1.0 (build ID 8ae0320a-c4a8-4a31-bfb3-f1ac7bdde6c7).
- Supply a dedicated functioning reviewer login and current contact information in App Review Information.
- Replace stale screenshots with exact iPhone/iPad captures from the release; verify support, privacy and terms URLs and localized metadata.
- Complete accurate age-rating, content-rights, privacy, encryption and availability answers. Recheck the community browser-game feature; do not reuse the old claim that no public user feed exists.
- Finalize reviewer-guide.md only after all advertised flows pass, attach it if useful, and submit the complete version for review.

Creating these files does not upload a binary, attach review information, or submit the app. No current Apple review status was inferred from older screenshots.

Apple requires operational backend services and full reviewer access: https://developer.apple.com/app-store/review/guidelines/ (Before You Submit).

Account deletion update: the native Profile now has a bilingual deletion confirmation and fresh-sign-in check. The durable Firebase/Cloud Tasks worker is deployed, and a disposable-account live test verified private file/record removal, authentication deletion, vote cleanup, RevenueCat removal, and rejection of stale credentials. See ../../account-deletion/acceptance.md. Physical-phone UI acceptance remains. Build 4 (source 07932db) and Build 5 (source ad4d629) completed Build and Archive with no errors/warnings, processed successfully, and were attached in turn. The readiness flag is now tied to the enabled, verified Gemini cloud pipeline.

## Additional concrete release follow-ups found during verification

- Native Google sign-in still points to the Firebase Hosting alias instead of the canonical web.app auth page. The callback currently has no per-attempt state validation. Bind callbacks to an active sign-in attempt and verify the full Google flow before release. Email login was verified separately and works.
- Validate the final sign-in choices and AI data-sharing consent against the review requirements, and finish the precise SDK/disclosure audit.
- Existing App Store rights text was preserved, not independently recertified by the agent.
