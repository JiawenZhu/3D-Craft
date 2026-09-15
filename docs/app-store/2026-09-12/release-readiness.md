# Release readiness — not ready for submission

This assessment distinguishes local native capture success from an operational App Store release. The user chose iPhone + iPad, with paid credits and subscriptions at launch.

## Must implement before release

1. **Production generation service.** `server/mobile.py:1` describes a loopback-only review API with no production identity or billing. `ios/CraftStudio/Sources/CraftStore.swift:34` defaults to a saved/review URL or localhost. Current phone builds depend on a Mac gateway. Ship an authenticated HTTPS backend that works with the Mac off, durable jobs and private asset storage. Do not expose the review server unchanged.
2. **Private file access.** `server/app.py:463` serves stored files without a per-user authorization check. Add ownership enforcement or scoped signed URLs before public hosting; verify another account cannot read private uploads or outputs.
3. **Real StoreKit fulfillment.** `CraftStore.swift:510–511` rejects purchases outside local testing. Replace the development purchase ledger with verified production/Sandbox transactions, idempotent credit fulfillment, subscription renewal handling, refunds/revocations, restore and account recovery. Disable local refill paths in release.
4. **Privacy and third-party AI consent.** Finish production data handling, retention and deletion. Provide clear consent before personal content is sent to third-party AI. Implement account deletion if the final app creates accounts. Review optional ChatGPT integration authorization for commercial distribution. Audit required-reason APIs and SDK privacy manifests against the final binary.
5. **Operational launch verification.** Test real iPhone/iPad on an independent network, interrupted generation/recovery, persistence, file exports and out-of-credit flows. Run StoreKit Sandbox/TestFlight purchase and subscription lifecycle checks. Confirm accessibility, content safeguards and device layouts.

## Must configure or confirm

- Confirm explicit App ID registration status in Apple Developer; create the 3D Craft app record if absent.
- Final credit amounts, prices, subscription period and benefits. Current StoreKit test values are not approved commercial terms.
- Customer support email; operator details; production privacy/support URLs and retention/deletion promises.
- Reviewer contact, live demo access/instructions, distribution regions, age-rating answers, privacy disclosures and encryption classification from actual implementation.
- Release version/build, accepted distribution toolchain, App Store signing and distribution archive. Current development IPA is not the submission artifact.
- Final screenshot compositions must use exact app captures. Re-capture any UI changed while implementing production requirements.

## Verified locally

- Native screenshot capture test passed on iPhone 17 Pro Max and iPad Pro 13-inch simulators.
- Seven PNG captures for each family; iPhone 1320 × 2868, iPad 2064 × 2752, RGB.
- Original concept and actual 3D model views captured separately. Promotional hero images are labelled Concept artwork.
- English/Chinese draft field lengths checked; keywords measured in UTF-8 bytes.
- Account financial setup observed active; this does not validate app billing functionality.

Apple sources: [Review guidelines](https://developer.apple.com/app-store/review/guidelines/), [privacy disclosures](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/). Reviewed 12 September 2026. Complete declarations against the final implementation, not this development snapshot.
