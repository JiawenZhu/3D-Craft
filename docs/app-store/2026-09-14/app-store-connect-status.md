# App Store Connect status — 14 September 2026

## Completed in the live dashboard

- Privacy Policy URL saved as https://3d-craft.web.app/privacy.
- User Privacy Choices URL saved as https://3d-craft.web.app/delete-account.
- App Privacy published; the dashboard confirmed “Published a few seconds ago by Jiawen Zhu”.
- Declared Email Address, Photos or Videos, Other User Content, User ID, Purchase History and Product Interaction. All are linked to the user for App Functionality. User ID and Purchase History also declare Analytics for RevenueCat. No tracking purpose selected.

Basis: Firebase account identity, persisted user images/prompts/models, user votes, and RevenueCat custom Firebase user IDs/purchase history. Device-local profile display name is not independently collected by CraftProfile. Reassess against any new release features or SDK integrations before submission.
RevenueCat reference: https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy

## Remaining

- Content Rights is unset. The app accesses user-submitted third-party content; the available Yes answer also attests necessary rights. Owner confirmation requested rather than asserting rights from source code.
- Version 1.0 has no build selection available; its Build section requests uploading a build. No binary uploaded or attached in this update.
- Live cloud generation and purchase delivery remain release blockers documented in release-readiness.md. Publishing privacy answers does not resolve those implementation gaps.
- Review sign-in and contact fields are populated in the live dashboard. Credentials intentionally omitted here. The account still requires full end-to-end cloud acceptance.

No Add for Review action was performed.
