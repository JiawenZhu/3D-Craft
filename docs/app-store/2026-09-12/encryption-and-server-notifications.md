# Encryption and purchase connection — September 12, 2026

## Completed and verified

- Added `ITSAppUsesNonExemptEncryption = false` to `ios/CraftStudio/Configuration/Info.plist` and the corresponding setting in `ios/project.yml`.
- Reviewed native networking, CryptoKit SHA256 fingerprint usage, and resolved dependency GLTFKit2. No custom encryption implementation found. The current Apple OS encryption usage supports the exempt declaration; reassess if dependencies or encryption change.
- Release simulator build succeeded using `/tmp/craft-encryption-check`; built app Info.plist readback returned Boolean false. This is local build verification, not an uploaded App Store binary.
- Generated the app-specific shared secret in Apple. Secret remains in App Store Connect, not this repository. RevenueCat marks this credential legacy for StoreKit 1; current app targets StoreKit 2.
- Created Apple In-App Purchase key named `3D Craft RevenueCat`, key ID `6MB43YCRUF`. Private key saved outside the repository under the user's restricted `.config/3d-craft/apple` directory (directory 0700, file 0600).
- Created RevenueCat App Store app `appb88bdcb0f7` in project `bbd24f9b`, bundle `studio.craft.ios`. Uploaded In-App Purchase key; dashboard reports **Valid credentials**.
- Copied the exact RevenueCat Apple Server Notification URL to both Production and Sandbox Server URL fields in App Store Connect app `6811466883`. Saved each and verified both displayed on the app information page. Current Apple form exposed no notification-version selector.

## Still pending

- No end-to-end sandbox purchase/renewal notification test has run. RevenueCat currently reports no notifications received.
- RevenueCat SDK, production credit fulfillment, App Store product mapping/offering attachment, and trusted settlement remain separate unfinished release work. Creating the store connection does not enable functioning paid purchases by itself.
- Optional App Store Connect API credential for automated product import/price updates remains unconfigured. No broad API key was created.
- DSA: opened Contact Information Verification and entered authorized support email, unsaved. Await public address/P.O. Box and explicit permission for a publicly displayed phone number. Existing App Review phone authorization is private-review-only. Do not automatically publish the account's private address. Verification and trader self-assessment remain outstanding; app-level non-trader status has not been changed.

## References

- https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
- https://www.revenuecat.com/docs/platform-resources/server-notifications/apple-server-notifications
- https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/

## Availability and DSA follow-up

- User supplied public DSA address; entered street, city, Illinois, United States, and postal code in the open verification form. Address is intentionally not duplicated in repository documentation. Form remains unsaved pending public-phone authorization and Apple verification.
- Configured launch availability in 173 countries/regions, excluding China mainland and Vietnam per user instruction to omit territories with additional game licensing. Saved and verified both rows show **Not Available**, while selected territories show **Available on App Release**.
- Disabled automatic availability in future App Store territories so new licensing requirements can be reviewed first.
- Apple's app-information reference explicitly lists China mainland game approvals and Vietnam game licensing. Korea's additional rating classification has content-dependent criteria; current app is Graphics & Design / Productivity with a 9+ global rating and does not meet the listed mature-game triggers. This is a launch distribution choice, not an assertion that 3D Craft is legally classified as a game in every jurisdiction or an exhaustive worldwide legal opinion.
- Reference: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information

## Dedicated public phone

User authorized Vapi number +1 (747) 281-1202 for public use. Configured dedicated 3D Craft assistant and added the number to the website and DSA form. Apple advanced to email OTP verification; waiting for user input. Phone and documentation verification are still pending. See docs/support/vapi-setup-2026-09-12.md.
