# Native iOS visual calibration — 2026-09-10

This review follows the user's screenshot feedback at 01:03. It supersedes the initial sample review, which did not catch the cropped cat in the empty-draft home state.

## Sources and evidence

Visual targets: `../docs/design/ios-themes-20260910/lavender-home.png`, `lavender-concepts.png`, `lavender-studio.png`, `lavender-profile.png`, and corresponding emerald variants. User-supplied actual before screenshot: `/Users/jiawenzhu/Desktop/Screenshot 2026-09-10 at 1.03.46 AM.png` (the actual filename contains a narrow space before AM).

Actual after screenshots and combined comparisons: `../docs/design/ios-themes-20260910/polish/`. In particular `compare-home.jpg`, `compare-studio.jpg`, `compare-profile.jpg`, `compare-concept.jpg`, and their original PNG screenshots.

Viewport: iPhone 17 Pro, iOS 27 simulator, 402 × 874 points / 1206 × 2622 pixels at 3×. Most generated references are 853 × 1844 pixels. Contact sheets resize each source proportionally to 380 px wide without stretching and preserve native status/home regions. This is a visual-direction comparison, not a pixel-difference score. Native safe areas, real project content and the existing GLB deliberately differ from illustrative mockups.

## Findings, fixes and comparison history

- P1 fixed: the home camera cropped the cat's ears/head. Replaced the fixed camera position with a two-axis fit of normalized model and plinth bounds. It reruns when viewport size changes. A longer product-photo lens limits perspective distortion. Tests project bounds for tall, wide and deep models at four aspect ratios.
- P2 fixed: the white status overlay obscured the brand during scroll. Removed that overlay and clip scroll content at the appropriate boundary; header and safe-area actions remain tappable.
- P2 fixed: the renderer appeared inside a small boxed card with a dark, hard-shadowed platform. The home and studio stages now blend into the page, use front fill, softer shadows and a white platform with theme edging. Real model textures, UVs and mesh remain intact.
- P2 fixed: studio display modes and main actions required scrolling. Material/Solid/Wire, game entry and export now remain in the bottom action area. Fullscreen, lighting and reset remain attached to the stage.
- P2 fixed: concept images were buried beneath completed processing information. Artwork is now first, with centered selection, fixed Generate 3D action and explicit cost. Detailed warnings remain accessible below; validation and confirmation are unchanged.
- P2 fixed in screenshot iteration: selected concept outline appeared on a neighboring card while the caption named the selected card. Native scroll-position state now centers taps, repeated taps and restored selection. Latest selected-source screenshot shows border and checkmark on the centered card.
- P2 fixed: Profile preview sat too low and the avatar showed a tiny full-body thumbnail. Profile has a compact header and head-focused avatar crop. Its appearance preview uses the real native model on the chosen stage instead of a grey-backed photo block.
- Initial new UI test failed to navigate back after the lighting sheet. It now explicitly dismisses Done and tests the identified studio Back action; the final route interactions pass.

## Required fidelity surfaces

- Typography: rounded native display type, restrained small studio heading, readable system labels; concept title and selected name are visually distinct. Real names and Chinese labels remain data-driven.
- Layout: removed redundant framing and repeated headings; complete model silhouette, prominent concepts and fixed actions. Native safe areas and scrollable lower settings are retained. No imitation device chrome.
- Colors: white plus selected lavender/emerald tokens throughout. No new hot-pink accents. Semantic warnings retain their meaning. Selection includes checkmarks and selected accessibility traits.
- Assets: the same actual cat GLB is used in home, studio and Profile preview; the plant concept test retains its actual input. No static mockup replaces an interactive model. Reference-image fur and tail detail are not present to the same degree in this GLB; this remains an asset-production gap rather than a UI fix.
- Copy: narrative headlines and explicit Idea → Concept → 3D flow retained. Source, sample, local storage, cost, and confirmation wording remain truthful. The game opens only through an explicit action.

Full-view comparisons were opened together. Focused review used original screenshots for head/foot margins, platform lighting, selected-card border/checkmark, avatar crop, fixed controls and header safe areas; those original regions are readable, so separate enlarged crops were not needed.

## Verification and limits

- Camera fitting unit test passed in `/tmp/craft-polish-review-v2.log`; the final lens calibration is also tested in `/tmp/craft-polish-final.log`.
- Concept selection, source confirmation (cancelled without submitting), and relaunch restoration passed in `/tmp/craft-polish-review-v3.xcresult` (26.222 seconds).
- Real cat preview, Material/Solid switching, fullscreen open/close, lighting sheet, Back and lavender/emerald switching passed in the visual UI test. Final run evidence: `/tmp/craft-polish-final.xcresult`.
- UI snapshots cover both themes, the real model and the existing concept project. No new provider generation or payment was submitted.
- Reduced Motion is honored by entrance/selection transitions in code; exhaustive runtime accessibility, physical-device GPU performance and the full product flow are outside this requested sample review.

