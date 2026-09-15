# Native image model and thumbnail review

Local native iOS implementation, September 10–11, 2026. This is simulator acceptance, not an App Store/device release.

## Concept workflow

- Create and Concept Studio expose the exact Gemini 3 Pro Image and GPT Image 2.5 Sunburst renderer IDs; choice is persisted and sent with concepts/refinements.
- Current local catalog has Gemini configured. OpenAI requires server-side `OPENAI_API_KEY`; no paid OpenAI call was made. Readiness reflects key configuration, not provider entitlement.
- The first arriving concept is brought into the visible carousel without implicitly selecting it for 3D. Later angles do not move the carousel away from an image being inspected.
- Confirming a 3D request animates only the actual selected source. Existing generation journey remains below the artwork. Completion exposes the actual model preview in the same project.
- Legacy pending submissions retain their exact request body; changing provider cannot replay an uncertain request as a different paid operation.

## Verification

- Backend: 38 image workflow tests plus 5 display-thumbnail tests for model routing, payloads, anchoring, provenance, idempotency and credits passed.
- Native integrated build: 12 tests passed, with 1 explicit simulator-only Vision skip. Covers image model selection/provenance, source-specific 3D activity, transparent thumbnail routing, and profile PNG persistence.
- Native UI: exact provider choices and unavailable OpenAI state exercised without submitting generation. Screenshots: `gemini-selection.png`, `openai-selection.png`.
- Live paid generation and full physical-device testing remain unverified.

## Thumbnail backgrounds

The user-reported dog PNGs have opaque black baked into the images. Semantic foreground extraction creates transparent display derivatives; it does not use black-color keying or alter reconstruction sources. The selected light lavender/emerald theme sits behind the subject. Asset-backed profile pictures preserve PNG alpha.

The iOS Simulator cannot create the Apple Vision inference context (Vision code 9). The local macOS server supplies cached transparent display derivatives, while compatible devices can perform on-device extraction. Other server platforms fall back to the unchanged image when no segmentation service is available. The raw Vision simulator test is explicitly skipped for that specific error; transparency/source-preservation tests still run.

Final native dog review passed in both themes. Full visible thumbnails have no black backdrop; eyes, nose, paws and tail remain intact. Real simulator screenshots: `thumbnail-emerald.png`, `thumbnail-lavender.png`. The updated app was installed and relaunched for review.
