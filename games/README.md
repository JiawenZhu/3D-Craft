# Forma Game

Four Godot 3D scenes live under the existing **Game** tab beside Asset and Explore. The current Forma interface is preserved. The embedded player shares keyboard and touch controls with the native Godot simulation.

| Scene | Play loop | Explore models |
| --- | --- | --- |
| Emberfront | Choose a vehicle, defeat four AI opponents, shoot barrels and chain explosions | Yellow car, camper van, robot pilot, dragon, towers, cottages; optional Boba vehicle |
| Coastline Rush | Three-second start, three AI rivals, eight ordered checkpoints, ramps and explosive obstacles | Yellow car, camper van, cottages, tower; optional Boba vehicle |
| The Last Signal | Push a physical crate onto a seal, cross the opening gate, recover three signals, return to the exit | Robot or Boba player, dragon, towers, cottage |
| Emerald Skies | Run, take off, hover, fly through eight rings, burn six hostile crystals, land at the nest | Animated Baby Emerald Dragon and castle towers |

## Build and run

Requires Godot **4.7.2** and its matching Web export templates. Set `GODOT_BIN` when the executable is outside PATH or the standard macOS application locations.

```sh
npm run game:build   # prepare existing assets, import, export Web
npm run game:test    # native physics and complete gameplay tests
npm run game:covers  # render actual scene screenshots, then export Web
npm run build       # build website, including the existing Web export
npm run dev
```

Open `http://localhost:3000/` and select **Game**. Re-run `game:build` after changing Godot sources: Vite does not compile GDScript. `game:covers` requires a graphical renderer; `game:test` runs headlessly and deliberately skips audio playback. No command above deploys or uploads the site.

Generated exports in `public/games/forma/` and Godot's `.godot/` import cache are ignored. Prepare the Web export before a release build. The initial engine and model download is approximately 84 MiB before HTTP compression. It is loaded only when a game is started. The export uses single-threaded WebGL 2; it does not require cross-origin isolation headers.

## Inputs

- WASD: drive; in ruins, move relative to the isometric camera.
- Space: fire in Emberfront, brake in Coastline Rush, jump in The Last Signal. In Emerald Skies, hold Space to take off/rise, release to hover, hold C to descend/land, and hold F to breathe fire. Shift dashes. The same actions have touch buttons.
- Shift: accelerate/run. Q: drop an existing generated magma cube with gravity.
- E: drop an explosive barrel, or interact with a nearby signal in ruins.
- R: recover upright at the spawn/last checkpoint, with a small armour cost.
- P / Escape: pause. Touch controls expose the same actions. Restart creates a fresh game instance.

## Architecture and provenance

`forma-playground/scripts/vehicle.gd` uses a rigid body, four suspension rays, forces for acceleration and lateral grip, torque for steering, and collision damage. The walking character is a capsule rigid body. Props and projectiles use real collision shapes; explosions apply distance-based impulse and damage. Visual GLBs use simple separate collision proxies to keep browser physics inexpensive.

`scripts/prepare_game_assets.py` copies eight existing Explore GLBs unchanged from `public/models`. `forma-playground/assets/manifest.json` records their original paths and SHA-256 hashes. No new generation service is called by a game. The four WAV sound effects are synthesized, with no external recording samples. Gameplay covers are captured from Godot's real viewport, not illustrations of unavailable gameplay.

The React host loads the Web export into a same-origin iframe. Both ends validate message origin and sender. The host sends control actions and receives public gameplay telemetry. It cannot load arbitrary workspace files or external models. Cloud asset import remains a separate product integration.

## Verification

`physics_test.gd` checks falling bodies, suspension driving, frozen motion on pause, actual projectile and vehicle-triggered barrel explosions, generated prop spawning, and the complete ruins push/collect/exit path. This component suite disables AI input to isolate collisions.

`competition_test.gd` drives the production controls through a complete arena victory and an eight-checkpoint race **with all enemies and rivals active**. It does not teleport the player, increase health, disable opponents or set a victory flag. Export tooling fails on Godot script/import diagnostics even if Godot returns zero.

Local validation: all eleven gameplay/vehicle test cases pass, all four scenes render and pass startup checks from the actual exported PCK, and the TypeScript/Vite production build passes. The browser was used to verify English/Chinese menus, in-game language changes, pause/resume, flight movement and fire-energy input. Phone-width dialog bounds were checked and an overflow was corrected. Real iOS/Android devices, Safari, listening acceptance and external hosting remain unverified. These are local playable scenes, not a shipped multiplayer game or native mobile application.

## Emerald Skies and language support

The dragon uses the actual Explore GLB, with procedural vertex deformation for wingbeats, alternating feet, tail motion and jaw movement. This is a lightweight game animation, not a newly authored skeletal rig. A rigid-body controller handles running, ascending, hovering and landing. Mouth breath combines animated flame geometry, soft particles, embers, local light and a synthesized looping fire sound. Aim assistance is limited to a forward cone; a physics ray blocks damage through scenery. Crystals fire dodgeable projectiles. Rings restore health/fire energy, chained crystal destruction earns bonus points, and empty fire energy enforces a recovery interval.

`dragon_test.gd` uses production movement/fire inputs to run, take off, hover, traverse all eight rings, destroy all six crystals and physically land for victory. It does not teleport, grant health, disable attacks or set completion flags. It is the eleventh case in `npm run game:test`.

Game defaults to English and remembers an explicit Chinese selection in local storage. The language switch updates menus, instructions, HUD, results, map legends and world signs during play without restarting. The small Chinese sign font is a renamed, SIL OFL-licensed Noto Sans SC subset; license and provenance ship with the game source. `scripts/prepare_game_font.py` rebuilds the subset from the official font when signs change (requires fonttools).

The yellow car and robot were rebuilt and reviewed from four sides before replacing the Explore/game source files. See `docs/model-review/README.md` for selected candidates, rejected alternatives and remaining texture limitations.
