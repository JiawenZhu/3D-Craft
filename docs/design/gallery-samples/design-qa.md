# Gallery design acceptance — native iOS

Reference: `../gallery-concepts/emerald-green-v1.png`, with the existing Profile palette retained.

## Implementation

- Create defaults to Characters. Characters and Objects contain only public examples; User created contains personal models. Personal dogs are retained in User created and Library.
- Library follows the gallery layout with search, All/Concepts/3D models/Favorites filters, sorting and private creation cards.
- Expand retains pinch/orbit and adds a themed floating dock for zoom out, reset and zoom in. Bounded optical zoom magnifies the live model without moving the camera through its geometry; reset restores the fitted view.
- Every gallery tile opens its generated 3D object. Original concept artwork remains accessible through the Concept step.
- A floating prompt composer retains photo, camera and file attachment paths and generation settings.
- Concept studio uses a centered selected image, explicit selection, a synchronized thumbnail strip, refinement and a compact Generate 3D model action.
- The 3D studio uses a large native interactive model, its physical display plinth, labeled reset/lighting/expand tools, material controls, Try in a game and Export.
- Profile still owns theme selection. Soft lavender and Emerald green retain their pre-existing color tokens; no green from the reference was substituted.
- Creation cost calculator and the default-hidden technical price toggle remain accessible.

## Scope of visual review

Native iPhone 17 Pro simulator, iOS 27. Screenshot sampling covers both gallery themes, the concept studio, and actual character/world/outfit models. These are live app captures, not generated mockups. Generated models have real reconstructed geometry and textures, so their fine details can differ from concept artwork.

The supplied garment and equipment examples are individual 3D assets. This work does not implement a wardrobe-equipping system or skeletal animation for them.

## Evidence

Initial native acceptance passed: four UI tests, zero failures (2026-09-11 05:44 CDT). Coverage: both gallery themes and category filters; selected concept and thumbnail layout; source-image inspection and lighting controls; Profile theme persistence across app restarts; character/world/outfit viewer framing. A separate source/order cache Codable unit test also passed. Earlier presentation-timing failures were addressed in the test by waiting for hittable controls and scrolling cards above the floating composer before tapping.

XCTest result: `ios/.build/Logs/Test/Test-CraftStudio-2026.09.11_05-42-39--0500.xcresult` (relative to repository root).

| Capture | Screen |
| --- | --- |
| [Green gallery](implementation/gallery-emerald.png) | Create, existing emerald palette |
| [Purple gallery](implementation/gallery-lavender.png) | Create, existing lavender palette |
| [Concept studio](implementation/gallery-concept-studio.png) | Existing user project; its original black source background is preserved |
| [Character](implementation/gallery-real-model.png) | New textured Lantern Explorer model |
| [Original source](implementation/gallery-original-concept.png) | Matching concept image |
| [World](implementation/gallery-world-model.png) | New textured Coconut Island model |
| [Outfit](implementation/gallery-outfit-model.png) | New textured Starlight Robe model |

The production manifest and catalog README track the individual 20 model outputs. Model geometry and texture structure are checked for every output; only the listed models received visual screenshot inspection. This is local simulator/backend verification, not a production deployment or physical-device acceptance run.

## Latest gallery separation and Expand verification

The latest build-for-testing succeeded. The public/private category unit test and backend catalog tests passed. The backend now serves exactly 20 curated public examples.

`testExpandedModelZoom` passed on 2026-09-11 at 06:06 CDT: opened Mint Racer, entered Expand, zoomed in twice, zoomed out, reset and closed Expand. The fit/detail/reset screenshots were visually inspected: the real model enlarges and returns to its fitted view. Native pinch remains enabled; this pass exercised the buttons.

The combined private-gallery/Library UI test passed its public/private gallery assertions but failed to select/verify Library's Models results reliably. A subsequent manual check in the live simulator successfully selected 3D models and displayed the user's dogs. This test run is not reported as an all-pass suite. Earlier green/purple gallery captures predate the renamed and separated tabs.

| Latest capture | Screen |
| --- | --- |
| [User created](implementation/gallery-user-created.png) | Personal models |
| [Library](implementation/gallery-library.png) | Private concepts and models |
| [Library models](implementation/gallery-library-models.png) | Manually verified Models filter |
| [Expand fit](implementation/gallery-expand-fit.png) | Fitted model and zoom dock |
| [Expand detail](implementation/gallery-expand-detail.png) | Enlarged live model |
| [Expand reset](implementation/gallery-expand-reset.png) | Restored fitted view |
