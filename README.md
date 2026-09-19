<p align="center">
  <img src="docs/app-store/2026-09-12/branding/AppIcon-1024.png" width="128" height="128" alt="3D Craft Icon" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0,0,0,0.15);" />
</p>

<h1 align="center">3D Craft</h1>

<p align="center">
  <strong>From Idea to 3D in Seconds — A complete creative studio & generative 3D pipeline for iOS, Web, and Cloud.</strong>
</p>

<p align="center">
  <a href="#-what-is-3d-craft">What is 3D Craft</a> •
  <a href="#-key-features">Key Features</a> •
  <a href="#-visual-showcase">Visual Showcase</a> •
  <a href="#-how-it-works">How It Works</a> •
  <a href="#-quickstart">Quickstart</a> •
  <a href="#-developer-api--agent-integrations">API & Agents</a> •
  <a href="#-engines-comparison">3D Engines</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/iOS-17.0%2B-blue?logo=apple&style=flat-square" alt="iOS 17+" />
  <img src="https://img.shields.io/badge/Swift-5.0-orange?logo=swift&style=flat-square" alt="Swift 5" />
  <img src="https://img.shields.io/badge/React-18.3-blue?logo=react&style=flat-square" alt="React 18" />
  <img src="https://img.shields.io/badge/Three.js-0.173-black?logo=three.js&style=flat-square" alt="Three.js" />
  <img src="https://img.shields.io/badge/FastAPI-Python_3.11%2B-teal?logo=fastapi&style=flat-square" alt="FastAPI" />
  <img src="https://img.shields.io/badge/Firebase-Auth%20%7C%20Firestore-yellow?logo=firebase&style=flat-square" alt="Firebase" />
  <img src="https://img.shields.io/badge/Cloud_Run-GCP-blue?logo=googlecloud&style=flat-square" alt="Google Cloud Run" />
</p>

---

## 💡 What is 3D Craft?

**3D Craft** bridges the gap between imagination and ready-to-use 3D models. Standard image-to-3D models often fail because real-world photos contain cluttered backgrounds, irregular lighting, and baked-in shadows that ruin 3D meshes. 

3D Craft solves this through an intelligent **multimodal AI pipeline**:
1. **Creative Dialogue**: You describe an idea or upload a reference sketch/photo.
2. **AI Concept Pass**: Google Gemini crafts an isolated, background-free studio concept asset with clean geometry lines and neutral lighting.
3. **High-Fidelity 3D Reconstruction**: The concept is transformed into a watertight, textured **GLB 3D model** via state-of-the-art reconstruction engines (**Microsoft TRELLIS.2**, **Tencent Hunyuan3D-2.1**, or **Hyper3D Rodin**).
4. **Interactive 3D Studio**: Inspect models with turntable controls, customize studio lighting, toggle solid/wireframe views, and export GLBs or hand them off directly to game engines and AI coding agents.

---

## ✨ Key Features

- **📱 Native iOS Client (iPhone & iPad)**: High-performance SwiftUI interface with native SceneKit / GLTFKit2 model rendering, dynamic studio lighting, haptic feedback, and offline caching.
- **🌐 Interactive Web Studio**: Responsive Three.js viewport with real-time A/B engine comparisons, face/vertex count diagnostics, and camera orbital stages.
- **🐲 Themed Mascot Waiting Loops**: Expressive procedural animations (Cloud Dragon & Panda Chef) that keep generation and modeling phases delightfully engaging.
- **🔑 Developer API & Agent Integrations**: Full REST API (`/api/v1/creations`) with account-owned API keys (`craft_live_`) enabling external AI agents (Claude Code, Antigravity, OpenAI Codex) to automate 3D workflows with permanent delete protection.
- **⚡ 20-Second Live Background Sync**: Foreground WebSocket/polling synchronization ensures creations made via API or agents appear on device in near real-time without pull-to-refresh.
- **🎮 Play Your Asset (Lanternfall)**: Instantly test generated 3D models inside built-in Godot mini-games or generate structured briefs for external game builders.
- **💳 Cloud Native & Cross-Platform**: Firebase Auth (Sign in with Apple, Google, Email), Cloud Firestore syncing, and StoreKit / RevenueCat Token packs.

---

## 🎨 Visual Showcase

