# Paid launch preparation

User confirmed: paid credits and subscriptions at launch. Amounts below come from the local StoreKit TEST configuration and are not approved live prices or configured App Store products.

| Product ID | Type | Proposed entitlement from code | Local test price only |
|---|---|---|---|
| craft.starter100 | Consumable | 100 Tokens once | USD 3.99 |
| craft.creator.weekly300 | Auto-renewing subscription, one week | 300 Tokens per paid weekly renewal | USD 7.99/week |

Before creating commercial products: confirm final credit quantities, regional prices, subscription period, provider-cost margins, failed-generation refunds, introductory offers (none currently), and cancellation/renewal copy. Do not treat the test prices as a pricing decision.

Implementation work required:
- Replace `/development/purchase` with server-verified Apple signed transaction processing for Sandbox and Production.
- Validate bundle, environment, product ID and unique transaction ID; grant credits atomically and idempotently.
- Process App Store Server Notifications for renewals, refunds, revocations and billing events. Reconcile missed events.
- Test app relaunch, interrupted payment, Ask to Buy, duplicate notification, refunded purchase, renewal, cancellation and restore/recovery.
- Remove development credit refill from the release UI; do not grant 1,000 review Tokens to every production session.
- Use StoreKit localized product prices, show duration and renewal terms, provide Restore/Manage Subscription, public terms and privacy links.
- Create IAP review screenshots and review notes only once the production paywall is accurate. The current test paywall must not be advertised as a paid entitlement.

The current code explicitly rejects live purchases. An active Apple Paid Apps Agreement does not make this backend production-ready.
