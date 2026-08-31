# Models Guide: Tencent Hunyuan3D-2.1 & Microsoft TRELLIS.2

This guide details the theoretical foundation, installation methods, and performance characteristics of the two primary 3D foundation models integrated into Rodin 3D Studio.

---

## 1. Tencent Hunyuan3D-2.1

### Model Overview
- **Hugging Face Space**: [https://huggingface.co/spaces/tencent/Hunyuan3D-2.1](https://huggingface.co/spaces/tencent/Hunyuan3D-2.1)
- **Primary Strength**: High-resolution photorealistic and stylized character synthesis with industry-grade PBR texture maps (Albedo, Normal, Roughness).
- **Core Architecture**:
  - Employs a multi-view generation stage that synthesizes consistent orthogonal and perspective character views from a single prompt or concept image.
  - Passes multi-view features into a 3D Diffusion Transformer (DiT) conditioned on point cloud priors to generate a dense, manifold 3D mesh.
  - Automatically performs non-overlapping UV chart packing and texture projection with neural inpainting for self-occluded regions.

---

## 2. Microsoft TRELLIS.2

### Model Overview
- **Hugging Face Space**: [https://huggingface.co/spaces/microsoft/TRELLIS.2](https://huggingface.co/spaces/microsoft/TRELLIS.2)
- **Primary Strength**: Structured 3D Latents (SLaD) producing dual representations: **3D Gaussian Splats** (instant real-time view synthesis) and **Textured Quad Meshes** in under 20 seconds.
- **Core Architecture**:
  - Discretizes 3D space into structured latent feature volumes, avoiding traditional NeRF training bottlenecks.
  - Generates sharp geometric discontinuities, making it ideal for hard-surface armor, mechs, weapons, and complex accessories.
  - Supports direct extraction of 3D Gaussian Splat PLY files for web/AR rendering alongside standard GLB game engine assets.

---

## 3. Rodin Hybrid Dual-Pass Engine

For production-grade game character workflows:
1. **Pass 1 (TRELLIS.2)**: Extracts the high-density base geometry and hard-surface contours in ~18 seconds.
2. **Pass 2 (Hunyuan3D-2.1 Texture Refinement)**: Applies multi-view neural texture refinement to bake 4K ray-traced materials with sub-surface scattering approximations.