<p align="center">
  <img src="docs/app-store/2026-09-12/promotional/01-lantern-cat-emerald.png" width="48%" alt="Lantern Cat - Emerald Studio" />
  <img src="docs/app-store/2026-09-12/promotional/02-blue-dragon-lavender.png" width="48%" alt="Blue Dragon - Lavender Studio" />
</p>
<p align="center">
  <img src="docs/app-store/2026-09-12/promotional/03-tropical-island-emerald.png" width="48%" alt="Tropical Island - 3D Diorama" />
  <img src="docs/app-store/2026-09-12/promotional/04-panda-chef-lavender.png" width="48%" alt="Panda Chef - Multimodal Concept" />
</p>

---

## 📱 Native iOS Experience (iPhone & iPad)

Designed from the ground up for iOS 17+, 3D Craft gives creators a studio-grade environment right in their pocket.

<p align="center">
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/01-discover.png" width="23%" alt="Discover 3D Assets" />
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/02-model.png" width="23%" alt="3D Model Orbit Inspection" />
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/03-lighting.png" width="23%" alt="Custom Studio Lighting" />
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/04-concept.png" width="23%" alt="Multimodal Concept Generation" />
</p>
<p align="center">
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/05-game-brief.png" width="31%" alt="Interactive Game Brief" />
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/06-objects.png" width="31%" alt="Props & Environments" />
  <img src="docs/app-store/2026-09-12/screenshots/iphone-6.9/07-lavender.png" width="31%" alt="Lavender Theme" />
</p>

---

## 🐲 Themed Mascot Waiting Loops

3D reconstruction can take between 15 and 45 seconds. 3D Craft replaces boring loading spinners with themed, procedural mascot loops:

<p align="center">
  <img src="ios/CraftStudio/Resources/Mascot/mascot-dragon-poster.jpg" width="48%" alt="Cloud Dragon Mascot Loop" />
  <img src="ios/CraftStudio/Resources/Mascot/mascot-panda-poster.jpg" width="48%" alt="Panda Chef Mascot Loop" />
</p>

---

## 🎮 Play Your Asset & Game Handoff

Why stop at looking at your 3D models? 3D Craft lets you play with them immediately:
- **Lanternfall**: Bundled 3D action game with boss battles, responsive touch controls, and dynamic night lighting.
- **AI Game Engine Handoff**: Exports clean game design briefs and models formatted specifically for **Claude Code**, **ChatGPT**, or custom game development scripts.

<p align="center">
  <img src="docs/lanternfall/gameplay-native.png" width="48%" alt="Lanternfall 3D Gameplay" />
  <img src="docs/design/game-handoff/iphone-handoff.png" width="48%" alt="Game Engine Builder Handoff" />
</p>

---

## 🏛️ Built-in 3D Gallery & Inspiration

Browse pre-loaded assets, character concepts, game props, and community creations:

<p align="center">
  <img src="public/gallery/cloud-dragon.jpg" width="18%" alt="Cloud Dragon" />
  <img src="public/gallery/panda-chef.jpg" width="18%" alt="Panda Chef" />
  <img src="public/gallery/moss-robot.jpg" width="18%" alt="Moss Robot" />
  <img src="public/gallery/star-skiff.jpg" width="18%" alt="Star Skiff" />
  <img src="public/gallery/moon-fox.jpg" width="18%" alt="Moon Fox" />
</p>

---

## 🔬 How It Works: The Concept-to-Mesh Pipeline

```
 User Input (Text / Photo / Reference)
                │
                ▼
  [Step 1: Multimodal Prompt Planning]
      Gemini 3.8 Flash / OpenAI Codex
  Analyzes silhouette, symmetry, style & textures (~5s)
                │
                ▼
  [Step 2: Studio Asset Concept Rendering]
      Gemini 3 Pro Image (Imagen 3)
  Produces a background-free, shadow-neutral studio plate (~15s)
                │
                ▼
  [Step 3: 3D Geometry & PBR Reconstruction]
      TRELLIS.2 (Gaussians + Mesh) / Hunyuan3D-2.1 (PBR) / Rodin Gen-2
  Generates watertight topology, normals, roughness & albedo (~30s)
                │
                ▼
  [Step 4: Real-time Inspection & Delivery]
      • Native iOS SceneKit / Three.js Viewport
      • 20s Live Sync to mobile & web clients
      • GLB Export / Mini-game Integration
```

---

## ⚡ Quickstart