Residual polish: a generated mockup can depict richer fur, tailored poses, cinematic gradients and detail unavailable in the current real model. This build improves native presentation and interactions; it does not claim to reproduce that synthetic character at the same rendering fidelity. A new higher-quality model/material pass is separate work.

final result: passed

---

# Motion and visual pass — 2026-09-10 (afternoon)

The earlier review on this page optimised for restraint. The user rejected that result as
"not as fashionable as in the image" and asked for a way more fashionable, more engaging app with
animations that are both easy to use and enjoyable. This pass reverses the restraint deliberately.

## What changed

A shared motion layer, `CraftStudio/Sources/CraftMotion.swift`, is now the app's vocabulary: animation
tokens, staggered entrances, depth and surface levels, press/lift button styles, the primary CTA with a
specular sweep, a shimmer, an animated segmented control, circular stage tools, a hero stage with podium
and halo, an empty state, decorative drift shapes, a sparkle burst and a semantic haptics map. Screens
compose those instead of hand-rolling animations. `StudioAtmosphere` gained gradient depth and a scroll
plane; `CraftSteps` became the mockup's badge-and-connector rail; `CraftAppearance` rebuilt the theme rows.

Every screen file was rewritten against one canonical direction ("Lit Studio"): light is the decoration,
mass moves deliberately, one bouncy token reserved for confirmations, an ambient layer under a fast
interaction layer. `GenerationJourneyView` also dropped a `TimelineView(.animation)` that was redrawing
the whole card at 30 fps.

## Accessibility and honesty

`CraftMotion.gated(_:_:)` is the single Reduce Motion decision point. Continuous loops are additionally
gated by Increase Contrast and by the `craftAmbientMotion` environment value; the sweep and shimmer
overlays are structurally not inserted when the gate is closed, and the SceneKit idle sway is guarded by
`!reduceMotion` and stops on touch. Under Reduce Motion selection is carried by colour, ring and
checkmark rather than movement.

The generation meter is an ease-out curve, never a spring, so it cannot render a percentage the service
did not report; it is labelled "Reported progress" and still shows the real `job.message` and `job.error`.
Costs, consent wording and the local-test-purchase disclosures are unchanged.

## Defects found by looking at the running app, and fixed

- `CraftSparkleBurst` initialised to its *un-fired* state, parking ten opaque particles on top of the
  "Create a concept" label until the first tap. Rest state is now the spent state.
- The selected appearance row used `.hierarchical` on `checkmark.circle.fill`, which tinted the disc to a
  pale wash and left the tick dark — it read as disabled. Now `.palette`: solid ink disc, white tick.
- The Material/Solid/Wire control sat in scroll content and was covered by the bottom action card, so it
  was invisible at rest and unreachable by the two suites that tap it without scrolling. It is now pinned
  above the card, on the gradient, as the mockup stages it.
- Pinning it shrank the scroll viewport and cropped the podium, so the studio stage was resized to fit.

## Verification

Built for the iPhone 17 Pro / iOS 27 simulator. `CraftStudioTests` 14/14 pass, including
`CameraFramingTests`. `AppearanceTests`, `ReviewFlowTests/testFreeReviewAndNativeGameEntry` and
`VisualPolishTests` pass; evidence in `/tmp/craft-uitest*.log` and `/tmp/polish-*.png`,
`/tmp/appearance-*.png`.

`ReviewFlowTests` asserted on a button labelled "Play with this character", which this app has never had
— the control is "Try in a game" / "带上这个角色" with identifier `asset.play`. That assertion could never
have passed, and never in the Chinese interface. It now targets `asset.play`.

`VisualPolishTests` fails if a draft reference image is left saved by an earlier photo-import test, because
`creation.sampleDetails` only exists in the empty-draft state. Clear the app container before running it
alone. That is test-ordering state, not an app defect.

## Limits

Not verified: physical-device GPU performance and thermals with the ambient layer running over SceneKit,
VoiceOver rotor traversal of the rebuilt controls, Low Power Mode behaviour of the `craftAmbientMotion`
gate, and the generation journey under a real long-running job — it was read for truthfulness, not
observed end to end. Tab switches re-run the staggered entrance because the tab content is identity-keyed;
`CraftMotion.staggerStep` is the single knob if that cadence wants tuning.

final result: passed
