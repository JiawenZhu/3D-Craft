# Play with the model in the viewer

Open an asset's 3D viewer and choose **Play in game** beside Export. Select a game, then press Play. Generation and opening the viewer never start a game automatically. Exiting returns to the same asset. English is the default; the existing Chinese language switch also covers this flow.

| Model type | Available games |
| --- | --- |
| Vehicle | Emberfront, Coastline Rush |
| Character | Lanternfall, The Last Signal |
| Flying character | Emerald Skies, Lanternfall, The Last Signal |

The suggested type uses the asset name and existing vehicle metadata. Users can change it, including for abstract models whose intended role cannot be inferred. Model facing offers quarter-turn corrections.

## Model handoff

`gameAssetRules.ts` resolves the selected asset's exact model URL: packaged `/models/` URLs use the frontend origin; generated `/files/` URLs use the configured API base. The iframe URL contains only the game options and `custom=1`. After the runtime announces that it is waiting, the parent sends the selected asset through the existing origin-checked message bridge.

The Godot loader downloads and imports the GLB at runtime. It replaces the player's visual, normalizes size and ground placement while preserving imported root transforms, and retains the selected game's physics and abilities. The world and timer remain frozen until the model is ready. Download/import errors offer retry or return; they do not silently substitute a stock character. Restart loads the same selected asset again. The studio viewport is unmounted during play to release its WebGL renderer.

## Current limits

- Self-contained GLB 2.0 with embedded geometry and textures, at most 100 MiB. Remote hosting must allow browser CORS; private URLs need a working signed download URL.
- The model keeps its geometry/materials and receives the game's movement. This does not automatically rig an arbitrary character or retarget walk/wing animations. Generic bob, turn, bank and existing gameplay effects are used; cat-specific mesh deformation is disabled for custom models.
- The game uses its existing collision body and ability sockets. Unusual body proportions may require future collision/attachment authoring.

## Local verification (2026-09-09)

- `node scripts/test_game_assets.mjs`: type suggestions, compatible game lists, exact URL resolution, invalid URLs/size/orientation and optional thumbnails.
- `Godot --headless --path games/forma-playground --script tests/custom_asset_test.gd` with the frontend on port 3000: 43 checks covering real HTTP GLB imports, movement in all five games, flying assets in both walking games, frozen loading, failure/retry, and retained arena/dragon abilities.
- `python3 scripts/build_games.py`: web export and packed default-mode smoke checks for all five games.
- Browser: stock robot visibly replaced the cat in Lanternfall; generated Vintage Surf Camper loaded as the player in Coastline Rush; exit returned to its viewer; Chinese controls rendered correctly.
- `npm run build`: TypeScript and Vite production build. This is local validation, not a deployment.

Re-export the Godot package before building the frontend whenever runtime scripts change.

## Native iOS local preview

The iOS `GameChooserView` is a native SwiftUI selection screen. Users explicitly select a compatible game and facing correction before entering. Only the game itself runs in WKWebView; the central 3D asset viewer remains native SceneKit.

`/ios-game` accepts a versioned base64 JSON fragment containing the selected asset identity, exact local model URL, model type, quarter-turn orientation, game, and language. The fragment is not sent to the HTTP server as a query. `nativeGameLaunch.ts` validates the request before mounting the existing `GamePlayer`; that player retains its origin-checked iframe bridge, waiting state, model import errors, and touch controls. Nothing auto-launches during generation.

This review bridge only accepts loopback HTTP(S) pages and assets under `/models/` or `/files/`, using the page port or local API ports 8000/8001. Arbitrary remote URLs, credentials, signed query strings, unsupported game/type pairs, and non-quarter-turn angles are rejected. Production authenticated game handoff remains a separate integration. Native browser navigation is restricted to the review origin and game paths; the main-frame-only `craftGame` message returns to the native model chooser. Failed navigation or a terminated web process shows a retry screen.

Checks: `node scripts/test_native_game_launch.mjs` covers exact selected identity/URL, Unicode names, API assets, all supported type/game combinations, and rejection cases. `GameViews.swift` typechecks for iOS 17 against the iOS Simulator 27 SDK. Integrated simulator gameplay must still be verified with the local web/API servers running.