### 1. Web Studio (Frontend Only)
Run the complete web studio in preview mode without needing local GPU weights:
```bash
npm install
npm run dev
```
Open [http://localhost:5173](http://localhost:5173) in your browser.

### 2. Local Inference Server (FastAPI)
To generate real meshes locally on your machine (supports Apple Silicon MPS & NVIDIA CUDA):
```bash
# Set up Python virtual environment and dependencies
./scripts/setup.sh --local

# Download Hunyuan3D shape weights (~7.5 GB)
python scripts/fetch_weights.py

# Launch the FastAPI backend
npm run server
```

Run `npm run doctor` to diagnose GPU hardware, acceleration drivers, and dependencies.

### 3. Native iOS App (Xcode)
```bash
cd ios
xcodegen generate
open CraftStudio.xcodeproj
```
Select your connected iPhone or a simulator target and click **Run**.

---

## ☁️ Recommended Cloud Setup: fal.ai & Gemini

For lightning-fast generation without needing a multi-gigabyte local GPU setup:

```bash
export FAL_KEY=your_fal_api_key          # fal.ai/dashboard/keys
export GEMINI_API_KEY=your_gemini_key    # aistudio.google.com/apikey
npm run server
```

The backend automatically switches to cloud mode. Generation runs in seconds and costs pennies per model.

---

## 🔑 Developer API & Agent Integrations

3D Craft 2.0 exposes a complete REST API for external developers and autonomous AI agents:

### Authenticating with API Keys
Generate account-owned API keys (`craft_live_...`) in the web studio or iOS app under **Profile → API access**.

```bash
# One-step Prompt to 3D Generation:
curl -X POST https://3d-craft.web.app/api/v1/creations \
  -H "Authorization: Bearer craft_live_your_key" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "A friendly mechanical frog with brass gears and emerald eyes",
    "engine": "trellis"
  }'
```

### Agent Integration Features:
- **Permanent Delete Guard**: Requires an explicit `"Allow permanent deletes"` toggle in Profile before destructive operations are permitted.
- **Repeat-Safe Keys**: Idempotency headers prevent accidental double billing.
- **Live Sync**: Any project created via API appears in your mobile app within ~20 seconds automatically.

---

## ⚖️ 3D Engines Comparison

| Feature | Microsoft TRELLIS.2 | Tencent Hunyuan3D-2.1 | Hyper3D Rodin Gen-2 |
|---|---|---|---|
| **Speed** | ⚡ Fastest (~15s) | ⏱️ Moderate (~45s) | ⏱️ Studio Grade (~60s) |
| **PBR Maps** | Albedo / Vertex color | Real Normal, Roughness, Metallic | PBR texture maps |
| **Apple Silicon (MPS)** | Space / Cloud only | Native MPS supported | Cloud API only |
| **Output Formats** | GLB, 3D Gaussians (PLY) | GLB, OBJ | GLB |
| **Cost (fal.ai)** | **$0.02** / generation | $0.16 (mesh) · $0.48 (textured) | $0.40 / generation |

---

## 📂 Repository Structure

```
3d-craft/
├── ios/                      # Native iOS client (SwiftUI, iOS 17+)
│   ├── CraftStudio/          # View architecture, SceneKit viewer, motion tokens
│   │   ├── Sources/          # Swift application source files
│   │   └── Resources/        # Mascots, icons, bundled models
│   └── project.yml           # XcodeGen specification
├── src/                      # Web studio frontend (React 18, Vite, Three.js)
│   ├── components/           # Generator card, 3D viewport, workbench
│   └── pages/                # Gallery, Showcase, API Keys manager
├── server/                   # Backend API (Python FastAPI)
│   ├── app.py                # Core routes & job queues
│   ├── api_keys.py           # API key generation, auth, and deletion scopes
│   ├── engines/              # TRELLIS.2, Hunyuan3D-2.1, and Rodin adapters
│   └── storage/              # Local asset cache and run files
├── games/                    # Godot mini-games and game-ready asset templates
├── docs/                     # Specifications, product guides, and screenshots
└── scripts/                  # Setup automation, model fetchers, doctor checks
```

---

## 📄 Licenses

- **Microsoft TRELLIS.2**: MIT License.
- **Tencent Hunyuan3D-2.1**: Tencent Hunyuan Non-Commercial License.
- **3D Craft Core & iOS Client**: Proprietary / All Rights Reserved.
