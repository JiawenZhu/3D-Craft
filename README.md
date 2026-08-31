# Rodin 3D Studio (`rodin-3d-studio`)

> Next-generation 3D game character and asset creation studio inspired by [Hyper3D Rodin](https://hyper3d.ai/workspace/rodin), powered by **Tencent Hunyuan3D-2.1** and **Microsoft TRELLIS.2**.

---

## 🌟 Highlights & Capabilities

- 🎨 **Text-to-3D & Image-to-3D Synthesis**: Generate production-ready 3D game characters from natural language prompts or 2D concept art in under 30 seconds.
- 🧠 **Multi-Model Generative Engines**:
  - **[Tencent Hunyuan3D-2.1](https://huggingface.co/spaces/tencent/Hunyuan3D-2.1)**: Industry-grade multi-view diffusion with 4K PBR texture baking (Albedo, Normal, Roughness, Metallic).
  - **[Microsoft TRELLIS.2](https://huggingface.co/spaces/microsoft/TRELLIS.2)**: Structured 3D Latents (SLaD) producing dual 3D Gaussian Splats + high-detail Quad Meshes.
  - **Rodin Hybrid Dual-Pass**: Blends TRELLIS structural geometry with Hunyuan3D 4K texture refinement.
- 🕹️ **Interactive WebGL 3D Viewport**: Built on Three.js & React Three Fiber with dynamic studio lighting rigs (Studio, Cyberpunk Neon, Sunset, Dramatic, Dawn), wireframe modes, and camera orbit controls.
- 🔍 **Material & Shader Channel Inspector**: Inspect isolated Albedo, Normal maps, Roughness, Metallic passes, and polygon topology metrics in real time.
- 📦 **1-Click Game Engine Exports**: Export directly to `.GLB`, `.OBJ`, `.FBX`, `.USDZ` (Apple Vision Pro/AR), and `.PLY` (3D Gaussian Splats).

---

## 📚 Documentation & Architecture

- 🏗️ **[System Architecture](./docs/ARCHITECTURE.md)** — Generative pipeline, latent diffusion representation, and Three.js client architecture.
- 🧠 **[Models Guide](./docs/MODELS_GUIDE.md)** — Deep dive into Tencent Hunyuan3D-2.1 and Microsoft TRELLIS.2.
- 💻 **[Local Deployment & GPU Setup](./docs/LOCAL_DEPLOYMENT.md)** — NVIDIA CUDA and Apple Silicon MPS instructions.

---

## 🚀 Quickstart

```bash
# 1. Clone & enter project folder
cd /Users/jiawenzhu/Developer/rodin-3d-studio

# 2. Install dependencies
npm install

# 3. Start development studio (opens in browser at http://localhost:3000)
npm run dev
```

---

## 🛠️ Tech Stack

- **Frontend**: React 18, TypeScript, Vite, TailwindCSS, Lucide Icons.
- **3D Graphics**: Three.js, `@react-three/fiber`, `@react-three/drei`.
- **Backend API**: Python 3.11+, FastAPI, Uvicorn, Gradio Client, PyTorch.
- **Foundation Models**: Tencent Hunyuan3D-2.1 & Microsoft TRELLIS.2.
