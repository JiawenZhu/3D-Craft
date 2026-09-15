# Release evidence and blockers

Assessment: 14 September 2026. **Not ready for App Review or replacement of the working phone build.**

## Current verified state

- Physical device Jiawen's iPhone is paired and available through Apple's device tools.
- Live https://3d-craft.web.app/api/health returns JSON with storage=firebase and generationReady=false.
- iOS connection source is fixed to https://3d-craft.web.app; saved local/LAN addresses cannot override it.
- The deployed server/firebase_api.py reads owner-scoped Firebase records without SQLite. Its bootstrap contains empty products/engine catalogs. Unimplemented routes return HTTP 503.
- Update: verified consumable Token-pack delivery is now deployed through RevenueCat to Firestore, with separate production and sandbox wallets. A live existing sandbox receipt credited 200 Tokens; retry credited 0. Subscription delivery and generation remain incomplete.
- Earlier migration evidence records 77 library creations, including 28 models, and 204 referenced cloud files with none missing. These counts are a migration snapshot, not a fresh census.
- The phone installer checks cloud readiness before installation. No new app was installed in this readiness check.

## Required implementation and acceptance

1. Durable authenticated cloud generation: project creation, image upload, concepts, supported model requests, persistent jobs, recovery, output storage and failure settlement. Local thread pools and SQLite are not a Cloud Run durability solution.
2. Transactional cloud wallet and RevenueCat delivery: verified receipts, unique transaction ownership, idempotent grants, retries, renewal/expiry, refunds and isolated sandbox behavior. Consumables now use server/firebase_billing.py in the cloud. Subscription delivery still relies on the older local implementation and is not enabled in the cloud API.
3. Cloud community and account lifecycle: verify user submissions, reporting/blocking, deletion of cloud records/files and authentication revocation. A local UI or route is not proof of a deployed service.
4. Complete physical-device acceptance with the Mac service off, including independent-network generation and sandbox purchases.
5. Review final privacy disclosures, AI data-sharing consent, retention/deletion policy and SDK privacy manifests against the actual distribution archive.

## App Store Connect finish list

- Align the release version with the App Store version, assign an unused build number, archive with an Apple-supported distribution toolchain and validate signing.
- Upload the archive, wait for processing and attach the processed build to the intended version.
- Supply a dedicated functioning reviewer login and current contact information in App Review Information.
- Replace stale screenshots with exact iPhone/iPad captures from the release; verify support, privacy and terms URLs and localized metadata.
- Complete accurate age-rating, content-rights, privacy, encryption and availability answers. Recheck the community browser-game feature; do not reuse the old claim that no public user feed exists.
- Finalize reviewer-guide.md only after all advertised flows pass, attach it if useful, and submit the complete version for review.

Creating these files does not upload a binary, attach review information, or submit the app. No current Apple review status was inferred from older screenshots.

Apple requires operational backend services and full reviewer access: https://developer.apple.com/app-store/review/guidelines/ (Before You Submit).
