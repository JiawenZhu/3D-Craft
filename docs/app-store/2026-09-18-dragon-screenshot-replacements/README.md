# Dragon replacements for screenshots 03 and 05 — pending review

Prepared 18 September 2026. **Local only. Not uploaded; App Store Connect was not touched.**

Only two listing screenshots change: `03-lighting` (Lighting studio) and
`05-game-brief` (Create a game). The existing Cloud Dragon studio example is shown
instead of Lantern Explorer (the cat). Every other App Store image, including the
first cat promotional image, stays as approved. The originals in
`../2026-09-12/screenshots/` were not modified.

| File | Size | Replaces |
|---|---|---|
| `iphone-6.9/03-lighting.png` | 1320 × 2868 | `2026-09-12/screenshots/iphone-6.9/03-lighting.png` |
| `iphone-6.9/05-game-brief.png` | 1320 × 2868 | `2026-09-12/screenshots/iphone-6.9/05-game-brief.png` |
| `ipad-13/03-lighting.png` | 2064 × 2752 | `2026-09-12/screenshots/ipad-13/03-lighting.png` |
| `ipad-13/05-game-brief.png` | 2064 × 2752 | `2026-09-12/screenshots/ipad-13/05-game-brief.png` |

## How they were made

These are real, unedited native captures. There is no compositing or redrawn UI.
They come from `AppStoreCaptureTests.testCaptureDragonLightingAndGameBrief`. This
test runs the same flow, theme (emerald), language (English) and cloud API as the
original capture test, but it taps the public Cloud Dragon example. It writes to
`/tmp/craft-appstore-captures-dragon`, so the original capture folder is never
overwritten. The status bar was set to 9:41 with `simctl status_bar`.

- iPhone: iPhone 17 Pro Max simulator. iPad: iPad Pro 13-inch (M5) simulator. Xcode 27.0.
- No generation, purchase or sharing actions were performed.

## Differences from the 12 September originals

- `05-game-brief` shows the **current** Create-a-game sheet. The 12 September
  capture predates the multi-object redesign. The new sheet has these parts: a
  "3D objects" card with Choose objects, ChatGPT/Codex/Claude Code/Other tabs,
  "Your idea (optional)" and a short prompt preview. The page structure,
  dimensions and theme are unchanged.
- The iPad status bar shows the capture date (Fri Sep 18), as the originals showed theirs.

Upload only after the owner approves these previews.
