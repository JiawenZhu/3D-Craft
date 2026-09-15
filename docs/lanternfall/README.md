# Lanternfall / 灯影夜行

An original fifth Forma game, inspired by the user-supplied 202-second demonstration of a cat-led 3D survivor game. Existing game designs and the dark Forma shell are retained. English is the default, with Chinese available in the same language switch.

## Reference review

The video was inspected through timestamp-spaced frames across its full duration. It demonstrates auto-combat, dropped experience, upgrade drafts, treasure and interaction points, escalating crowds and large bosses in a night-time town. Its development section shows character reference poses, image-to-mesh reconstruction, character animation and effects assembled from several specific visual steps. The supplied video's characters, textures, UI and code were not copied into this game.

Reviewed September 9, 2026:

- [zedtixPro/Megabonk-Game-Template](https://github.com/zedtixPro/Megabonk-Game-Template): Unity early version, with the author explicitly describing unfinished/placeholder systems. No repository-level license was visible in its root listing. Not imported.
- [ryanmlo/survivors-game](https://github.com/ryanmlo/survivors-game): its README identifies the Kenney Godot 4.3 3D platformer starter, MIT code and CC0 included assets. It offers basic movement/camera/collectables, which this workspace already implements. Not imported.
- [mmaehira/05_poc-godot](https://github.com/mmaehira/05_poc-godot): a 2D Godot survivor project; not a match for the requested detailed 3D presentation. Not imported.

Reusing the existing Godot runtime avoids a second engine download and preserves the existing browser bridge, language support, inputs, pause/restart and model pipeline. New gameplay and town geometry are authored in this workspace. This is inspired by a game genre, not an official Megabonk port.

## New hero provenance

Original concept: Gemini through the existing `server.gemini.make_image` implementation. One clean full-body view, one face and tail, neutral studio lighting and separated limbs. Reconstruction: the existing `/api/generate` Rodin high-quality route, seed 37, PBR GLB and A-pose setting. Request and provider job records are retained in ignored `server/storage/lanternfall-20260909/`.

Concept: `public/images/explore/lantern_cat.png`.
Model: `public/models/lantern_cat.glb`, Rodin job `job-c0cf0aed9b`, asset `a-5f649cb9c6`. Four-view inspection accepted a single face, two ears, four separated limbs and one rear tail. Tail shape is straighter than the concept; this is not a pixel-identical reconstruction. 94,108 faces, 53,192 vertices, one mesh/material, 2K texture, 10.37 MB. See [four-view model review](cat-model-review.png).

Audio: four original synthesized WAVs, reproducible with `venv/bin/python scripts/prepare_lantern_audio.py`; no sampled music or downloaded effect packs.

## Verification

- Focused production gameplay test (`tests/survivor_test.gd`): all nine checks passed after combat/camera tuning. The agent used normal movement/dash and offered upgrades to ignite all three shrines and defeat the Warden at 133.7 seconds; 202 enemies defeated, level 8. No health/stat/time/position cheats. Includes upgrade freeze, invalid choice rejection and pause bypass protection.
- Source import and startup checks of all five exported PCK modes passed. TypeScript and Vite production build passed. Existing large-chunk warnings remain.
- Actual browser acceptance: start screen, live combat and English/Chinese upgrade cards inspected; choosing upgrades resumes play; on-screen movement moved the cat and dash reduced its available charge. Corrected dash-button contrast and enabled an expanding canvas for this mode in portrait windows.
- Actual game cover rendered by Godot, not an illustration. Native sample: 224 draw calls and about 1.87 million primitives including scenery. Browser frame rate varies with viewport and hardware; no real iOS/Android device certification was performed.
- This is a local playable game at `http://localhost:3000/` → Game → Lanternfall, not a production deployment. The shared five-game engine/model download is approximately 94.3 MiB before HTTP compression.

The hero uses mesh deformation for walking and tail motion rather than a full skeletal rig. Enemies and town are original procedural geometry; they are not as detailed as the generated hero. A further production art pass could introduce rigged enemies, richer animation and streamed per-game assets.

### Direction-key focus regression (September 9)

The page-level input bridge accepted arrow keys, but the cat controller inside the focused Godot iframe accepted only WASD. Upgrade selection focuses that iframe, making arrow controls appear to stop working. The controller now accepts both sets directly. `survivor_controls_test.gd` reproduced seven failing assertions before the patch and passes all nine afterward: four directions, post-upgrade, post-pause, WASD compatibility, boundary collision and moving away from the south wall. This focused test is included in `game:test`.
