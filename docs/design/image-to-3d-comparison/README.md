# 3D Craft image-to-3D provider comparison

Open [the interactive comparison](index.html) through the repository's local HTTP server. The page loads optimized copies of each finished GLB on demand and lets you orbit it, switch between aligned front/side/back views, toggle clay shading, and download a preview copy. Its cards use local renders of the original outputs. [results.json](results.json) contains sanitized prediction IDs, timing, geometry, texture, and original file-size measurements. The raw provider files remain local because some exceed GitHub's file limit. The Atlas API credential and temporary signed media URLs are deliberately absent.

## What was tested

The input was 3D Craft's existing [Cloud Dragon concept](../gallery-samples/cloud-dragon.png), a 1254 × 1254 PNG. Each of the ten image-capable endpoints in AtlasCloud's [3D catalog](https://www.atlascloud.ai/models?type=Text-to-3D%2CImage-to-3D) received one generation request using that uploaded image. This included the Meshy multi-image endpoint with **one** reference, so it does not demonstrate the benefit of multiple views. The catalog's four text-only endpoints were excluded from a same-image comparison.

The existing [Rodin gallery generation](../gallery-samples/README.md) is the app-specific baseline. Rodin used the app's 1024-pixel reference normalization, quality `high`, tier `Regular`, PBR materials, `concat` conditioning, and one reference. Atlas received the unchanged 1254-pixel PNG. These are comparable product-flow outputs, but not identical pixel-level inputs or synchronized model versions. There was one run per model and no prompt tuning, seed matching, manual cleanup, remeshing, or retopology.

| Atlas endpoint | Tested parameters beyond the common image | Listed cost, USD |
| --- | --- | ---: |
| Seed3D 2.0 | High subdivision, GLB | $0.353 |
| Tripo H3.1 | Texture + PBR, standard geometry and texture quality | $0.220 |
| Hunyuan Rapid | PBR on | $0.500 |
| Hunyuan Pro | Normal generation, PBR on | $0.700 |
| HI3D v2.1 Fast | Texture + PBR on | $0.425 |
| HI3D v2.1 Pro | Texture + PBR on | $0.765 |
| HI3D v3.0 Quality | Texture + PBR on | $1.105 |
| HI3D v3.0 Master | Texture + PBR on | $5.185 |
| Meshy v7 | Texture + PBR, Ultra off, 2K texture | $0.660 |
| Meshy v7 Multi | One image, texture + PBR, Ultra off, 2K texture | $0.660 |

Prices were read from AtlasCloud's [detailed pricing page](https://www.atlascloud.ai/pricing/models) on 24 September 2026 with the tested options selected. Some model-card “from” prices and README examples show different settings or stale amounts. The table therefore uses the detailed rate card, and the page displays a provider-reported per-job price only when the prediction response supplied one. The ten Atlas rate-card amounts sum to **$10.573**. The test account's available balance moved from **$23.504388 to $12.931388**, also a **$10.573** change. This is an aggregate balance observation, not ten itemized invoices; prices and billing may change.

**Cost decision:** Do not spend our own test balance on another model priced at about $1 or more per generation. HI3D Quality ($1.105) and HI3D Master ($5.185) had already completed before that cap was set. They remain selectable in the app for users who choose their Token price. This page performs no API generation.

## How to read the result

For this dragon, Rodin's 10.4 MB, 91,878-triangle GLB remains a strong mobile baseline. Hunyuan Rapid is similarly light (12.6 MB, 49,272 triangles) and fastest, but costs more and its face and unseen back depart more from the source. Tripo ($0.22, **$0.18 less** than Rodin) and Seed3D ($0.353, **$0.047 less**) are the only lower-cost Atlas candidates in this one run. Both preserve the overall character, yet deliver 45–47 MB files with one million or more triangles. Any mesh/texture optimization has its own processing cost, so an end-to-end saving is not yet proven. Tripo's source-facing direction is +X in its GLB, so the comparison viewer aligns its front view without modifying the downloadable file.

The higher HI3D, Meshy, and Hunyuan Pro tiers produce complete textured characters, but their 46–115 MB files and invented rear details weaken their value for an iPhone-first app at the tested prices. HI3D Master is especially disproportionate: $5.185 and a 115 MB, five-million-triangle GLB. A large triangle count or 8K texture does not establish better usability, rigging, animation, or fidelity on unseen sides.

Geometry and texture figures were measured from the delivered GLBs with `trimesh`. Timing is Atlas's `latency_ms` from completed predictions, not a guaranteed end-user wait time. Visual notes describe these specific outputs under common comparison lighting. The interactive viewer uses smaller display copies from the iOS app; its reported file sizes and triangle counts describe the original outputs. Tripo's camera orientation and the common lighting are for inspection only. Large raw outputs may load slowly and require decimation and texture compression before shipping to phones or browser games. The biggest raw file is over GitHub's usual 100 MB file limit.

The app now defaults to Tripo H3.1 at the user's request; that product choice is broader than this single-sample research conclusion. Any further representative pilot using our own credits should stay below the new test cost cap, include a thin-accessory character and a hard-surface object, confirm image handoff and prediction polling, verify final GLB maps and iPhone performance, and keep Token reservation/refund behavior intact. A real multi-view comparison needs matched front, side, and back input images rather than one front image repeated through a multi-image endpoint.

## Source documentation

- [AtlasCloud 3D catalog](https://www.atlascloud.ai/models?type=Text-to-3D%2CImage-to-3D)
- [AtlasCloud pricing](https://www.atlascloud.ai/pricing/models)
- [AtlasCloud file upload](https://www.atlascloud.ai/docs/upload-files) and [prediction status API](https://www.atlascloud.ai/docs/predictions)
- [Tripo H3.1 API](https://www.atlascloud.ai/docs/en/more-models/tripo-h3.1/image-to-3d/generateImage)
- [Hunyuan Pro API](https://www.atlascloud.ai/docs/more-models/tencent/hunyuan3d-pro-image-to-3d/generateImage)
- [fal Rodin model](https://fal.ai/models/fal-ai/hyper3d/rodin) and [3D Craft's Rodin generation record](../gallery-samples/README.md)
