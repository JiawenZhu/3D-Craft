# Inbox — hand-off from the image/animation side

Drop reference images here (`.png` `.jpg` `.webp`) and they appear in the studio's
input card under **Sample images**, ready to send to any engine.

This is the seam between the two halves of the project:

| | produces | consumes |
|---|---|---|
| image / animation side | concept art, turnarounds, hero renders → `server/inbox/` | — |
| this studio | 3D meshes → `server/storage/` | `server/inbox/` |

Multi-view works too: name files `<subject>_front.png`, `<subject>_back.png`,
`<subject>_left.png`, `<subject>_right.png` and the direction is picked up
automatically, which measurably improves the back side on both engines.

Nothing here is committed — the folder is gitignored apart from this file.
