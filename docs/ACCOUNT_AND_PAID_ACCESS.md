# Account and paid-access implementation — 2026-09-12

## Implemented and locally checked

- Web no longer creates anonymous Firebase sessions or offers guest generation.
- iOS uses Firebase email/password sign-in, registration and reset against the same project as web. Passwords are not persisted. Refresh credentials live in Keychain.
- Backend verifies Firebase ID tokens, including revocation, and rejects anonymous providers. Firebase UIDs are distinct from the old device-session identities. New wallets start at zero, with no trial/review migration.
- Switching accounts clears workspace state and isolates cached iOS library and pending generation records. Web reads account assets from Firestore and clears old shared caches from view.
- The $4.99 / 200-credit Stripe Checkout offer uses server-owned amounts and identity, and an authenticated customer request. Signed webhook delivery is idempotent per checkout session. Unpaid/wrong-currency/wrong-amount deliveries and production test events cannot grant credits.
- Legacy global generation/storage endpoints reject unsigned callers and unpaid accounts. They remain closed for paid accounts until owner scoping and metering are migrated.
- Paid mobile generation/chat remain explicitly unavailable rather than spending customer balances using the old 15/55 local-review prices. Stripe Checkout remains unavailable while this is incomplete. No real payment has been enabled or taken.
- Local development sessions are off by default. Isolated automated tests may explicitly set `CRAFT_ALLOW_LOCAL_REVIEW=1` and `RODIN_MOBILE_DEVELOPMENT=1`; production always rejects this bypass. Do not set these for a publicly proxied server.

## Required before enabling real sales

1. Complete provider-cost metering and settlement for chat, concepts, 3D and retry/partial-failure paths, replacing legacy review tariffs. Aggregate provider charges with the 15% fee once. Migrate web storage/jobs to per-account ownership, with authenticated media delivery compatible with native viewers.
2. Connect RevenueCat/Apple purchase delivery to the verified account wallet, including initial purchase, renewal, refund/revocation and restoration. Current native paywall remains a pricing preview; do not publish it as a working paid subscription release.
3. Configure production Firebase Admin credentials with appropriate user-verification permissions, a durable single-writer ledger service/database, and an HTTPS API address. Firebase Hosting currently has no backend rewrite; configure the production API or a rewrite before launch.
4. Configure `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` on that backend. Register `/api/billing/stripe/webhook` for `checkout.session.completed` and `checkout.session.async_payment_succeeded`. Add refund/dispute handling before live rollout. Never put these secrets in `VITE_*` or the app bundle.
5. Keep `CRAFT_PAID_GENERATION_READY` unset until items 1–4 and real sandbox end-to-end acceptance pass. It only controls checkout availability, not the generation safety blocks; remove those blocks only with tested metered routes.
6. Deploy server, web and Firestore rules together, then distribute the rebuilt iOS app. This turn made source changes and local builds only; no hosting/backend deployment or phone installation was performed.

## Validation

`CRAFT_ALLOW_LOCAL_REVIEW=1 venv/bin/python -m unittest tests.test_paid_access tests.test_mobile tests.test_mobile_chat tests.test_commerce`

79 tests passed with image/model providers mocked. The new tests cover missing/anonymous/forged identity, zero-credit accounts, rejection of device sessions and fake purchases, verified duplicate payment delivery, account isolation, and fail-closed legacy and paid generation. These do not substitute for production Firebase, Stripe or Apple/RevenueCat sandbox verification.

## Admin-granted demo credits

Demo credits are assigned explicitly by an administrator, never on signup. They enter the same spendable balance as purchased credits and satisfy the server credit gate without a purchase. The signed Firebase `admin: true` custom claim controls the web grant form and `POST /api/billing/admin/credits`; profile fields and email alone never authorize a grant. Recipients must have a registered, enabled Firebase account. Grants are atomic, deduplicated by request UUID, and recorded with actor, recipient, amount, time and reason in `admin_credit_grants`. Recipient ledger entries do not disclose private audit details.

With trusted Firebase Admin credentials configured, bootstrap the owner's role using `venv/bin/python -m scripts.set_account_admin --email zhujiawen519@gmail.com`. Sign out and back in afterward. The role has not been assigned live by this source change. `--revoke` removes the role and revokes sessions.

The existing generation-readiness blocks still apply to all balances, including admin grants. Source support for grants does not mean generation or purchases have been deployed or enabled.

## Website showcase mode

The website at https://3d-craft.web.app/ now renders `Showcase` instead of the creation/payment workspace. `LegacyStudioApp.tsx` preserves the old workspace, with no public route enabling it. The landing page links to Apple app ID 6811466883; actual download availability depends on App Store publication.

The read-only `/api/showcase/library` API uses the same verified Firebase owner and SQLite records as iOS. It excludes curated examples and uploaded originals from the private collection, requires no credit balance, and authenticates preview media requests. The website never substitutes demo data for an empty or unreachable collection.

Production library activation requires a reachable HTTPS backend serving this API with the iPhone app's persistent database. Configure `VITE_API_BASE` to that backend or add a matching hosting API rewrite before claiming live synchronization. Current hosting configuration serves static frontend only; no backend address is assumed and legacy device-owned creations are not assigned to an arbitrary signed-in user.

### Firebase preview sync (September 13)

Production `Showcase` now subscribes directly to `users/{uid}/mobileCreations` in Firestore. Owner-only rules protect that collection. Previews are size-bounded JPEG data stored inside the document, so viewing does not require the private LAN gateway or public file URLs. This phase displays concept images and previews of 3D objects; it does not upload full mesh files or provide cloud 3D interaction.

The updated iPhone store calls `/api/mobile/cloud-library/sync` after refresh, in batches of two changed previews. The backend uses that user's verified ID token for Firestore writes, and records successful content hashes for retries/deduplication. An authenticated `/claim-device` endpoint can migrate the old device's creations using its saved unguessable device token; it cannot migrate credits, claim another account's already-migrated library, or migrate running jobs. Unknown device credentials are rejected. The updated native app makes this claim during connection.

Hosting and Firestore rules may be deployed independently, but the Mac API must run the new code and the physical iPhone must install the new native build before historical device records can sync. No existing device-owned records were manually reassigned. The Mac inspection found no Firebase-owned jobs yet. Its configured Google credential file is missing; verified native sign-in must be checked after fixing that backend credential configuration. No live end-to-end sync has been claimed.
