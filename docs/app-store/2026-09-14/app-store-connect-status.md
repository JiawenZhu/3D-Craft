# App Store Connect status — 14 September 2026

## Completed in the live dashboard

- Privacy Policy URL saved as https://3d-craft.web.app/privacy.
- User Privacy Choices URL saved as https://3d-craft.web.app/delete-account.
- App Privacy published; the dashboard confirmed “Published a few seconds ago by Jiawen Zhu”.
- Declared Email Address, Photos or Videos, Other User Content, User ID, Purchase History and Product Interaction. All are linked to the user for App Functionality. User ID and Purchase History also declare Analytics for RevenueCat. No tracking purpose selected.

Basis: Firebase account identity, persisted user images/prompts/models, user votes, and RevenueCat custom Firebase user IDs/purchase history. Device-local profile display name is not independently collected by CraftProfile. Reassess against any new release features or SDK integrations before submission.
RevenueCat reference: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy

## Remaining

- Content Rights is completed in the live dashboard: “Yes, this app has the necessary rights to its third-party content.” This was observed already saved; it was not inferred from source code.
- Version 1.0 has no build selection available; its Build section requests uploading a build. No binary uploaded or attached in this update.
- Consumable Token-pack delivery has been verified in the cloud. Cloud generation, subscription delivery, and the other release blockers remain documented in release-readiness.md. Publishing privacy answers does not resolve those implementation gaps.
- Review sign-in and contact fields are populated in the live dashboard. Credentials intentionally omitted here. The account still requires full end-to-end cloud acceptance.

No Add for Review action was performed.

Cloud Build 2 from eca8713 succeeded on Xcode 26.6 with no warnings or errors. The workflow was then updated with App Store Connect archive preparation and Cloud Build 3 was started. An archive upload and processed build selection are not yet verified by this status update.
