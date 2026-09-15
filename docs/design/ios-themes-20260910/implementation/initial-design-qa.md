# Native iOS appearance — sample review, 2026-09-10

Scope: implement the approved light lavender/emerald direction in the existing native app. This is a sample review requested by the user, not full release acceptance or a pixel-identical static mock reproduction.

## Visual evidence

Sources: `../docs/design/ios-themes-20260910/lavender-profile.png` and `emerald-studio.png`, each 853 × 1844 px. Other approved flow targets remain beside them.

Actual captures: `../docs/design/ios-themes-20260910/implementation/`, including `appearance-lavender-profile.png`, `appearance-emerald-create.png`, `appearance-emerald-studio.png`, `plant-concept-selection.png` and `craft-final-launch.png`.

Device: iPhone 17 Pro, iOS 27 simulator; 402 × 874 points at 3×, screenshots 1206 × 2622 px. Native UIKit/SwiftUI has no CSS viewport. Comparison sheets proportionally normalize both images to 380 px wide, without stretching, and retain status/home regions. They are composition comparisons, not a pixel-difference metric.

Full-view evidence: `implementation/compare-lavender-profile.png` and `implementation/compare-emerald-studio.png`, relative to the source directory. Both sheets were opened together with full-resolution actual screens. Focused inspection covered theme selection labels/checkmarks, the studio step labels and floating controls, and the home primary button. Those regions were readable in the originals, so no separate region crops were necessary.

State: Profile with lavender and emerald selected; Create with the user's saved plant reference; a completed real plant GLB in the studio; a saved plant concept set and its selected-source confirmation. Test data warnings are retained rather than hidden to imitate the cat mockups.

## Findings and fixes

- Fixed: step text "Concept" wrapped in the studio. The label now preserves its intrinsic width; `appearance-emerald-studio.png` shows one line.
- Fixed: bundled portrait did not resolve through an asset-catalog name. Explicit JPEG loading now displays the real sample cat in Profile and its preview.
- Fixed: scrolling content could sit behind status-bar text. A noninteractive top safe-area surface now protects status text; the latest `plant-concept-selection.png` and `craft-final-launch.png` show the corrected boundary.
- Fixed: the main Create button fell below the initial viewport. The input preview is shorter; `craft-final-launch.png` shows Camera/Photos/Files and the primary button together.
- Fixed during interaction review: tab identifiers were attached to labels, and the language test tapped an offscreen control. Identifiers now address buttons; the test scrolls controls into the visible area. Actual Chinese theme labels were verified.
- P3 follow-up: the existing sample portrait has a grey photographic background, unlike the isolated cat artwork in the design. It is a genuine bundled model thumbnail, not a replacement drawing; a dedicated transparent thumbnail would improve polish.

No actionable P0/P1/P2 findings remain within this sampled theme/flow scope.

## Required fidelity surfaces

| Surface | Review |
| --- | --- |
| Typography | Native rounded system display text and SF text preserve hierarchy. Long real asset names wrap intentionally; studio step labels no longer split. Chinese labels were checked. |
| Spacing/layout | Light, open composition; rounded controls; photo/concept/model remains central. Native safe areas and accessible system control sizing make Profile longer than the static reference; its lower sections intentionally scroll. Main actions remain reachable. |
| Colors/tokens | Lavender fill #D8A1F1 with #302238 button text; emerald #9CDCC3 with #123428 text. White base with low-opacity theme washes. Selection also uses a checkmark and accessibility state, not only color. Semantic error/success colors stay meaningful. |
| Images/assets | Existing real photo, selected concepts and GLB are preserved. Theme changes do not recolor model textures. SF Symbols supply functional icons; no drawn substitute for character art. Sample cat thumbnail quality is the P3 note above. |
| Copy/content | Existing Idea → Concept → 3D sequence, explicit game entry and source/cost confirmation retained. Local-profile and on-device storage copy does not imply account sync. English and Chinese theme/navigation labels verified. |

## Focused verification

- Latest native build/test command completed with `TEST SUCCEEDED`: `/tmp/craft-concept-review-20260910.xcresult` and `/tmp/craft-concept-review.log`.
- `AppearanceTests.testThemeSwitchPersistsAndLocalizes`: passed, 0 failures, 36.916 seconds. Lavender/emerald selection, relaunch persistence, Chinese labels, real-model fullscreen open/close and game chooser entry. Evidence: `/tmp/craft-theme-review-v3-20260910.xcresult`, `/tmp/craft-ui-tests-v3.log`.
- `SourceFlowReviewTests.testSelectedPlantConceptConfirmation`: passed, 0 failures, 25.339 seconds. Horizontal concept selection, exact selected-source confirmation and restored selection after relaunch. Generation confirmation was cancelled, not submitted.
- Final app installed and launched successfully as `studio.craft.ios`; `craft-final-launch.png` verifies actual rendered content after launch. Existing simulator mirror at port 3200 was reused and opened in the in-app browser.
- Latest build output has no Swift source compile warnings/errors; only the toolchain's skipped AppIntents metadata notice.

## Remaining acceptance

User will perform the full review. Not covered here: every screen and language string, physical camera, new provider generation, purchases, gameplay after launch, all device sizes/Dynamic Type sizes, exhaustive VoiceOver and reduced-motion runtime testing. No App Store release or website deployment occurred.

Implementation checklist: theme persistence done; core visual surfaces done; sampled interaction checks done; screenshots saved; full user/device acceptance pending.

final result: passed
