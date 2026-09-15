# Image + prompt for 3D generation

The iOS confirmation sheet includes an optional editable 3D prompt for Rodin.
It starts empty, with a button to reuse the original project description. The
selected image or checked view set remains the image input. The app does not
replace or regenerate it when adding text. A cleared prompt stays cleared.

Rodin receives image URLs and prompt together. The prompt is limited to 800
Unicode scalars, leaving room within the existing 1,024-character provider
budget for a short reference instruction. No additional image generation,
extra Token charge, or model change happens automatically.

The currently integrated TRELLIS.2, Hunyuan textured/white, and Hybrid image
paths do not accept text guidance. The sheet offers an explicit switch to
Rodin. When a user switches away after entering text, the draft is preserved;
they must choose Rodin or clear it before continuing. The API rejects unsupported
nonempty modelPrompt before reserving Tokens. Alternatively, the user can edit
the concept in the existing image workflow and then reconstruct that image.

The new optional modelPrompt field is part of request idempotency. Omitted
values keep older request signatures and their original bounded-project-prompt
behavior. Explicit text is delivered to the provider and stored in job settings;
image-only engines record promptApplied=false.

For a swing, the prompt may specify its frame, canopy, seat proportions and
space for a seated character. Swinging physics and controls belong to game
implementation. Text guidance is not a guarantee of photographic facial likeness,
rigging, animation, collision geometry, or an interactable game environment.

API schemas inspected September 14, 2026:
- https://fal.ai/models/fal-ai/hyper3d/rodin/api
- https://fal.ai/models/fal-ai/trellis-2/api
- https://fal.ai/models/fal-ai/hunyuan3d/v2/api

Validation uses offline provider mocks for exact prompt/image forwarding,
unsupported prompt rejection without reservation, blank prompt behavior,
length validation, and idempotency; it does not claim a measured improvement
in likeness or compare paid generated results.

Local verification: 46 backend/provider-contract tests and nine native source
selection tests passed. The UI test entered a prompt, switched to an image-only
model, and confirmed the draft survived switching back to Rodin. The updated
signed phone build was installed and launched (installation sequence 5240).

The UI test reported its assertions passed, but Xcode stalled while finalizing
the result bundle and was stopped afterward. No exported screenshot was reviewed.
Backend and native unit-test processes completed successfully.
