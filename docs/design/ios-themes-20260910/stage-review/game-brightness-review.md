# Bright game scene review — 2026-09-10

Changed the shared Godot rig to neutral daylight with ambient and opposing directional fill. Removed Lanternfall town's later night-light override. All five scenes now expand to their actual viewport aspect, including The Last Signal in portrait. Native game chrome and in-game HUD surfaces use light backgrounds; gameplay and custom asset adapters remain unchanged. The five actual game cover captures were refreshed in both the web and iOS resources.

## Sample evidence

- `game-survivor-dog-portrait.png`: actual user GLB `a-77f731a340` imported by the production runtime. The back of the dog remains yellow and readable.
- `game-ruins-dog-portrait.png`: same real GLB in The Last Signal; portrait viewport fills without the earlier 16:9 black bars.
- These two are Godot renderer captures at 402 × 760, not iOS screenshots or illustrated mockups.

## Verification

- `npm run game:covers`: passed, including all five packed game startup smoke checks and final Web export.
- `npm run build`: passed (existing large JS chunk advisory remains).
- `node scripts/test_native_game_launch.mjs`: passed.
- `survivor_controls_test.gd`: passed arrows, WASD, movement after upgrade/pause, and escape from south boundary.
- Both sample actual GLB imports and renders passed.
- Ego Chromium custom-game sample could not complete: the engine timed out downloading a GLB, while direct same-page fetch of that URL succeeded, and browser screenshot capture also timed out. Native WKWebView remains a separate acceptance check; no browser success claimed.

Local changes only. No assets were regenerated and no deployment occurred.
