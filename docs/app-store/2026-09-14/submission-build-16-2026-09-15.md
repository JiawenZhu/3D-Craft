# App Store build 16 submission receipt

Submitted September 15, 2026 at 03:01:53 America/Chicago (08:01:53 UTC).

- App: **3D Craft**, Apple ID `6811466883`, bundle `studio.craft.ios`.
- Version: **1.0 (16)**; **Waiting for Review**.
- Submission: `8e84ff37-5d1e-4e4e-9043-35ce6bc87d8a`.
- App Store build: `1c2a4ffd-f5df-4293-9887-b5961e71c78d`; VALID and APP_STORE_ELIGIBLE.
- Xcode Cloud run: `29ba2827-dcb0-4140-9e72-035644e0ca33`; Build and Archive succeeded using Xcode 26.6 (17F113).
- App source: `4a8257a714fea8f352f4624e5b3e03c329f43a17`, pushed to both GitHub master and codex/app-store-cloud before the build.
- Production backend: `https://3d-craft.web.app`, Cloud Run revision `craft-api-00020-kcr`.
- Build 15 was withdrawn only after build 16 became VALID, and replaced in the version's build selection.

## Items submitted together

App Store Connect displayed **7 Items Submitted**, **Waiting for Review**, and **Draft Submissions (0)**. The seven items are:

| Item | Apple ID |
| --- | --- |
| iOS App 1.0, build 16 | 6811466883 |
| Mini Pack — 200 Tokens | 6811690447 |
| Creator Pack — 500 Tokens | 6811691221 |
| Studio Pack — 1200 Tokens | 6811691468 |
| Creator Monthly — 850 Tokens | 6811468389 |
| Creator Weekly — 250 Tokens | 6811468944 |
| 3D Craft Creator subscription group | 22380580 |

## Review setup completed

- Captured the real native Token-pack and subscription screens in the simulator and uploaded them to all five paid products as review screenshots. The screenshot capture test passed; it performed no purchase. The subscription capture shows an existing active monthly plan.
- Corrected stale subscription review notes and localized descriptions: subscription Tokens expire each period with no rollover; separately purchased Token packs never expire. Existing prices were preserved.
- Set purchase/subscription availability to the app's existing 173 territories, excluding China mainland and Vietnam. Automatic availability in new territories remains off. The app territory selection itself was preserved.
- Saved build 16 TestFlight instructions, including two-image completion without restarting, authenticated selected-image previews, AI-sharing consent, and immediate accepted-job display.
- Updated reviewer instructions for build 16 while preserving the existing reviewer credentials/contact and content-rights declaration. Existing declarations were not independently recertified.
- Verified the dedicated reviewer email login against Firebase and successfully loaded authenticated wallet and project endpoints. No credentials are stored in this receipt.
- Verified production health, privacy, terms, support and account-deletion pages return HTTP 200. Published App Privacy information and existing iPhone/iPad listing screenshots remain present.

## Scope and release status

Manual release remains selected. Apple approval and public App Store availability have **not** occurred. This receipt confirms submission, not completion of every physical-device billing lifecycle or gameplay acceptance test. Existing limits in the release evidence remain applicable. The follow-up Git commit contains only this release record, review screenshots and TestFlight notes; it does not change the app binary.

[Open the submitted review](https://appstoreconnect.apple.com/apps/6811466883/distribution/reviewsubmissions/details/8e84ff37-5d1e-4e4e-9043-35ce6bc87d8a)

## September 15 EULA metadata correction and resubmission

Apple's automated 3.1.2 rejection at 04:43 America/Chicago identified a missing functional Terms of Use (EULA) link in the App Store product-page metadata. The app has no custom EULA configured. Added Apple's standard EULA URL and the existing privacy-policy URL to the English (U.S.) App Description, preserving all other description text. The saved description is in app-description-en-US.txt.

Verified the standard EULA URL resolves to Apple's Licensed Application End User License Agreement, and App Store Connect saved the exact updated description. Selected Update Review and Resubmit to App Review. At **2026-09-15 19:04:35 UTC (14:04:35 America/Chicago)**, the same submission returned to **WAITING_FOR_REVIEW**; the review page listed all seven items as Waiting for Review, including **1.0 (16)**. No app code, pricing, subscription entitlement or binary changed. Apple approval remains pending.
