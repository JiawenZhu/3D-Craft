# Gemini-first release acceptance

15 September 2026. The user explicitly approved releasing with Gemini first and adding cloud ChatGPT account connection later.

## Release behavior

- Gemini supplies prompt planning and concept images through https://3d-craft.web.app.
- The native image/planner pickers and Profile hide the deferred ChatGPT connection. Existing saved selections migrate to Gemini for new requests. A saved, previously approved ChatGPT request keeps its original provider and Token ceiling; it is never silently replayed as a paid Gemini request.
- External asset sharing to ChatGPT / Claude Code is unchanged.
- Generation readiness requires the cloud concept, planning and model services to be enabled. This operational signal permits phone installation; it does not certify App Review readiness.

## Canonical full-flow evidence

`scripts/verify_cloud_release_flow.py` ran with explicit paid-test opt-in against the canonical HTTPS origin, using a disposable Firebase account.

1. Generated an original frog in a teal raincoat with Gemini: **17 Tokens**. Visually inspected the resulting full-body concept.
2. Used that exact cloud concept as Hunyuan white-model input: **19 Tokens**.
3. Downloaded an **18,872,832-byte GLB**, validated its glTF 2 header and nonempty mesh primitives. Anonymous download was rejected.
4. Starting balance 200 → **164**, reserved balance **0**, **2** Firebase library records.
5. Idempotent replays returned the existing jobs. Removed the disposable account and cloud files; retained a deletion barrier.

Jobs: `cj-d3018a5b6de23a23e818dfbd838d1e9965cdeffdc8293ac6e5b417bb76dbc339`, `mj-dcc5c7e686b0ba2d676a0e80e32db4bae148d088f60656c04abaf3372bcfee8c`.

Evidence log: `/tmp/craft-cloud-release-flow.log`; local visual artifacts: `/tmp/craft-cloud-release-flow/`.

## Focused checks and limits

- 20 native AI-account, model-selection and source-selection checks passed, including saved-request price preservation and Gemini selection migration.
- 8 focused cloud API/concept checks passed, including missing-dependency readiness and disabled development purchases.
- This establishes cloud generation and accounting. Physical-phone rendering/export, exact-release screenshots, reviewer-account acceptance and final App Store disclosures still require completion.
- The earlier four-view provider test produced inconsistent camera angles; validation correctly rejected it as matching 3D input. Do not claim multi-view consistency from that test.

## Deployment and review access

- Source `f6c1255` pushed to GitHub `master` and `codex/app-store-cloud`.
- Cloud Run `craft-api-00016-rml` serves 100% of traffic. The canonical health response confirms Firebase storage and generation readiness. The authenticated catalog contains only Gemini.
- Built with the installed Xcode and successfully installed and launched on Jiawen's physical iPhone after reconnecting the device. Embedded service origin remains `https://3d-craft.web.app`. Device installation/launch does not establish complete physical-device acceptance.
- Existing App Review email login authenticated successfully. Wallet read returned 5,000 available test Tokens, no reservations; projects and private assets returned HTTP 200. No balance adjustment was made in this check.
- App Store Connect privacy disclosures are already published, covering user content, user ID, purchases, product interaction and email. Final SDK/disclosure reconciliation remains necessary.

## App Store and native-screen verification

- Xcode Cloud Build **13**, source `f6c125528964565a3c60ee25ce522874c2c70fc0`, completed Build and Archive with zero errors/warnings. App Store Connect processed it as VALID.
- Build `8ae0320a-c4a8-4a31-bfb3-f1ac7bdde6c7` is attached to version 1.0 (`d0c468c4-63c3-45dd-80f9-c25518539f6a`); relationship update and readback verified.
- Updated the walkthrough portion of App Review Information for Gemini, cloud storage, actual purchase verification and supported multi-view validation. Saved and reloaded to verify persistence; existing rights declaration was left unchanged.
- Native public-discovery → model → lighting → concept → external game brief → object gallery screen checks passed on iPhone and iPad simulators. Updated the capture test's canonical URL and its signed-out Objects selector. These checks do not exercise authenticated generation or purchase delivery.
- Added current iPhone discovery, lighting and game-brief screenshots to the existing App Store set (7 total). Captures: `/tmp/craft-gemini-listing/iphone/`. Added the current iPad discovery screenshot to its existing set (5 total). iPad captures: `/tmp/craft-gemini-listing/ipad/`.
- Not submitted for review in this pass. Follow the remaining concrete checks in release-readiness.md.
