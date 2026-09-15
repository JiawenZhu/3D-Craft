# Cloud subscription delivery: implementation and acceptance

Verified September 14, 2026 (US Central). This is partial release evidence, not App Review readiness.

## Implemented

- Canonical API: `https://3d-craft.web.app`. Cloud Run revision `craft-api-00005-9dj` serves Firebase-backed purchase reconciliation.
- Verified weekly/monthly periods grant 250/850 Tokens once. New periods replace unused subscription allowance; wallet reads enforce expiry even if no notification arrives. Pack balance is separate and never expires. Existing balances are not reclassified or expired by migration.
- Firestore transactions enforce receipt ownership, duplicate-delivery protection, subscription ordering, and the account-deletion barrier. Current-period refunds remove remaining subscription allowance; a delayed old period cannot replace a newer period.
- iOS Wallet displays pack and subscription balances separately, including the current period's expiry. The existing receipt-based navigation and Token animation remain in place.
- RevenueCat webhook `whintgr5ba19fb3e9` targets `/api/billing/revenuecat/webhook`, filters the 3D Craft App Store app, and accepts production and sandbox notifications. Authorization lives in Secret Manager, never in the app. Notifications trigger an authoritative customer lookup, not a grant from event-supplied amounts.
- Production and sandbox wallets remain separate. Cancellation and plan-change billing are governed by Apple's verified period, not a client-calculated price difference.

## Verified

- 45 focused backend tests passed, including period replacement, duplicate delivery after spending, expiry, upgrade ordering, refund handling, ownership, deletion and webhook authorization.
- An isolated synthetic Firestore fixture passed concurrent duplicate deliveries, weekly-to-monthly replacement, delayed old refund, expiry on read, and preservation of the 200-Token pack. It produced exactly three grant entries. Fixture wallet, entries and receipts were removed afterward. This did not execute an Apple purchase.
- The authorized test account's actual RevenueCat record was an expired, refunded sandbox monthly subscription. Cloud restore returned 200; a direct claim of that refunded transaction returned 409. No new purchase was made.
- RevenueCat's dashboard test event `5C72F2BD-3220-4840-A112-7508049D6C2D` received HTTP 200 from the canonical endpoint. An unauthenticated test request received 401. This verifies delivery/authentication, not a real renewal.
- Local iPhone Release compilation and website production build passed. Firebase Hosting deployment completed.

## Remaining before release

- Test fresh weekly/monthly purchases, accelerated renewals, cancellation, upgrade, delayed delivery and restore on the physical phone against Firebase. Confirm the visible balance and animation after navigation.
- Verify Apple-to-RevenueCat server notification coverage independently of the RevenueCat-to-Firebase transport test.
- The v1 subscriber lookup exposes the latest subscription period. Refunds of older periods, refund reversals, and account transfer policy need explicit handling and acceptance. A refunded receipt is currently sticky; reversal does not restore it automatically.
- Review the requested subscription-expiry policy and purchase disclosures against App Review requirements before release; existing paid balances are preserved. One-time Token packs must remain non-expiring.
- Generation reservations must spend valid subscription allowance first and preserve the source of reservations/refunds. Cloud generation is still unavailable (`generationReady=false`); no phone replacement or review submission is claimed.
- Select a processed App Store build containing these source changes after Xcode Cloud completes, and complete the remaining community, privacy and reviewer acceptance work.
