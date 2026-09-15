# Grounded studio, personal profiles and bright games

Local implementation and sampled acceptance, 2026-09-10.

## Changes

- Removed the duplicate SwiftUI podium and clipped overscan. The real model and a solid SceneKit plinth share one camera, depth buffer and ground plane (y = 0). The platform receives the character's shadow. Grounded idle rotation replaces vertical bobbing; a camera dolly and model reveal retain motion. Orbit stays above the display floor.
- Added neutral rear and lower fill lights; raised default Studio ambient/environment/exposure while retaining lighting controls and original model textures. No assets were regenerated.
- Profile supports a display name, PhotosPicker image, or an existing library preview. Save persists locally; Cancel discards the draft. Home/Profile avatars and appearance preview reflect that choice. Default cat remains available. English and Chinese are supported.
- All five games use a brighter shared environment and opposing fill. Removed Lanternfall's extra night override and enabled portrait expansion across modes. Native game wrapper and in-game controls use light surfaces. See `game-brightness-review.md` for game-specific checks.

## Verification

- Native build and selected XCTest runs succeeded: camera framing, physical stage bounds/contact/depth, profile save/reload/image normalization/error handling.
- Native UI samples passed: cat front/orbit/fullscreen; existing user dog front/back; selecting a library dog avatar in Profile; Cancel; launch the same user dog into native WKWebView Lanternfall and hold Forward. The profile selection sample deliberately cancels, preserving the user's current identity. Persistence is covered separately by isolated unit tests.
- `/tmp/craft-stage-review.xcresult`, `/tmp/craft-stage-final.xcresult`, `/tmp/craft-dog-game-review.xcresult` contain the run results. The final dog/game run explicitly disabled verbose diagnostic collection to avoid an Xcode simulator diagnostic delay.
- `stage-dog-front.png`, `stage-dog-back.png`, `stage-profile-custom-avatar.png`, `stage-dog-native-game.png` are actual iPhone 17 Pro simulator captures. The dog captures include the final lighting adjustment. Cat captures document the same physical stage/interaction, just before that final light adjustment.
- Game export, all five packed startup checks, native launch parser, Lanternfall movement regression checks, and web production build passed.

## Scope

Sampled acceptance only, not a full device/performance/accessibility matrix. Photo-library selection on a physical device and account/cloud profile sync were not validated; profile identity is intentionally device-local. The Last Signal has a real Godot portrait-render sample, while native WKWebView sampling focused on Lanternfall. Ego Chromium custom-model capture timed out; this did not reproduce in the native WKWebView sample. No production deployment or provider generation occurred.

Preview: http://127.0.0.1:3200/ (existing iOS simulator mirror). Embedded games use the running local studio at http://127.0.0.1:3000/.
