# 3D Craft — visual and motion direction

Date: 2026-09-09. Status: three static design concepts, awaiting selection. No application implementation or animation QA performed in this exploration.

## Grounding

Reference: [Customuse Skins Maker Roblox Design, Asib Iquebal](https://dribbble.com/shots/27511209-Customuse-Skins-Maker-Roblox-Design). Captured reference: customuse-reference.png. The reference is a static image; motion below is our proposed design, not observed source behavior.

Existing product context: current-web.png and ../ios-2026-09-09/implementation/native-user-reference-home.png. Character reference: public/images/explore/lantern_cat.png. All three ImageGen requests attached the actual reference, native app screenshot, and cat image.

Target: mobile-first 390 × 844 logical-pixel compositions. These are raster concept renders, not finished layouts or guaranteed model outputs. English default; retain Chinese localization. Preserve photo/text → concepts → user selection → 3D → optional game preview. Adapt the reference’s light surfaces and character emphasis using our own product identity.

## Displayed option mapping

1. 01-playful-atelier.png — creation home, generous hero character and prompt-led creation.
2. 02-living-character-stage.png — completed model studio, interactive turntable and explicit game entry.
3. 03-concept-playground.png — concept selection, tactile horizontal browsing and restrained violet actions.

The concepts explore different focal screens as well as hierarchy; they are not three completed app designs. A selected direction should be extended consistently across the full existing flow. The sample character on an empty creation home must be identified as a sample. Generated concept art is not proof of available outfits or 3D fidelity.

## Motion contract

| Trigger | Proposed motion | Timing | Behavior constraint |
| --- | --- | --- | --- |
| Screen first appears | Title and controls fade/translate 8 px, slight stagger | 220–320 ms, 30 ms stagger | Once per meaningful navigation, not every rerender |
| Press a control | Scale to 0.97, spring back; native light haptic where appropriate | 100–180 ms | Activate immediately; preserve 44 pt touch targets |
| Browse concepts | Drag follows finger, snaps with restrained spring; selection ring crossfades | 250–350 ms settle | Keyboard and accessible selection alternatives; avoid compulsory swiping |
| Choose a concept | Selected image maintains visual continuity into the generation stage | 350–450 ms | Do not imply that a real mesh already exists |
| Generation running | A subtle light sweep accompanies explicit server stages | 2.5 s ambient loop | Show actual queued/concept/reconstruction/export state. No fabricated percentages or unlimited spinner on failure |
| Model becomes ready | Stage fades up, model scales from 0.96, one soft halo pulse | 450–600 ms | Only after the actual model has loaded successfully |
| User inspects model | Touch-controlled orbit with restrained inertia | Direct manipulation | Stop automatic motion on interaction; provide reset orientation |
| Studio idle | Optional slow lighting drift | 6–8 s loop | Pause offscreen and during inspection; do not deform arbitrary unrigged meshes |
| Change render mode | Crossfade surface UI and apply actual viewer mode | 150–220 ms | Keep model and camera position stable |
| Choose Try in a game | Game chooser sheet enters, selected asset retained | 250–350 ms | Never auto-enter; list compatible worlds with clear user override where supported |
| Game ready | Short crossfade into loaded game scene | 300–450 ms | Await confirmed asset load; preserve actionable loading and retry states |

Character waving, breathing, running, or wing animation requires a compatible rig and animation clips. Use real rotation and lighting for ordinary static GLB models. ImageGen renders must never be presented as interactive 3D assets.

## Quality and implementation guardrails

- Preserve existing generation, library, export, language, and game handoff behavior; introduce visual changes within the existing project.
- Use SwiftUI transitions and RealityKit for native iOS where the current architecture supports them; use existing web motion/rendering primitives for the web app. Share design tokens and backend states, not screenshot-based layouts.
- For reduced motion, replace spatial transitions with short opacity changes and disable ambient movement. No flashes or repetitive confetti.
- Budget toward 60 fps interaction on target devices, measure rather than promise. Suspend offscreen rendering, limit simultaneous real-time previews, and use poster thumbnails in library rows.
- Use real job progress, cancellation/retry, and restoration after backgrounding. Animation must not obscure errors or duplicate generation requests.
- Keep visual selection separate from technical promises: source reference is inspiration, concepts are static, and live motion still requires implementation and testing.

## Focused acceptance after implementation

Capture creation home, selected concept, and ready 3D studio at a matching mobile viewport. Test one end-to-end concept-to-model path, explicit game selection, English/Chinese, reduced motion, background/resume, and loading failure. Inspect gesture responsiveness and frame time on a representative physical phone. Confirm the game receives the user’s actual selected asset.
