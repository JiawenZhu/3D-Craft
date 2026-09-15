# Conversation creation — 2026-09-12

Implemented in the native SwiftUI app. Existing emerald and lavender profile tokens are unchanged.

- Sending a gallery idea saves a project and starts a conversation rather than a paid image request. The selected Gemini/ChatGPT planner asks focused follow-ups, offers suggested replies, and maintains a structured brief.
- Messages, replies, failures and briefs persist in owner-scoped SQLite; cached projects include chat history. Client message IDs reconcile uncertain submissions without duplicating the assistant call. Studio restarts expose interrupted turns as retryable failures.
- Concepts and native interactive 3D results appear in the same chat timeline. The existing image count confirmation, image/planning model pickers, selected-source refinement, original-image inspection, 3D settings, validated multiview, progress animations, pricing and studio tools remain available.
- A newly uploaded reference belongs to this conversation. Both planning and new concept generation use the selected reference, and owner/project membership is validated.
- Public gallery and library previews use a shared disk cache, coalesced downloads and bounded decoded memory cache. View cancellation does not cancel cache population. Originals remain untouched for generation/export. Foreground cutouts also persist fallback results and share in-flight work.
- Native 3D interaction is opt-in with Explore 3D, preserving normal chat scrolling.

Verification:

- 61 backend tests passed (`tests.test_mobile_chat` + `tests.test_mobile`), including conversation isolation/persistence/idempotency, failed-turn handling, reference uploads, brief/reference/style forwarding, Gemini schema compatibility, and existing image/3D credit reservation/settlement behavior. Providers are mocked in these tests.
- Two cache unit tests passed: concurrent download coalescing + disk reuse by a fresh cache with no network; invalid data is not persisted.
- Two native conversation UI tests passed: gallery -> first reply -> follow-up, plus inline concept selection, real sample GLB/zoom, image count/price adjustment, cancel, and history after relaunch. Fixtures are served by `ios/scripts/chat-review-server.py` on isolated localhost:8003 with paid generation disabled. Screenshots in this folder are fixture-based UI evidence using existing public artwork/models, not newly generated conversation assets.
- A live Gemini conversation request through the actual API completed in approximately five seconds with a context-specific follow-up. No new paid image or 3D generation was required for this change.
- Simulator build and signed generic iPhone build succeeded. Export signature verified. The phone was disconnected during handoff, so this update was not installed or visually verified on the physical phone.

Development export: `ios/.build-device/exports/3DCraft-Chat-2026-09-12.ipa`. It uses the existing private LAN review gateway and needs the Mac studio running on the same Wi-Fi. It is not a TestFlight or App Store release.

The initial UI test attempts hit controls partially covered by the fixed composer. The final tests explicitly scroll controls into the usable viewport and pass. The chat scroll view is clipped to its viewport, with a solid theme-colored composer background.


## Direct reference generation — 2026-09-12

Uploaded images now open the quantity/cost confirmation directly, both from Create and inside a saved conversation. Original image plus user text goes straight to the chosen image renderer. Each candidate uses the original reference, retains the camera/identity unless explicitly changed, and avoids the default style and turnaround rewrite. Text-only input continues the agent-led conversation without a fixed round count. The pending attachment/text survives cancellation; source instructions and generated results persist in the conversation.

Validation: 63 mocked backend tests passed (including image-only requests, reference forwarding, selected count, charges, retries and owner checks). Two native UI tests passed on a separate disposable iPhone simulator: direct attachment confirmation/cancellation with and without text, and text-only multi-turn flow. Simulator and signed device builds succeeded. Updated app installed and launched on the paired iPhone; development IPA exported to `ios/.build-device/exports/3DCraft-Direct-Reference-2026-09-12.ipa`. No paid provider call was made in this verification; actual image resemblance still needs a real generation review.
