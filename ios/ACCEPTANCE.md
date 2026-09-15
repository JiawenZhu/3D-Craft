# Native iOS local review acceptance — 2026-09-09

Requested delivery: a SwiftUI implementation of the approved dark/coral/lilac designs, using the existing photo/text → concepts → 3D workflow, running on this Mac so the user can inspect it. Later user direction explicitly makes generation testing free and makes StoreKit purchases optional.

## Implemented review flows

| Requirement | Current evidence |
| --- | --- |
| Native iOS, computer preview | CraftStudio SwiftUI/Xcode project; installed on iPhone 17 Pro simulator; live serve-sim browser canvas at http://localhost:3200 |
| Existing visual direction | Create, concept, asset, library, profile and game-selection native screens; actual frames in `docs/design/ios-2026-09-09/implementation` |
| Photo / album / file / text input | Native camera, PhotosPicker and fileImporter; image review includes rotation, centered crop and single-subject confirmation. Camera requires a real device. |
| Separate concepts and 3D | 1–4 candidate views at 15 test Tokens each (default 4); refinement 15; selected-concept model generation independently confirmed at 55. No automatic model purchase. |
| Real output | Actual 2K concepts and generated asset a-2181c954df: 95,216 triangles, 2K texture, 9.09 MiB GLB. User also generated a separate scene asset during review. |
| Inspect and export | Native SceneKit/GLTFKit2 material/solid/wire viewer, orbit/zoom; full-resolution concept inspector; actual share sheet opened, exported cat GLB hash equals server source. |
| Use selected character in game | Actual selected cat rendered in native WKWebView Lanternfall; explicit type/game/facing selection; no silent default-model fallback. Native game screenshot records selected cat appearance and running HUD. |
| Library | Owned assets separated from examples; search, saved project/concept versions, favorites, cached library metadata on cold start. Uncached images/models still need connection. |
| Free testing | Initial/refill-to-1,000 development Tokens, no subscription needed; optional local StoreKit testing clearly labeled. No customer charges enabled. |
| Reliability | Persistent session and drafts; durable server jobs; silent reconnect; persistent uncertain submission keys prevent repeated generation on retry. Existing server was not restarted during live jobs. |
| English and Chinese | Native navigation, generation, image inspection, viewer status, wallet and game selection; actual language-toggle UI test. |

## Verification scope

Backend suite: 24 tests passed. Native unit suite: 5 passed, including failed background connection, pending request persistence across relaunch, and explicit-new-request release after a terminal result. Native free-credit/language/generated-model/game-entry UI test passed. Browser game launch validation and game asset routing suites passed. The native game was additionally visually inspected; WKWebView existence alone was not treated as game-render proof.

Tests involving real generation use the existing configured provider account. Test Tokens are development accounting, not a claim that provider computation is free.

## Production release gates

This is the requested local review app, not an App Store/TestFlight release. The business plan separately schedules Apple login/cross-device identity, private cloud file authorization, verified production IAP lifecycle, account deletion/privacy/support, physical-iPhone camera/network/performance testing, and paid-beta quality/cost evaluation. Those gates have not been claimed as completed or sold. Physical devices cannot connect to this loopback-only development API as configured.

## Review

Keep backend port 8001, web port 3000, and simulator mirror port 3200 running. Start commands and Xcode instructions are in README.md. Do not restart the backend while a generation is active. A failed connection shows a reconnect banner and retains saved project data. Pending generation retries reuse the original idempotency key.

## Website visual parity update

Per the user's September 9 follow-up, the native app now uses the website's charcoal canvas, terracotta/lilac ambient background, and gentle viewport-driven card illumination. Reduce Motion and Increase Contrast suppress fading. The 3D viewer exposes Studio, Rim, Sunset, Night and Flat lighting with live key/rim, environment and exposure adjustments; these update lights in place without replacing the model or camera. Soft directional shadows and procedural environment reflections preserve the imported material maps. The lighting controls UI test passed; final brightness calibration also compiled successfully.

The native Photos import → rotation/crop → one-subject confirmation UI test passed. It canceled the review afterward to preserve the user's saved draft.

## Selected-source workflow parity update

The native client now uses the same `gemini.make_concept_set` pipeline as the website: uploaded photo/camera/file or text → prompt planning → canonical front image → anchored candidate views → consistency assessment → explicit selected image → reconstruction. The original image is also a free selectable source and can bypass concept generation. Reconstruction is always a separate 55-Token confirmation with the actual source preview and engine/settings; it does not generate another concept behind the scenes.

The creation hero displays the user's draft image. The previous exact hardcoded cat prompt is migrated away, while custom text remains. The cat is only a viewer/game example. Selections persist by workspace/project, with no silent first-image fallback; a missing source must be selected again. Generated-view metadata and validation gate multiview. Invalid/mixed/unverified views cannot be combined. Four engine choices and web-compatible quality/effort values are passed to the backend.

GenerationJourneyView shows the real source, planned subject, saved concept, stage and progress with subtle activity animations. Reduce Motion disables activity motion. No fabricated percentages or simulated model fallback are used.

Verification: 13 native unit tests passed, including selected second-image persistence and omission of empty multiview IDs for single-image requests. A native UI review selected the second generated plant concept, inspected the exact source confirmation, canceled without billing, restarted the app and verified that selection persisted. Full Xcode test command succeeded. The actual plant-photo smoke run generated four 2048×2048 images and identified a citrus branch, not a cat. The view check rejected the similar candidate views; this run is restricted to single-image reconstruction. Provider consistency is assessed rather than guaranteed.

Screenshots: `native-user-reference-home.png`, `native-neutral-reference-prompt.png`, `native-plant-generation-journey.png`, `native-selected-plant-confirmation.png`, `native-plant-selection-persisted.png` in the implementation image folder.


The final backend suite contains 32 passing tests, including concurrent recovery of original references for older projects. The plant reconstruction completed as `a-2309359572`, from selected concept `mc-f9ed13abd7a241549ba1b6a7f12fc366`, with 102,590 triangles, 2K texture and an 8.75 MiB GLB. The smoke review used 60 development Tokens for four concepts and 55 for the separate Rodin model. Real provider generation was explicitly exercised; this is not a simulated preview. The final source-only build succeeded and was installed for simulator review.


Final visual acceptance: the native model viewer displayed the generated branch with its prominent yellow leaf, material response and ground shadow (`native-generated-plant-model.png`). The plant viewer UI test passed with a successful Xcode exit. The app remains installed locally; production services and physical-device release were not part of this update.
