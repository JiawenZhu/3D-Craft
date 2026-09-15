# Commercial product foundation

## Product decision for this iteration

Keep the existing Forma interface: atmospheric background, floating controls and image/text → concept → 3D flow. The proposed white redesign was rejected and was not implemented. New agent setup uses the existing tools menu and modal styling. A camera shortcut uses the browser's rear-camera capture hint where supported; desktop browsers may show a file picker. This is not an iOS or Android application release.

Until launch and billing preferences are resolved, the implemented foundation is the existing web studio plus a local CLI/MCP adapter. Credits remain cosmetic in the current UI; provider requests can incur real charges. The following milestones are proposed work, not shipped capabilities.

## The customer journey

1. Capture a photo or describe an object. For a landmark, frame the complete subject and decide whether the goal is a stylized prop or an accurate reconstruction.
2. Prepare a clean concept while preserving the features the customer chose. A single image cannot verify hidden surfaces. Offer extra reference captures when fidelity matters.
3. Reconstruct and review the model from several angles, including geometry without texture. Separate issues in the input, shape and texture.
4. Export GLB or a bundled OBJ into a workspace. Record source reference, settings, engine, actual endpoint and version/provenance when available. Add game-specific scale, pivot, triangle/texture budgets, LOD and collision work before claiming game readiness.

## Architecture to extend

Web studio / mobile client / remote MCP → authenticated application API → durable job queue → provider adapters → private object storage. The desktop CLI/MCP bridge additionally handles local file upload and workspace downloads. A remote MCP server must use asset ids and scoped uploads/downloads, not access arbitrary paths on the hosting machine.

The existing Python provider adapters and pipeline stage boundaries are reusable. Current disk indices and in-memory direct jobs are development infrastructure. Browser Firebase login and asset sync exist, but the Python API does not enforce Firebase identity or ownership. Therefore they are not a complete commercial account boundary.

## Milestones and acceptance criteria

| Milestone | Concrete work | Acceptance |
| --- | --- | --- |
| Private hosted beta | Verify identity on all API and file routes; tenant ownership on assets/runs; private storage and expiring downloads; upload constraints and quotas; persistent queue and job events; scoped OAuth for remote MCP. | Two users cannot list/read/delete each other's assets. A worker restart resumes a job without double charging. Account revocation removes access. |
| Usage and billing | Choose managed credits, BYOK or both. Managed: reserve credits before submission, reconcile provider completion, release failed-job reservations and verify billing webhooks. BYOK: keep encrypted provider secrets server-side and revocable. | Repeated delivery/retry with the same idempotency key yields one job and one ledger charge. Display an estimate before a paid action; retain auditable usage records. |
| Mobile capture | Test mobile web first, retaining the visual language. Add photo orientation/HEIC handling, subject crop, progress across navigation, resume after upload interruptions and private draft storage. Native clients can then share the authenticated API. | Capture → concept → model → share/download on physical iOS and Android devices; survive backgrounding and reconnecting; permissions and errors are understandable. |
| Agent distribution | Hosted MCP with OAuth and public metadata, desktop workspace adapter, versioned CLI releases and reproducible client configs. | End-to-end tests in ChatGPT, Claude Code and Antigravity: submit once, poll, download into a chosen workspace. No local machine paths in remote tools. |
| Game asset delivery | Optional scale/pivot adjustment, triangle and texture budget presets, LOD/collision exports, source and generation manifest, license/rights metadata. | Import known assets into actual destination game engines and verify materials, orientation, scale and package contents. |

Pricing, native platform priority, app-store submission and public deployment are not selected or executed by this patch. Provider terms and output licensing must be reviewed for the chosen commercial plan; no rights to every photographed subject or generated asset are implied.

## Quality experiments to prioritize

The completed comparisons are in [RECONSTRUCTION_QUALITY.md](RECONSTRUCTION_QUALITY.md). The 4K experiment is a useful higher-detail candidate but not a universal fidelity improvement. The generated turnaround failed because different views changed internal relationships; the consistency gate correctly prevented reconstruction from that set.

Next experiments should isolate one variable at a time with the same source and recorded seed:

- **Real multiview references:** same rigid prop, camera rotated around it, fixed object state. Compare single-image against checked multiview using matched render angles, silhouette overlap and human review of distinctive features. This directly tests whether better evidence helps.
- **Component reconstruction:** reconstruct couch, figures and small props separately for scenes with occlusion; assemble using explicit transforms. Evaluate whether this preserves silhouettes and avoids fused geometry.
- **Texture-only refinement:** freeze accepted geometry, then test sharper texture generation/baking separately. Inspect seams and all camera angles, so better front appearance does not conceal new side/back defects.
- **Export budgets:** evaluate a detailed master and reduced variants in a real game scene. Compare material/UV integrity and visible quality at the target on-screen size.

Do not describe any of these proposed experiments as completed, or a model as an accurate scan merely because it has more triangles or a 4K texture.
