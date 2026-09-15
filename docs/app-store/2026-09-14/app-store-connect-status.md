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
- Version 1.0 now has processed build 3 attached and saved. Apple build ID: `d423e311-2ff4-4b24-8ae9-e7f33697ba96`; processing state `VALID`, audience `APP_STORE_ELIGIBLE`, iPhone and iPad supported, app icon included. The build-selection requirement is resolved.
- Consumable Token-pack delivery has been verified in the cloud. Cloud generation, subscription delivery, and the other release blockers remain documented in release-readiness.md. Publishing privacy answers does not resolve those implementation gaps.
- Review sign-in and contact fields are populated in the live dashboard. Credentials intentionally omitted here. The account still requires full end-to-end cloud acceptance.

No Add for Review action was performed.

Cloud Build 2 from eca8713 succeeded on Xcode 26.6 with no warnings or errors. Cloud Build 3 also succeeded, including Archive and App Store Connect preparation; Apple processed it as version 1.0, build 3. The authenticated App Store version/build relationship was verified after saving the selection. App Store SDK build is 23F81a; the early-beta upload error no longer applies to this cloud artifact. No Add for Review or Submit for Review action was performed because product/backend acceptance is incomplete.
