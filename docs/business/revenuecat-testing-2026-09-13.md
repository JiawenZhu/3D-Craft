# RevenueCat purchase testing — 3D Craft

> Historical September 13 local-backend evidence. The cloud implementation and current remaining acceptance are documented in [cloud subscription acceptance](cloud-subscription-acceptance-2026-09-14.md); the local setup and rollover descriptions below are not the current cloud configuration.

## Verified on September 13, 2026

- Apple app `appb88bdcb0f7`, bundle `studio.craft.ios`: RevenueCat reports valid in-app purchase key credentials.
- Current offering `default` / `ofrng974d00ef04` contains weekly, monthly and three Token-pack packages.
- Firebase authentication of the user-authorized test account and the server's RevenueCat customer lookup succeeded. That account had no subscription or non-subscription purchase records.
- Live authenticated `/api/mobile/purchases/revenuecat/sync` returned 200. A fabricated transaction returned 409 and left the balance unchanged.
- 32 focused backend tests passed for purchase verification and paid access, including idempotency, account ownership, refunds, recurring grants and sandbox isolation.
- No Apple purchase was executed by the agent. UI/device builds do not prove sandbox checkout, renewal delivery or a production release.

## Phone testing, before public App Store release

1. In App Store Connect, open Users and Access → Sandbox → Test Accounts. Use a Sandbox Apple Account, distinct from the app's own Firebase login.
2. On the development iPhone, enable Developer Mode if needed and sign in under Settings → Developer → Sandbox Apple Account. Apple may first expose this section after the app attempts a purchase. Never substitute the Firebase app password for an Apple account password.
3. Open 3D Craft and sign in to the app. Open its paywall and confirm the selected product and Apple-displayed localized price. Choose the one-time 200-Token pack first.
4. Complete only an Apple sandbox purchase. Compare the wallet before/after: +200 once. Reopen the paywall and restore: the same transaction must not add another 200.
5. Test weekly (+250 per paid transaction) and monthly (+850 per paid transaction), cancellation, pending purchase and recovery after a lost connection. Apple sandbox renewals are accelerated; they do not follow real weekly/monthly intervals.
6. In RevenueCat Customers, enable sandbox data and inspect the same Firebase app-user ID. Confirm product, environment and transaction match the phone.

Alternative: upload a build to TestFlight for internal testing. TestFlight purchase testing also uses Apple's sandbox and does not require a public App Store release. Local StoreKit configuration tests are useful UI simulations but are not a substitute for Apple/RevenueCat sandbox verification. Sandbox regional prices can differ from production; verify final storefront prices in App Store Connect.

## Implementation and remaining production setup

The iPhone now calls `/api/mobile/purchases/revenuecat` with an Apple transaction identifier. The authenticated server queries RevenueCat for that Firebase user, validates product/store/environment, and grants its server-defined allowance. Client-supplied amounts are never used. Restore calls `/api/mobile/purchases/revenuecat/sync` to reconcile available customer records.

`REVENUECAT_API_KEY` is configured locally with the app's existing public Apple SDK key, supported by the v1 customer endpoint. No secret key is embedded in the app. `CRAFT_REVENUECAT_SANDBOX=1` permits test transactions only while the backend is not in production. Production always rejects sandbox grants.

A webhook receiver is implemented at `/api/billing/revenuecat/webhook`. It requires an exact `REVENUECAT_WEBHOOK_AUTHORIZATION` header and the 3D Craft App Store app ID. It grants initial purchases, renewals and top-ups once per transaction; refund notifications reverse the original grant once, including out-of-order delivery. Cancellation or expiration alone does not erase paid rollover Tokens.

**Not configured live yet:** a durable public HTTPS backend and RevenueCat webhook destination/authentication. The current Mac backend is private and is not reachable by RevenueCat. The pull path supports local purchase/restore testing, but the v1 subscription snapshot includes only the latest transaction; it cannot backfill every renewal while the app is closed. Production requires verified webhook delivery and durable shared storage before launch. Historical refunds for consumables also require webhook delivery rather than relying on snapshot absence.

Apple → RevenueCat server notifications should also be verified: the RevenueCat dashboard currently reports no notifications received. Do not replace its Apple notification URL with the app's RevenueCat webhook URL; these are different connections.

