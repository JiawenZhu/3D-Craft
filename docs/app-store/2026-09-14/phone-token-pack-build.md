# Installed Token-pack test build

14 September 2026: version 1.0, build 2026091402, bundle studio.craft.ios.

Signed Debug build passed. Apple's device tools confirmed installation and launch on Jiawen's connected iPhone (installation sequence 5264). The built Info.plist was checked for the canonical https://3d-craft.web.app origin.

The Xcode project was regenerated and opened. Its Run scheme no longer enables the local Products.storekit simulator, so device purchase testing follows Apple's sandbox and RevenueCat/cloud verification.

Included: delayed Wallet animation acknowledgement, separate sandbox balance label, account-safe wallet response handling, and removal of the Studio connection settings section. Cloud consumable delivery was verified separately using an existing sandbox receipt, including retry without duplicate credit.

Scope: user-authorized Token-pack device testing. Cloud generation and subscription delivery remain incomplete; this installation is not App Store readiness or submission. The physical-device animation and Apple purchase confirmation remain for the user's acceptance test. The default full-readiness installer gate was not changed.
