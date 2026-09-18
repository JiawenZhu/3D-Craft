# Mascot waiting animations — local review

Prepared 18 September 2026. **Pending owner review. Not committed, shipped or uploaded.**

Open [`index.html`](index.html) in a browser to review. It plays the same MP4/JPG
files that the iOS app bundles, from `ios/CraftStudio/Resources/Mascot/`.

## What these are

Six muted loops: two mascots × three waiting phases. They are used **only** as
waiting indicators.

| Theme | Mascot (original art) | Thinking (small) | Concept image (large) | 3D (large) |
|---|---|---|---|---|
| Soft lavender | Cloud Dragon, `docs/app-store/2d-app-store-selection/original-2d-art/cloud-dragon.png` | blinks, tilts head, a small orb floats | a claw sweeps glowing strokes into a ring | shapes a turning glass cube that dissolves into sparkles |
| Emerald green | Panda Chef, `…/original-2d-art/panda-chef.png` | blinks, tilts head, a small orb floats | the spoon draws glowing loops like a wand | kneads a glowing cube between its paws |

## Model actually used

**fal Seedance 2.5 image-to-video**, endpoint `bytedance/seedance-2.5/image-to-video`.
The endpoint and its parameters were checked against
https://fal.ai/models/bytedance/seedance-2.5/image-to-video/api before any call.
No procedural fallback was needed.

- One submission per clip, no retries. The first clip was validated first, then the other five were submitted.
- Settings: 480p, `duration: "4"`, `generate_audio: false`. The same original art (downscaled to 960 px JPEG in `source/`) was passed as `image_url` and `end_image_url`.
- Request IDs, seeds, prompts and output sizes are in `seedance-log.json`. The key is read from `.env` and is never written or printed.
- Estimated cost from fal's published rate (about $0.22 per second at 480p): 6 × 4 s ≈ **$5.30**. The actual charge was not read from the fal account.

## Encoding and app assets

`scripts/mascot/encode_mascot_loops.sh` converts `raw/` (640×640 H.264, 4.04 s) into:

- `mascot-<dragon|panda>-<thinking|concept|model>.mp4`: 480×480, used at 164 pt.
- `mascot-<dragon|panda>-thinking-small.mp4`: 144×144 head-and-shoulders crop, used at 28–36 pt.
- `mascot-<dragon|panda>-poster[-small].jpg`: the first frame, which is the unchanged original art. Shown under Reduce Motion, while paused, and before the first video frame decodes.

The files are H.264 High, CRF 26–27, 24 fps, 97 frames, and have **no audio track**.
Together the 12 files are about **719 KB**.

Seedance ends close to its start frame but not exactly on it (first vs last frame about 34–35 dB PSNR).
The encoder blends the last 0.25 s toward frame 0, so each loop flows back into its own start.
Measured on the lossless intermediate for `panda-thinking`, last→first improves to 41.5 dB. In the
encoded files, H.264 keyframe noise limits that measurement to about 35 dB.

## App integration

`ios/CraftStudio/Sources/CraftMascotLoop.swift` defines `CraftMascotLoop(phase:size:active:)`.
The mascot comes from the appearance setting: lavender → dragon, emerald → panda.

| Surface | Before | Now |
|---|---|---|
| Chat reply pending (`CraftConversationView`) | `ProgressView()` | thinking, 36 pt; send button thinking, 28 pt |
| "Improving prompt…" (`ModelGenerationSheet`) | `ProgressView()` | thinking, 28 pt |
| Creation journey activity (`GenerationJourneyView`) | spinning arc + orbiting dots around the source image | 164 pt mascot: **thinking** while the job is `queued`, then **concept** for concept jobs or **model** for 3D jobs while running |

Honesty and lifecycle:
- The mascot appears only while the real job/turn is active. The journey card's reported
  percentage, stage nodes and messages are unchanged. The loop implies no progress.
- Playback requires `active` plus the app's existing gates: Reduce Motion off,
  Increase Contrast off, and `craftAmbientMotion`, which is false when the scene is
  backgrounded or in Low Power Mode. Otherwise the video view is removed and its player is torn down, revealing the still art.
- `AVQueuePlayer` + `AVPlayerLooper` loop the clip gaplessly. The player is muted, doesn't keep
  the display awake, pauses in the background, and is torn down in `dismantleUIView`.
- Decorative only: the indicator is `accessibilityHidden`, and the adjacent text carries the meaning.

Not changed: gallery assets, paywalls, game content, promotional mascots, the concept-card
reconstruction overlay, and other non-generation spinners.

## Verification

- `xcodebuild build` for the iPhone 17 Pro Max simulator (Xcode 27.0) succeeded.
- `xcodebuild test -only-testing:CraftStudioTests`: 69 tests, 0 failures, 1 pre-existing skip.
  This includes the new `MascotLoopTests`, which check the theme→mascot mapping and that every clip is
  bundled, silent, about 4 s long and under 400 KB, with both posters present.
- The HTML gallery was rendered in headless Chrome, with both themes and all sizes checked visually.

## Known limitations

- The live chat, queued and running states were not exercised in the running app, because that would
  start paid generation or chat jobs. The integration is verified by compilation, unit tests and the
  gallery, which uses the same assets and framing.
- In the lavender theme, the circular portrait slightly clips the dragon's wing tips at 164 pt.
- Seedance motion is generative, so small details (spines, hands) shimmer slightly between frames.
- Behaviour with other apps' audio playing was not tested on a device. The clips have no audio
  track and the player is muted.

### Final review

The remaining chat send-button thinking spinner now uses the 28 pt mascot; upload-only
progress remains a standard indicator. When motion is gated off, the native video view
is removed and its player is torn down, ensuring the poster shows instead of a paused
video frame. After these changes the simulator rebuilt and both MascotLoopTests passed
(2 tests, 0 failures). Browser playback loaded every clip without media errors, had no
horizontal overflow, and the Reduce Motion preview stopped all videos. All six motion
contact sheets and both replacement iPhone captures were visually reviewed. No device
installation or paid live generation flow was performed during this review.