Sources:
- https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox
- https://www.revenuecat.com/docs/test-and-launch/sandbox/apple-app-store
- https://www.revenuecat.com/docs/api-v1/customers
- https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields

## Token pack loading fix (September 13, phone acceptance)

User reported successful sandbox subscriptions but Token packs stayed on Reload prices. Live App Store Connect had no consumable products; RevenueCat already contained the three package associations. Created the missing Apple consumables, English names/descriptions, review notes/screenshots, US availability and base prices:

| Product | Apple ID | US price | Tokens |
|---|---|---|---|
| craft.credits.small.v1 | 6811690447 | $4.99 | 200 |
| craft.credits.medium.v1 | 6811691221 | $9.99 | 500 |
| craft.credits.large.v1 | 6811691468 | $19.99 | 1200 |

Only the US storefront was enabled for current sandbox acceptance. Other launch storefronts remain to be aligned with the app's approved regional availability. No review submission or real purchase was performed. RevenueCat associations remain on the same product IDs; consumables do not unlock the creator entitlement.

The native Reload prices action now reports whether the selected package became available, rather than silently returning. It never grants Tokens. Built and installed the update on the connected iPhone. Actual Token-pack Apple checkout and resulting balance still need phone verification after Apple's product propagation.


## Subscription switch reconciliation fix (September 13, after phone checkout)

User confirmed Token packs work in Apple sandbox. Read-only RevenueCat and local ledger checks found the 200-Token and 1,200-Token transactions, each granted once. The stuck device queue contained a weekly product ID paired with a monthly store transaction ID already granted 850 Tokens. This was not a missing Token-pack payment.

- Native purchase delivery now uses the product ID from RevenueCat's returned store transaction, rather than the selected plan button. A deferred change returning an existing subscription no longer claims a new grant for the selected plan.
- The server resolves legacy mismatched weekly/monthly claims only from the authenticated user's verified Apple transaction. The real transaction's product determines the allowance. Consumables cannot substitute for subscriptions. An already-delivered receipt remains acknowledgeable when the latest-only provider snapshot advances; ownership, environment, and refund checks still apply. No client amount is trusted.
- The in-app weekly purchase action is disabled while monthly is active; Apple's own subscription management remains available for future changes.
- Sync notice is shorter and Retry is disabled while a sync is running. The durable queue is cleared only after server acknowledgment.
- 38 focused billing/access/commerce tests passed. Built, installed and launched on the connected iPhone (installation sequence 5072). After server restart, device preferences showed zero pending receipts; server observed two successful receipt acknowledgments and zero 409 conflicts. Rechecking the historical claim did not increase the wallet.

Policy clarification: Apple determines upgrade charges and prorated refunds, not a fixed $10 difference. Apple manages scheduled downgrades at renewal even if the in-app purchase button is unavailable. Cancellation stops renewals; it is not an automatic refund and does not remove Apple's refund process. Existing paid Tokens continue to roll over. No subscription Token-expiry migration was implemented: Apple's guideline 3.1.1 says purchased credits may not expire, and the current paywall already promises rollover. A future periodic service allowance needs a separate product/policy assessment, not simply renaming or expiring existing paid Tokens.

References:
- https://developer.apple.com/app-store/subscriptions/
- https://developer.apple.com/app-store/review/guidelines/#in-app-purchase
- https://support.apple.com/en-gb/118223

This is local iPhone sandbox verification, not a public production launch. The previously noted public backend/webhook requirements remain outstanding.


## Wallet purchase animation (September 13)

After a verified purchase, the root closes the paywall and navigates to Wallet in the sheet's onDismiss callback. Wallet scrolls to its balance card and waits 550 ms for navigation before presenting +N Tokens, a numeric balance transition, and success feedback. Reduce Motion uses an immediate balance update. The reward fades after three seconds. Account changes clear pending UI state.

The server returns the verified receipt's funded amount separately from this request's new grant. This lets a client finish presenting its own pending purchase after a delayed response or background sync without granting again. The client remembers presented receipt IDs per signed-in account; ordinary restore does not schedule a purchase animation, and repeated acknowledgments do not repeat it. Deferred plan changes use the real returned transaction. No optimistic balance increase is performed.

Focused billing/access/commerce checks: 38 passed, including new-grant versus replay receipt amounts. Device build/install succeeded; animation appearance and timing require the user's next sandbox purchase on the phone. No additional purchase was performed by the agent.
