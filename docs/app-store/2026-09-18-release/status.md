# Version 1.1 preparation

Owner approved six Seedance mascot waiting animations and two dragon screenshot replacements on September 18, 2026.

- Approved implementation committed and pushed to `codex/app-store-cloud`: `f7f879e`.
- App Store Connect draft version 1.1 created: `d3d77d6e-e37a-4f0f-b02c-37d5540c4ad5`.
- English localization: `3b7b7b58-373c-4263-a663-ea0843039bcd`.
- Replaced only iPhone 6.9-inch `05-game-brief.png` and `03-lighting.png`. Both delivery states COMPLETE with no errors. Original first five screenshots and their order preserved. iPad's existing five screenshots unchanged.
- New screenshot IDs: `b843b384-133f-4c9c-9d53-f1cd30272f1d` (game brief), `2938dcce-2ce2-4609-9379-9dd29d83e34f` (lighting).
- Existing version 1.0 remains live. Version 1.1 is PREPARE_FOR_SUBMISSION, not submitted or released.
- Account-owned API credentials are being implemented and reviewed separately; no live API-key feature or mobile build is claimed yet.

## Version 2.0 (September 18, 2026)

Owner asked to ship this release as **2.0** with API access in "What's New".

- `ios/project.yml` and the Xcode project now say `MARKETING_VERSION` 2.0.
- App Store text: `whats-new-2.0.md` (adds API Access and Live Library Sync to the four approved bullets).
- API-key surface is live on Cloud Run `craft-api-00025-sdf`: one-step prompt-to-3D (`POST /api/v1/creations`),
  project read/rename, concept-image download, newest-first assets, permanent deletes behind the explicit
  `assets:delete` scope. Verified live end to end with the owner's test account (63 Tokens per creation).
- App: refreshes every 20 s while open and on foreground; drops jobs deleted on the server. Key screens (iOS + web)
  have an "Allow permanent deletes" toggle, off by default.
- Still to do in App Store Connect: rename draft version 1.1 → 2.0, paste the What's New text, attach the new build.
- Before public release: remove the owner's UID from `CRAFT_API_SANDBOX_UIDS` on `craft-api`.
