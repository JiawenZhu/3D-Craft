# 3D Craft billing dashboard setup

Verified in RevenueCat on September 12, 2026 (dashboard UTC September 13).

Project: bbd24f9b. Test Store: appf875cd93fc.
Default offering: default / ofrng974d00ef04.
Creator entitlement: creator / entlfccc5b476b; weekly and monthly test products attached.

| Test product | ID | Renewal | USD | Credits |
| --- | --- | --- | --- | --- |
| Creator Weekly | craft.creator.weekly.v1 / prod59c9fd22da | Weekly | 4.99 | 250 |
| Creator Monthly | craft.creator.monthly.v1 / prod49179c0681 | Monthly | 14.99 | 850 |

No yearly plan or free trial. CRFT (Craft Credits) grants on purchase or renewal: 250 weekly and 850 monthly; both have expiration Never. The default offering metadata contains the product description, website, 15% service fee, $.01 usage denomination and estimated 4 / 13 complete creations at 62 credits each. These are estimates, not guaranteed counts. Extra images, models, chat and retries affect usage.

These are TEST STORE products, not activated Apple subscriptions. Production SDK integration, trusted settlement and Apple production store credentials/products still need completion. Metadata production_billing_enabled is false; it is informational and is not a payment enforcement mechanism.

App Store Connect app created: 6811466883, name 3D Craft, bundle studio.craft.ios, SKU 3d-craft-ios, English US, iOS version 1.0. Draft only, not submitted.

## App Store Connect draft saved

App ID 6811466883. Subtitle: AI concepts to 3D characters. Primary Graphics & Design; secondary Productivity. English promotional text, description, keywords and marketing website saved and read back from a separate page. Review contact remains incomplete; Apple validates that section independently. Support/privacy URL not filled because the public pages have not been verified. The provided root website currently shows the older Forma Studio interface and needs launch-content alignment.

Uploaded four native 2D concept screenshots each for iPhone 6.9-inch and iPad 13-inch; both showed 4 of 10 screenshots with no upload errors. iPhone 6.5-inch inherits the 6.9-inch set.

Apple subscription group 22380580, 3D Craft Creator, English group localization saved.
Monthly Apple product 6811468389, craft.creator.monthly.v1, one month, Creator Monthly, description “850 credits monthly for AI concepts and 3D creations.” US base $14.99 and Apple-generated currency equivalents saved.
Weekly Apple product 6811468944, craft.creator.weekly.v1, one week, Creator Weekly, description “250 credits weekly for AI concepts and 3D creations.” US base $4.99 and Apple-generated currency equivalents saved.
Both have draft review notes explaining credit allowances and usage estimates; no trial or Family Sharing enabled. Country availability, final review screenshots and binary purchase tests remain pending.

App download price configured as $0.00, with paid subscriptions separate. No review submission or release performed.

RevenueCat App Store connection form has name and studio.craft.ios filled but cannot be completed without the required SubscriptionKey .p8, Key ID and Issuer ID. No credentials invented or exposed. Apple products are not yet linked into RevenueCat; the existing default offering and grants currently use Test Store products only.
