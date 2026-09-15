# 3D Craft — native iOS review app

SwiftUI iOS 17+ client for the existing 3D Craft studio. This is a local review build, not an App Store release.

## Start the services

From the repository root, keep both commands running in separate terminals:

```sh
RODIN_MOBILE_DEVELOPMENT=1 RODIN_PORT=8001 venv/bin/python -m server.app
npm run dev -- --host 127.0.0.1
```

The mobile API intentionally accepts loopback connections only. The iPhone simulator can access the Mac's loopback server. For an owner's physical-device development build, the private LAN gateway below can forward the mobile API without restarting generation jobs. Production identity, receipt validation and public hosting remain separate release work.

## Build

Install Xcode and XcodeGen, then:

```sh
cd ios
xcodegen generate
xcodebuild -project CraftStudio.xcodeproj -scheme CraftStudio -destination 'platform=iOS Simulator,id=12D14131-D489-4300-815F-E7A77C841E1E' -derivedDataPath .build build CODE_SIGNING_ALLOWED=NO
./scripts/launch-review.sh 12D14131-D489-4300-815F-E7A77C841E1E
```

Use an available simulator UDID from `xcrun simctl list devices available` on another Mac. GLTFKit2 0.5.15 is resolved by Swift Package Manager. The bundled cat GLB is copied from `games/forma-playground/assets/lantern_cat.glb`; generated binary assets are ignored by Git and must be supplied when moving this checkout.

## Review flow

1. Create: take a photo on a physical device, choose Photos/Files, enter text, or load the clearly labeled explorer reference.
2. Confirm the number of concepts and the total Token cost. Provider generation is real and uses the studio's configured provider account.
3. Select a concept; refinement and 3D generation each require a separate cost confirmation.
4. Open a completed GLB in the native viewer. Orbit, zoom, material/solid/wire, export and compatible game selection are available.
5. Library separates your generated assets from studio examples. Profile controls language, connection and wallet access.
6. StoreKit products are local tests in the simulator. No real customer payment is enabled. Do not present local credit fulfillment as production receipt verification.

The detailed scope, billing proposals and release gates are in `docs/business/3D_CRAFT_IOS_PRODUCT_BUSINESS_PLAN_2026-09-09.zh-CN.md`.

The launch script supplies Xcode developer framework search paths required by StoreKitTest. A plain simulator launch remains safe but may skip local purchase activation. Never use these test-only settings for a distribution build.

## Free generation testing

The loopback development backend now grants 1,000 test Tokens on first bootstrap. No subscription is required. Tap the balance or Profile → Free generation testing to refill up to 1,000. This is explicitly a development credit, recorded separately from StoreKit transactions. Optional billing screens remain under a disclosure section. Real upstream generation still uses the configured provider account.

## Connection recovery

Background refresh failures show a nonmodal reconnect banner and retry the full session/bootstrap connection every three seconds. Existing projects and drafts remain visible. Simulator review credentials persist inside the private app container because unsigned simulator Keychain writes may fail. Keep port 8001 running while generation is active; do not restart the provider server during a review job.

Verified on 2026-09-09: 24 backend tests and 3 native unit tests passed, including a failed-connection test asserting no modal alert. A real concept produced asset `a-2181c954df` (95,216 triangles, 2K texture); native viewing and the export share sheet were exercised, and exported GLB bytes matched the server file. This does not establish production hosting or physical-device connectivity.

## Native visual controls

The app now uses a white base with user-selectable Soft lavender and Emerald green themes. Profile → Appearance applies the choice immediately and saves it on this device. Theme colors affect interface surfaces, controls and the viewing stage, while preserving the real model materials. English and Chinese remain available.

### Motion

The interface has a shared motion language in `CraftStudio/Sources/CraftMotion.swift`: a fixed set of
spring/duration tokens, staggered entrances, depth and surface levels, press and lift button styles,
a specular sweep, a shimmer, an animated segmented control, a floating tab bar and a semantic haptics
map. Screens compose those rather than hand-rolling animations, which is what keeps the app feeling
like one product.

Every animation is gated. `CraftMotion.gated(_:_:)` is the single decision point, and continuous
ambient loops (drift, breathe, shimmer, sweep, the SceneKit idle sway) are additionally suppressed by
Increase Contrast and by the `craftAmbientMotion` environment gate. Under Reduce Motion the app still
reads correctly: entrances cross-fade, selection is carried by colour, the ring and the checkmark
rather than by movement, and nothing loops.

Create, the horizontal concept carousel, the 3D studio and Profile follow the approved mobile designs. Open an asset's Lighting & model details disclosure to choose Studio, Rim, Sunset, Night or Flat. The floating sliders button adjusts lighting and exposure; the fullscreen button expands the actual viewer. Switching lighting preserves camera framing. See `design-qa.md` for the 2026-09-10 sample review and `ACCEPTANCE.md` for wider release boundaries.

### Photo-to-3D source selection

Create uses your photo/file/camera reference or your own description. It generates 1–4 candidate camera views (4 by default, 15 test Tokens each) using the website's shared concept pipeline. Explicitly tap the original or a concept image before opening the 3D confirmation. That screen previews the exact source, engine, quality and effort. Confirming reserves 55 test Tokens for the model; it does not generate replacement concepts. Original/direct mode skips concept charges. Library examples never replace your creation input.

Selected images survive returning to a project and app relaunch. Multiview is offered only for a checked view set; the server also validates source ownership, sibling set, camera directions and provider compatibility. The native generation journey follows actual server stages. Generated camera views can still fail consistency checks; in that case choose a single image.

## Physical iPhone review (2026-09-12)

A signed Debug build was installed and launched on the owner's iPhone 17 Pro Max using the existing Apple Development team. First launch displays iOS's Local Network permission prompt; allow it to connect to the Mac.

`ios/scripts/phone-review-gateway.py` reads the ignored `.env.phone-review.json` configuration and binds only to the configured Mac LAN address. A random private path gates mobile API and read-only model-file access; requests without it receive 404. The upstream stays on loopback port 8001. The development build receives its API base through the `CRAFT_REVIEW_URL` build setting; no private URL is committed. Normal builds retain the simulator default.

Keep the Mac awake, the API and gateway running, and the phone on the same Wi-Fi. The phone must grant Local Network access before gallery/generation connectivity can be verified. This is a local development installation, not TestFlight. The browser-game launcher still uses its existing loopback-only web configuration and requires separate physical-device adaptation.

### Physical iPhone connection builds

Use `python3 ios/scripts/install-phone-review.py` for this Mac's paired test phone. It reads the ignored `.env.phone-review.json`, embeds the gateway only in the Debug build, verifies the built Info.plist, then installs and launches the app. A generic iPhone build without `CRAFT_REVIEW_URL` is not a configured LAN review build. Do not use the review installer for App Store archives.

Physical devices now reject saved loopback server addresses and use the configured gateway. Missing configuration shows a settings action instead of retrying the phone's own localhost. The app persists the resolved address across later upgrades, refreshes identity once after a 401, and reports sign-in, network, or missing-configuration failures separately. Automatic retries back off to 30 seconds and stop for failures that need sign-in or configuration.


### Cloud migration (September 14, 2026)

The private LAN instructions above describe the previous acceptance setup.
All current app builds select `https://3d-craft.web.app`; saved local URLs are
ignored. The phone installer now checks the cloud API and its generation-readiness
flag before installation, so the current phone app is not replaced prematurely.
See `docs/firebase-cloud-migration.md` for the deployed storage migration and
remaining generation/payment release gates.
