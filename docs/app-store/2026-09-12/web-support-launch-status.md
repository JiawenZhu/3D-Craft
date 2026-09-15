# Web branding and support pages — September 12, 2026

Implemented 3D Craft branding in the existing web studio, emerald accents from native CraftAppearance (#9CDCC3, #D6F2E7, #68C2A0, #1C654D), and these routes:

- /privacy
- /terms
- /policy
- /contact (also /support)
- /delete-account

Support/developer email confirmed: zhujiawen519@gmail.com. Apple review phone confirmed: +1 408 599 4164 (not published on the support website).

CareerVivid source pages were inspected as structural references. CareerVivid-specific age limits, refund guarantees, resume functionality and service providers were not copied. Pages describe 3D Craft data flows and AI provider involvement; no fixed retention period or automatic deletion guarantee is invented. The email deletion request page does not replace the in-app account-deletion requirement for a release that supports account creation.

Validation: TypeScript and Vite production build passed. Contact page visually inspected. Privacy, Terms, Policy, Deletion and main studio routes rendered in the production preview without desktop horizontal overflow. Mobile acceptance and live hosting verification remain pending.

Publishing attempt failed because Firebase CLI authentication expired. Started reauthentication; browser is at Google account selection for Firebase CLI. The user took browser control before completion. No deployment succeeded.

App Store draft: entered support URL /contact, copyright 2026 Jiawen Zhu, and contact name, email and phone. Save clicked; immediate readback had no nonempty alerts. Independent persisted readback remains pending. Privacy policy URL /privacy and privacy choices URL /delete-account entered and Save clicked; completion/readback not yet verified when browser control was taken. Do not treat these URLs as live until hosting succeeds.

Still needed before submission: finish hosting sign-in/deployment; confirm age/content scope and enforce it; validate App Privacy labels against production SDKs/data use; confirm content rights and applicable trader status; complete production purchases/RevenueCat linkage; test account deletion, privacy consent, billing and real generation on release build; upload the release binary and complete review-access information. No App Store review submission performed.

## Deployment completed

After user renewed Firebase sign-in, Firebase Hosting deployment to forma-studio-2026 succeeded (release complete). Live browser checks confirmed the new 3D Craft studio, Privacy, Terms, Usage/Billing and Data Deletion routes. The first contact visit used an older cached document; a fresh release-query HTTP check confirmed the new document and the live bundle containing the Contact page and support email. Existing open tabs may need a refresh. App Store Connect readback confirmed privacy and privacy-choices URLs saved. No App Store submission performed.
