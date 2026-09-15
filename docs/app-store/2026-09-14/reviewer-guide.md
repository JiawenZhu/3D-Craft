# 3D Craft — reviewer walkthrough draft

**Do not submit this draft until the cloud generation, purchase delivery, deletion and community checks in release-readiness.md pass.** Instructions below describe the intended release flow, not proof that today's cloud build supports every step.

App: 3D Craft (studio.craft.ios), App Store ID 6811466883.
Website and service origin: https://3d-craft.web.app/
Support: https://3d-craft.web.app/contact
Privacy: https://3d-craft.web.app/privacy
Terms: https://3d-craft.web.app/terms

## Access

Use the email sign-in option and the dedicated demo credentials supplied in App Store Connect's App Review Information. Review access must remain available throughout review, with sufficient server-controlled generation allowance. It must not require a developer's Mac, personal ChatGPT account, Apple sandbox account, or a private network. The final demo account and its complete flow have not yet been certified for this release.

## Creation and library

1. Browse Characters and Objects for public examples. These are separate from the signed-in user's private creations.
2. Sign in, describe an idea or select a reference image, and generate concepts with Gemini. This release does not offer own-account ChatGPT generation. No personal AI-provider account or Mac service is required.
3. Select a concept and choose Make this 3D. Review the chosen model and displayed Token cost before confirming. Where the selected engine supports it, additional views or an optional description can guide generation; capabilities differ by engine.
4. Wait for completion or leave the screen and return to the library. Open the completed model, rotate and zoom it, and change lighting or display mode.
5. Sign in to the website with the same app account to inspect the same private creations. Access is tied to the Firebase user; the website is not a public listing of private work.

## Export and games

Export model uses iOS sharing. The game handoff lets the user select models and share those files with a short editable brief to an external agent. 3D Craft does not automatically build a game when the user shares these files.

The Games feature presents community-submitted links and votes. Games currently open with Safari services or the system browser. Do not describe this feature as absent from the app. Public submissions, reporting, blocking and moderation must be verified before submission.

## Purchases

Subscriptions and consumable Token packs use Apple's in-app purchase flow with RevenueCat verification. RevenueCat is not a separate checkout or Apple Pay replacement. Apple controls payment authentication, including any available biometric confirmation.

The localized purchase price and subscription period must be visible before confirmation. Successful verification must credit the correct signed-in account exactly once, then open Wallet and show the confirmed increase. A pending purchase or delayed verification must not be presented as delivered Tokens.

Subscription cancellation stops future renewal; access and allowance must follow the verified paid period. Apple's refund decisions and subscription-change handling apply. Do not promise an app-calculated price difference or that Apple can never issue a refund. The intended distinction is that subscription allowances expire with their period while purchased Token packs persist; this requires verification in the cloud ledger before being stated as a release feature.

## Final reviewer handoff

Before copying these notes, replace this draft with instructions tested on the exact uploaded build; confirm demo access, model generation, purchases, restoration, deletion, and community controls. Add the release build number and any genuine restrictions or special steps. Never include production API secrets, personal Apple credentials, or a local backend address.
