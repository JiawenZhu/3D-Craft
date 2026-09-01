# The two engines

## Tencent Hunyuan3D-2.1

- Space: <https://huggingface.co/spaces/tencent/Hunyuan3D-2.1>
- Weights: <https://huggingface.co/tencent/Hunyuan3D-2.1> (public, ungated)
- Code: <https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1>

Two stages. **Hunyuan3D-DiT** is a flow-matching shape model that denoises a latent
into an occupancy field, which is meshed by marching cubes. **Hunyuan3D-Paint** then
synthesises real PBR maps (albedo / metallic / roughness) onto the mesh.

The shape stage is ordinary PyTorch, so it runs on CUDA, MPS and CPU — this is the
only part of either engine that works natively on an Apple Silicon Mac. The paint
stage depends on a custom CUDA rasterizer and does not.

Its Space accepts up to four named views (`front` / `back` / `left` / `right`) in
addition to the primary image.

> The Space's `/shape_generation` endpoint currently raises `TypeError` for every
> input; `/generation_all` is the only working entry point, and it requests a 270 s
> ZeroGPU slot.

## Microsoft TRELLIS.2

- Space: <https://huggingface.co/spaces/microsoft/TRELLIS.2>
- Weights: <https://huggingface.co/microsoft/TRELLIS-image-large> (public, ungated)
- Code: <https://github.com/microsoft/TRELLIS>

**Structured LATents (SLAT)**: a single latent that decodes into a radiance field, a
set of 3D Gaussians *and* a mesh. Generation is two flow models — a sparse-structure
pass that decides which voxels are occupied, then a SLAT pass that fills them.

Faster than Hunyuan and multi-image native (pose-free). It needs `spconv`,
`nvdiffrast` and `diff-gaussian-rasterization`, all CUDA-only, so outside an NVIDIA
box it runs through its Space.

Its Space is stateful: `/start_session` → `/preprocess_image` → `/image_to_3d` →
`/extract_glb`, all on one client.

## Picking between them

Use the **A/B** toggle next to the engine switcher — it runs one input through both
and shows them side by side.

| | Hunyuan3D-2.1 | TRELLIS.2 |
|---|---|---|
| PBR textures | yes | vertex colour / baked only |
| Gaussian splat output | no | yes |
| Multi-image input | 4 named views | native, pose-free |
| Runs natively off CUDA | shape stage only | no |
| Relative speed | slower | faster |
| Licence | Tencent Hunyuan non-commercial | MIT |
