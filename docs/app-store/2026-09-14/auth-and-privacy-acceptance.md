# Authentication and AI privacy release update

15 September 2026.

## Implemented and verified

- Native Google authentication uses the canonical HTTPS origin. Only the active ASWebAuthenticationSession callback is accepted, with unpredictable per-attempt state, ten-minute expiry and unique required fields. Firebase verifies the ID token and UID before account publication. The website bridge preserves state and rejects requests without a valid state; Firebase Hosting deployment succeeded.
- Enabled Sign in with Apple for studio.craft.ios as a primary App ID. Created a dedicated Apple authentication key and configured the Firebase Apple provider with the native bundle ID. Private key material remains outside the repository and app bundle.
- The installed app and its embedded provisioning profile both contain com.apple.developer.applesignin = Default. The user initially reported Apple error 1000 and subsequently confirmed that Apple sign-in works. The initial error's cause is unconfirmed; no capability mismatch was found.
- Apple sign-in uses a hashed nonce and per-request state; Firebase validates the Apple identity token. A cancelled or stale authorization does not publish a new account. Apple credential revocation is checked on app activation and notification.
- For Apple-linked account deletion, native authorization must match the linked Apple subject. Firebase reauthentication must return the same UID before access is revoked and the durable deletion request is sent. This path still requires an end-to-end disposable Apple-account test.
- Added separate, per-account permission before sending prompts/conversation/reference images to Google Gemini or concepts/references/3D prompts to fal.ai and the selected model provider. A declined first request is not submitted; no generation is queued or charged. Profile offers a reset control. Existing jobs already accepted by a provider are not cancelled by permission reset.
- Added the app privacy manifest. Own-container preferences use CA92.1; cache-file timestamp eviction uses C617.1. Six collected categories match the published app disclosures: email, user ID, photos/videos, other user content, purchases and product interaction. All are linked to account, none used for tracking. RevenueCat's bundled manifest and GLTFKit2's manifest are present; the app links purchases to its own Firebase UID even though the SDK's generic manifest marks purchase history unlinked.
- Native tests: 65 executed, one intentionally skipped, zero failures. Includes callback validation and AI-recipient/account isolation checks. Web production build passed; existing bundle-size advisory remains.

## Evidence and limits

- `/tmp/craft-release-auth-tests.log`, `/tmp/craft-privacy-tests.log`
- `/tmp/craft-apple-phone-install.log`: successful physical installation and launch against https://3d-craft.web.app.
- `/tmp/craft-auth-hosting-deploy.log`: successful Hosting release.
- Source `1de40b8`, including the privacy prompt and manifest, was installed and launched on the physical phone and processed as Xcode Cloud / App Store build 15.
- An interactive simulator test using the authorized reviewer account presented the Google Gemini permission alert, selected “Not now”, and verified the request-not-sent response. Test passed; `/tmp/craft-ai-consent-ui-test.log` and `/tmp/craft-ai-consent-review.png`. Temporary test credentials were removed from the checkout. This does not claim live fal permission acceptance or an end-to-end Apple deletion test.
- App Store version 1.0 (15) is Waiting for Review. See [submission receipt](submission-2026-09-15.md).
