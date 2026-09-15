# Cloud community acceptance — 14 September 2026

## Deployed evidence

- Cloud Run revision `craft-api-00009-mgt` serves 100% of traffic. Its image is `us-central1-docker.pkg.dev/forma-studio-2026/craft-cloud/api:ce45d7bd-6c51-4b54-b4e4-6667c30c06b4`; Cloud Build completed successfully.
- Requests use `https://3d-craft.web.app/api/mobile/community`. No SQLite or Mac-hosted community service is involved.
- Firestore rules compiled and deployed; all four ranking indexes reached READY. Direct client reads of private reports/preferences and forged approval writes returned HTTP 403.
- A disposable Firebase account exercised the deployed API: authenticated link validation, rejection of a private HTTP address, pending submission, retry returning the same submission, owner-only listing and removal.
- Concurrent requests to the deployed vote endpoint produced one like. Blocking prevented app playback; unblock restored access. Reporting saved the actual reason in Firebase and hid the game for that account.
- The deployed account-deletion worker removed the account's report, private safety preferences, submission and vote. Its old token received HTTP 403. All disposable accounts and fixture records were removed after verification. No purchase or model-generation request was made.
- Canonical health remains `storage=firebase`, `modelGenerationReady=true`, `generationReady=false`; community work does not imply completion of cloud concepts/chat.
- Updated community privacy and retention text is published at `https://3d-craft.web.app/privacy`.

## Focused verification

55 backend tests passed across community, account deletion, projects, model jobs, billing and subscriptions. This includes consent validation, rejection of client-controlled publication/ownership, filtered pagination, bounded transaction retries and refusal to acknowledge failed reports.

The opt-in Firebase fixture also verified pending/approved/rejected visibility, concurrent submission/report/vote idempotency, blocking after creating a fresh service instance, posting restrictions, moderation records, deletion barriers and vote cleanup. It exposed a read-phase Firestore transaction conflict; bounded retries were added and the concurrent check then passed.

The Release iPhone target compiled with the installed Xcode. The only reported notice was optional AppIntents metadata extraction being skipped. Website type-check and production build passed; the existing large-bundle advisory remains. These are compilation and service checks, not physical-device UI acceptance.

Reproduce in an authorized environment:

```sh
CRAFT_RUN_FIRESTORE_INTEGRATION=1 CRAFT_CHECK_DEPLOYED_COMMUNITY=1 python scripts/verify_cloud_community.py
```

## Remaining review work

- Exercise report, block, unblock, submission status and rollback feedback on the physical iPhone build. Preserve existing purchase credit animation acceptance separately.
- Establish the human moderation routine and monitored support contact described in `moderation.md` before release. No automatic email or notification workflow is claimed.
- The three old example records originated in a local-review-only seed script and do not contain saved rights or review confirmations. They were preserved, but remain absent from the public feed. A fresh empty public feed is expected until submissions are approved; do not fabricate approvals to fill it.
- Reconcile App Store age rating and disclosures for the actual public game catalog and external browser behavior.
- Xcode Cloud Build 7 (pre-community source `feed9a1`) completed Build and Archive with zero errors/warnings, processed VALID / APP_STORE_ELIGIBLE, and was attached to version 1.0. The community native changes require the next processed build. The app has not been submitted for review.
