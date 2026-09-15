# Cloud Token-pack delivery

Implemented 14 September 2026 for the shared https://3d-craft.web.app API.

- POST /api/mobile/purchases/revenuecat verifies the signed-in Firebase user's purchase against RevenueCat before granting any Tokens.
- Server catalog determines pack amounts: small 200, medium 500, large 1200. Client amounts are not accepted.
- Firestore billingReceipts uses a globally unique store/environment/transaction key, and transactionally writes one balance increase and ledger entry. Cross-account reuse is rejected; refunds cannot regrant the same receipt.
- Production balance: users/{uid}/private/wallet. Apple sandbox balance: users/{uid}/private/sandboxWallet. Each has an entries subcollection. Sandbox purchases never fund the production balance.
- billingContext selects which balance to display after a verified purchase. It must never select a production generation funding source. Future generation billing must explicitly use the correct wallet and trusted environment policy.
- RevenueCat API key is supplied to Cloud Run through Secret Manager; no private provider key is embedded in iOS or included in the Docker build source.
- Reconciliation checks existing confirmed packs. It does not open a purchase sheet or charge the user.

## Wallet animation

A confirmed response includes purchaseReceiptID, purchaseTokens and purchaseCredit. The app opens Wallet after paywall dismissal, waits for its appearance transition, then displays +Tokens and changes the number. An animation is acknowledged only when the visible phase begins. Interrupted navigation before that point preserves the pending animation. A delayed response cannot update a different signed-in user's wallet.

## Evidence

Existing Apple sandbox receipt on the authorized test account: 200 Tokens delivered, second verification returned zero additional credit, subsequent Wallet GET returned the persisted balance, anonymous verification was rejected. No new purchase was made. Production wallet remained empty while sandbox credit was persisted.

## Remaining release work

Cloud subscription renewals/expiry, automatic refund webhooks, durable generation and full on-device acceptance are not certified by these checks. Refunds are reconciled when the RevenueCat subscriber record reports them. This is a Token-pack repair, not an App Store readiness declaration.
