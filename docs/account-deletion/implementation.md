# Account deletion

The iOS Profile screen offers **Delete account** in English and Chinese, with an explanation and a second destructive confirmation. A sign-in within the last five minutes is required. Older sessions are directed to sign out and sign in again; canceling an Apple subscription is not a prerequisite for deletion.

## Cloud flow

1. The Firebase-authenticated `POST /api/mobile/account/delete` requires `confirm: true`. Account identity comes from verified claims, never a submitted UID.
2. A deterministic Cloud Task is created before the Firestore deletion marker, so queue failure cannot lock the account. An early dispatch without a marker retries without erasing anything.
3. `accountDeletions/{uid}` immediately blocks authenticated API operations and client Firestore/Storage writes. Transactional purchase settlement also checks it, preventing a receipt retry from recreating the wallet.
4. The Cloud Run worker verifies a Google OIDC token for the exact task identity and audience. It disables Firebase sign-in, revokes refresh tokens, removes private Storage objects, private records and subcollections, owned public content and votes, Firebase authentication, and the RevenueCat customer profile.
5. Each step is idempotent and records completion. Cloud Tasks retries temporary failures without repeating completed steps. RevenueCat cleanup runs last so provider downtime does not delay removal from Firebase. RevenueCat V2 accepts customer deletion asynchronously.
6. On acceptance, the app clears its local creation caches and pending work, signs out, and confirms that processing continues on the server. It does not claim all provider erasure has finished synchronously.

Minimal receipt ownership and deletion records remain to prevent duplicate credits and resolve disputes. Exported copies, Apple transaction records and provider operational logs are outside this erasure operation. Apple subscriptions must be canceled through Apple separately.

## Deployment configuration

- Firebase/GCP project: `forma-studio-2026`; API origin: `https://3d-craft.web.app`.
- Cloud Run service: `craft-api`, region `us-central1`.
- Cloud Tasks queue: `craft-account-deletion`, unlimited attempts, one dispatch/second, maximum two concurrent tasks, backoff 30–3600 seconds.
- Task identity: `craft-deletion-worker@forma-studio-2026.iam.gserviceaccount.com`.
- Runtime identity: `craft-api@forma-studio-2026.iam.gserviceaccount.com`.
- `CRAFT_TASK_ORIGIN` is the direct HTTPS Cloud Run origin. `CRAFT_TASK_IDENTITY` is the task identity. The OIDC audience must equal the origin.
- `REVENUECAT_PROJECT_ID=projbbd24f9b`; `REVENUECAT_DELETION_API_KEY` is supplied only from Secret Manager `craft-revenuecat-deletion-key`. The V2 key has Customers Configuration read/write only. Subscription, purchase, project configuration, charts and audience permissions remain disabled. The separate existing purchase-lookup SDK key is unchanged.
- Runtime permissions: Cloud Tasks enqueuer, act-as on the task identity only, Firebase Auth user get/update/delete, existing Firestore access, and object list/delete scoped to `users/` in the app bucket.
- Firebase Storage's service agent requires `roles/firebaserules.firestoreServiceAgent` for the deletion-marker check. Rule compilation alone does not establish this cross-service permission; test an active authenticated download after deployment.
- Secrets are never included in the app, browser bundle, repository or build context.

## Verification

See `acceptance.md` for observed deployment and disposable-account results. The overall App Store release still requires cloud generation, subscription lifecycle and community moderation acceptance.

Primary references: [Apple account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/), [Firebase cross-service rules](https://firebase.google.com/docs/rules/manage-deploy), [RevenueCat customer API](https://www.revenuecat.com/docs/api-v2/customer).
