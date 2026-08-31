# Rodin 3D Studio Architecture & Technical Specification

## Overview

**Rodin 3D Studio** is a next-generation 3D generative studio inspired by **Hyper3D Rodin** (`https://hyper3d.ai/workspace/rodin`), engineered specifically for game developers, technical artists, and 3D character creators. It integrates state-of-the-art open-source 3D foundation models:

- **Tencent Hunyuan3D-2.1**: High-fidelity multi-view diffusion with 4K PBR texture baking.
- **Microsoft TRELLIS.2**: Structured 3D Latent Diffusion Model (SLaD) generating 3D Gaussian Splats, Radiance Fields, and clean quad-dominant meshes.

```
+-----------------------------------------------------------------------------------+
|                            Rodin 3D Studio Frontend                               |
|                                                                                   |
|  +---------------------------+  +------------------------+  +------------------+  |
|  |     Generative Panel      |  |  Interactive Viewport  |  | Material & PBR   |  |
|  | - Text-to-3D / Image-to-3D|  | - Three.js / R3F       |  | - Albedo / Normal|  |
|  | - Style & Prompt Presets  |  | - OrbitControls & Grid |  | - Roughness/Metal|  |
|  | - Engine Switcher         |  | - Studio Lighting Rig  |  | - Topology Stats |  |
|  +-------------+-------------+  +-----------+------------+  +--------+---------+  |
+----------------|----------------------------|------------------------|------------+
                 |                            |                        |
                 | REST / WebSocket           | WebGL Render Stream    |
                 v                            v                        |
+----------------------------------------------------------------------+------------+
|                         FastAPI Engine Orchestrator                               |
|                                                                                   |
|  +-------------------------------------+  +------------------------------------+  |
|  |       Hunyuan3D-2.1 Bridge          |  |         TRELLIS.2 Bridge           |  |
|  | - Multi-View Synthesis Prior        |  | - Structured Latent Diffusion (SLat)|  |
|  | - Neural Mesh Reconstruction        |  | - Radiance Field & Gaussian Splat  |  |
|  | - 4K PBR Texture Baking (UV Space)  |  | - Micro-surface Quad Mesh Extractor|  |
|  +-------------------------------------+  +------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 1. The 3D Generative Pipeline

```
[Text Prompt / 2D Concept Image]
               │
               ▼
[Step 1: Multi-View & Background Preprocessing]
   • Background removal (BiRefNet / RMBG-2.0)
   • Multi-view canonical pose alignment (Front, 3/4, Side, Back)
               │
               ▼
[Step 2: 3D Latent Representation & Geometry Synthesis]
   • TRELLIS: Sparse 3D Structured Latent (SLaD) diffusion
   • Hunyuan3D: 3D DiT (Diffusion Transformer) point cloud & implicit field
               │
               ▼
[Step 3: Mesh Extraction & Topology Optimization]
   • Dual Marching Cubes & Poisson Surface Reconstruction
   • Quad-dominant remeshing and decimation (5k to 100k polygon LODs)
               │
               ▼
[Step 4: PBR Texture Baking]
   • Automatic UV Unwrapping (XAtlas)
   • Neural Texture Baking: Albedo, Normal, Roughness, Metallic, AO (4096 x 4096)
               │
               ▼
[Step 5: Client-Side Interactive 3D Delivery]
   • Direct streaming into Three.js / React Three Fiber viewport
   • 1-Click Game Engine Export: .GLB, .OBJ, .FBX, .USDZ, .PLY (Gaussian Splat)
```

---

## 2. Model Architecture Comparison

| Feature | Tencent Hunyuan3D-2.1 | Microsoft TRELLIS.2 |
| :--- | :--- | :--- |
| **Foundation Model** | Multi-View Diffusion + 3D DiT | Structured 3D Latent Diffusion (SLaD) |
| **Output Representations** | Textured Polygonal Mesh | 3D Gaussian Splats + Radiance Field + Mesh |
| **Topology Quality** | Uniform Quad/Triangle, smooth surfaces | Sharp micro-geometry, clean hard-surface edges |
| **Texture Resolution** | Up to 4096 x 4096 PBR | Up to 4096 x 4096 PBR |
| **Inference Latency** | ~35 seconds | ~18 seconds |
| **Min VRAM Requirement** | 12 GB (BF16) | 16 GB (FP16/BF16) |
| **Best Used For** | Organic characters, stylized anime, flowing cloth | Cyberpunk mechs, hard-surface armor, weapons, Gaussian splats |
