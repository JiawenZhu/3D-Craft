# Game-builder handoff

The Create a game sheet accepts multiple completed 3D objects from the public
collection and the signed-in user's assets. Choose ChatGPT, Codex, Claude Code,
or Other. The user supplies an optional idea and decides the game design with
their own agent.

The preview, copied text and GAME_BRIEF.md contain exactly the same short prompt:

> Create a game that runs in a browser using these 3D objects.
>
> - Moon Fox (01-moon-fox.glb)
> - Tree (02-tree.glb)
>
> [The user's optional idea]

There are no imposed game genres, controls, frameworks or browser names.
Chinese mode uses an equivalent short Chinese request. Each selected original
GLB is copied without conversion into a unique temporary folder, using indexed
filenames to avoid collisions. Invalid model headers fail visibly and remove the
partial package. No studio URLs or credentials appear in the brief.

Share objects & prompt opens the native activity sheet with all GLBs and the
brief. Opening an agent alone does not attach files or send a task. The user
chooses the receiving app or saves the files. Legacy built-in game code remains;
the old Play button is not rendered in the asset detail.

Four focused XCTest cases passed on September 13, 2026: multi-object byte
preservation, unique filenames, concise user-directed prompts, and invalid/empty
selection cleanup. The UI test checks multi-selection and the native share-sheet
boundary; no test sends files to an external agent.

September 13 local acceptance: the native UI test selected two objects, verified
both indexed filenames and the concise browser request, selected Claude Code,
and reached the native share sheet. The final signed Debug build was installed
and launched on the connected iPhone with the private LAN gateway verified.

The object picker and selected-object summary reuse CraftThumbnailImage, matching
the profile library's cached concept previews. Picker rows show a 56-point preview
on the left, a two-line name and collection label in the middle, and the selection
circle on the right. Missing images use the existing cube placeholder; selection
and export remain available. The summary shows 48-point previews.
