# Reconstruction quality investigation — 2026-09-09

The current cloud TRELLIS path used `fal-ai/trellis`, despite the UI calling it TRELLIS.2. Adding images or requesting more faces did not make this a newer model. The existing input was a 1024×1024 concept render of two seated people on a couch. We inspected the live viewer and generated two additional meshes and a four-view turnaround. **No tested alternative eliminated the artifacts.**

## Implemented fixes

- TRELLIS fal now submits every supplied reference to `fal-ai/trellis/multi` using `image_urls` and `multidiffusion`. The old path only read image 0. Unsupported non-API providers explicitly reject multiple images instead of silently ignoring them.
- Rodin uses `concat` for views of one object. `fuse` was blending object features. More than five images are rejected instead of silently truncated.
- Generated images carry explicit requested camera directions. Front/back/left/right labels no longer depend on list index; the original photo is excluded from the generated turnaround set. A failed view no longer shifts the labels of later images.
- Hunyuan fal requires exactly front/back/left. Missing or duplicate directions are rejected before upload; views are never substituted. The concept picker only offers those three views to Hunyuan.
- Generate the canonical image first; other views reference that same image. A separate Gemini vision check audits the entire frozen scene, object relationships, pose and occlusion. Failed or unavailable checks disable automatic multi-view reconstruction. This is a heuristic check, not geometric proof or a guarantee of unseen-surface accuracy.
- The automatic concept pipeline uses checked view sets, falling back to one selected image when checks fail. Clicking a concept explicitly chooses single-image reconstruction. Missing files cause an error.
- The modal displays warnings and no longer automatically repeats paid requests after failure. The input shelf reflects the exact references submitted. New assets record input count, directions and generation settings.
- The TRELLIS family label no longer promises a specific cloud version.
- Gray/normal preview materials use flat shading when the GLB lacks vertex normals. This fixes black diagnostic previews without changing the exported mesh.
- A failed view-set retry clears any earlier multi-view selection before falling back to one concept. The comparison page freezes its input image so later Studio runs cannot change the reference.

## Actual experiments

All meshes used `server/runs/run-e3e8936ffb/concept_0.jpg` as the source and seed 0. The baseline was an existing run, not a newly billed rerun. Different algorithms/settings mean differences cannot be attributed to resolution alone.

| Sample | Actual endpoint / parameters | Result |
| --- | --- | --- |
| Existing model | `fal-ai/trellis`, high effort, 2048 texture | 27,910 triangles, 18,430 vertices, 4.88 MB. Fine fingers, controller and facial details are softened or lost. |
| Higher resolution | `fal-ai/trellis-2`, resolution 1536, 18 steps in each stage, decimation target 150000, texture 4096, remesh true | 142,332 triangles, 98,050 vertices, 8.11 MB. Controller is more explicit but eyes/clothes have new defects. Not promoted to a default. |
| Independent engine | `fal-ai/hyper3d/rodin`, high/Regular, PBR, one image | 93,270 triangles, 52,658 vertices, 2048 texture, 9.37 MB. Retains some prop detail but changes proportions/appearance; not an overall fidelity win. |
| Anchored turnaround | Canonical front followed by back/left/right, all referencing the canonical image | Failed. The sofa stays front-facing while people rotate; the rear image has impossible occlusion. Both visual inspection and the automated check reject it. Not submitted for mesh generation. |

The unchanged source photograph is retained in the run folder. This investigation evaluates reconstruction against the concept input, not a quantitative claim of identity preservation against the original photograph.

## Review and reproduction evidence

With the existing Vite server on 3000 and API on 8000, open:

`http://localhost:8000/files/quality-20260909/review.html`

It loads actual GLBs with synchronized orbit controls. Original-color textures remove lighting as a confound; gray material isolates geometry. The local comparison page depends on Three.js served by Vite on port 3000. Experiment files are local and ignored by Git under `server/storage/quality-20260909/`:

- `detail.glb`, `detail-request.json`, `detail-stats.json`
- `rodin/model.glb`, `rodin/stats.json`
- `front.jpg`, `back.jpg`, `left.jpg`, `right.jpg`, `views.json`, `validation.json`
- `review.html`

The two meshes are also recorded as experimental assets in the Studio shelf; the original assets remain unchanged.

Validation: `npm run build`, `venv/bin/python -m unittest discover -s tests -v`, Python compilation, real Gemini view generation + consistency assessment, real TRELLIS.2 and Rodin generation, and rendered model comparison. Tests cover provider payloads, missing/duplicate directions, failed views, consistency-check failure and actual pipeline reference selection. The newly wired TRELLIS multi-image endpoint has offline payload regression coverage; it was not called with the rejected view set. CUDA/Space execution and production deployment were not tested.

## Practical conclusion

A 4K texture cannot restore geometry absent from the reconstruction, and adding inconsistent generated views can make the model worse. For this complex scene, the remaining route to reliable fidelity is to obtain physically consistent views (real captures or renders from an existing 3D scene), or build/refine the people, couch and props separately and assemble them with controlled transforms. Close-up faces, fingers and small props can still require targeted geometry and texture correction. Neither process is implemented or proven by this patch.

## Provider contracts checked

- https://fal.ai/models/fal-ai/trellis/multi/api
- https://fal.ai/models/fal-ai/hunyuan3d/v2/multi-view/api
- https://fal.ai/models/fal-ai/hyper3d/rodin/api
- https://fal.ai/models/fal-ai/trellis-2/api
