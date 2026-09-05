# Rodin 3D Studio

A local image-to-3D workspace modelled on [Hyper3D Rodin](https://hyper3d.ai/workspace/rodin),
driving two open models: **Tencent Hunyuan3D-2.1** and **Microsoft TRELLIS.2**.

The UI is a close recreation of the Rodin workspace — the same generator card, mode
rails, effort tiers, asset shelf and workbench. The backend is real: each engine runs
either natively on your own GPU or against its official Hugging Face Space.

---

## Quickstart

```bash
npm install && npm run dev
```

That alone gets you the full interface. Generations run in **preview mode** (simulated)
until an inference server is up, so every control is usable immediately.

To generate real meshes:

```bash
./scripts/setup.sh --local          # venv + torch (CUDA / MPS / CPU auto-detected)
python scripts/fetch_weights.py     # source repos + Hunyuan3D shape weights (~7.5 GB)
npm run server                      # http://127.0.0.1:8000
```

`npm run doctor` prints exactly what your machine can and cannot run.

---

## Recommended: run it on fal

For anything resembling production, use fal.ai. It hosts the same models, returns in
seconds instead of minutes, and costs cents per asset.

```bash
export FAL_KEY=...     # from fal.ai/dashboard/keys
npm run server
```

That is the whole setup. Every engine switches to `provider=api` automatically, and
the GENERATE button shows the real dollar cost of the run on hover before you click.

| engine | fal endpoint | per generation |
|---|---|---|
| **TRELLIS.2** | `fal-ai/trellis` | **$0.02** |
| **Hunyuan3D-2.1** | `fal-ai/hunyuan3d/v2` | $0.16 · $0.48 textured |
| **Rodin Gen-2** | `fal-ai/hyper3d/rodin` | $0.40 |

`FAL_KEY` is read by the Python server only — the browser never sees it, which is
what fal's docs require. Never put it in Vite env vars.

---

## The concept pass

Image-to-3D inherits every flaw of its input. A cluttered background becomes
geometry, a cropped limb becomes a hole in the mesh, and hard shadows bake into the
albedo where no relighting will ever remove them. So a photo does not go straight to
the reconstructor:

```
your photo + a few words
        │
        ├─► Gemini writes the full image prompt      gemini-3.7-flash    ~7s
        ├─► Gemini renders a clean studio asset      gemini-3-pro-image  ~17s
        └─► TRELLIS / Hunyuan / Rodin reconstruct it fal.ai              ~30s
```

```bash
export GEMINI_API_KEY=...    # aistudio.google.com/apikey
npm run server
```

The four stages are drawn as a node board under the generator, each separately
retryable — a bad mesh re-runs the mesh, not the render you already paid for. Runs
persist to `server/runs/<id>/run.json`, so a refresh mid-run loses nothing.

Two consequences worth knowing:

- **Text-to-3D works now.** With no image, Gemini draws one from the words, and the
  reconstructor takes it from there. Both engines are image-conditioned; this is the
  image.
- **Re-prompting an asset means re-running the concept.** TRELLIS and Hunyuan read
  the *image*, not the prompt — feeding the same picture back with different words
  changes almost nothing. The workbench routes re-prompts for pipeline assets back
  through Gemini, which is what makes the wording reach the geometry.

Like `FAL_KEY`, `GEMINI_API_KEY` is server-side only. Never give it a `VITE_` prefix:
Vite inlines `VITE_*` into the browser bundle and publishes it to everyone who loads
the page.

## What runs where

Each engine picks a provider automatically
(`RODIN_PROVIDER=auto|api|local|space`; `auto` prefers fal, then native, then Space).

| | fal API | native (local GPU) | hosted Space |
|---|---|---|---|
| **Hunyuan3D-2.1 shape** | ✅ | CUDA, **Apple MPS**, CPU | ✅ |
| **Hunyuan3D-2.1 PBR paint** | ✅ | CUDA only — needs the custom rasterizer | ✅ |
| **TRELLIS.2** | ✅ | CUDA only — spconv / nvdiffrast / diff-gaussian-rasterization | ✅ |
| **Rodin Gen-2** | ✅ | — no open release | — |

Without a `FAL_KEY` on an Apple Silicon Mac you still get **Hunyuan3D-2.1 geometry
natively and unlimited**, and TRELLIS.2 through its Space. Native MPS is slow but
real — an Extreme-Low run on an M5 Pro takes ~6 min and returns a watertight
~270k-face mesh. The effort dropdown reads its estimates from the server, so they
always match whatever the engine is actually running on.

### Hosted Spaces need a token

The Space fallback runs on ZeroGPU. Anonymous quota is small, and Hunyuan's
`/generation_all` asks for a 270 s GPU slot anonymous callers cannot get at all:

```bash
export HF_TOKEN=hf_...
```

A free token covers TRELLIS.2; Hunyuan's texturing path wants a PRO-tier slot. This
is a fallback — prefer `FAL_KEY`.

---

## Comparing the two engines

The **A/B** toggle beside the engine switcher runs one input through the selected
engine *and* a rival of your choosing (`vs …` cycles it), then opens them side by side —
same shading, same lighting, same turntable, with face counts, texture resolution and
file size under each. With a fal key that includes Rodin, so you can answer the only
question that matters: is Rodin at $0.40 actually 20× better than TRELLIS at $0.02
**for your assets**?

Rules of thumb so far:

- **Hunyuan3D-2.1** is the only one of the two that outputs real PBR maps, and its
  shape model is the one that runs natively outside CUDA.
- **TRELLIS.2** is faster, multi-image native (pose-free), and additionally emits 3D
  Gaussians alongside the mesh.

---

## Working alongside an image/animation agent

The two halves share this repo and hand off through one folder:

| side | produces | consumes |
|---|---|---|
| image / animation | concept art, turnarounds, hero renders → `server/inbox/` | — |
| **this studio** | 3D meshes → `server/storage/` | `server/inbox/` |

Drop `.png` / `.jpg` / `.webp` into `server/inbox/` and they show up behind the
**Sample images** button in the input card, one click from a generation. A
`_front` / `_back` / `_left` / `_right` suffix on the filename is read as the view
direction, so a multi-view set arrives pre-tagged — which measurably improves the
back side on both engines.

`GET /api/inbox` lists what is there; the folder is gitignored, so large reference
sets never bloat the repo.

## Layout

```
src/
  components/generator/   the Rodin generator card — mode rail, input card, effort tiers
  components/workbench/   three.js viewport, single-asset workbench, A/B compare
  store/StudioContext.tsx generation state machine (real backend + preview fallback)
server/
  app.py                  FastAPI: /api/health, /api/generate, /api/jobs, /api/assets
  engines/hunyuan.py      Hunyuan3D-2.1 — native MPS/CUDA + Space provider
  engines/trellis.py      TRELLIS.2 — native CUDA + Space provider
  engines/rodin.py        Hyper3D Rodin — API only, via fal
  engines/fal_api.py      shared fal provider: upload, subscribe, download
  inbox/                  hand-off folder for reference images (gitignored)
  engines/hybrid.py       TRELLIS geometry piped into Hunyuan paint
scripts/
  setup.sh                venv, torch, dependencies
  fetch_weights.py        clones upstream repos, pulls weights
  doctor.py               capability report
```

## Environment

| variable | meaning |
|---|---|
| `HF_TOKEN` | Hugging Face token — raises ZeroGPU quota and download limits |
| `FAL_KEY` | fal.ai key — enables the `api` provider and the Rodin engine |
| `GEMINI_API_KEY` | Google AI Studio key — enables the concept pass |
| `RODIN_GEMINI_TEXT_MODEL` | prompt writer (default `gemini-3.7-flash`) |
| `RODIN_GEMINI_IMAGE_MODEL` | concept renderer (default `gemini-3-pro-image`) |
| `RODIN_PROVIDER` | `auto` (default), `api`, `local`, or `space` |
| `RODIN_WEIGHTS` | weights directory (default `server/weights`) |
| `RODIN_MPS_DTYPE` | `float32` to force the slower, higher-precision MPS path |
| `RODIN_PORT` | API port (default 8000) |
| `VITE_API_BASE` | where the frontend looks for the API |

## Docs

- [Local deployment](docs/LOCAL_DEPLOYMENT.md) — install, providers, Apple Silicon notes, API reference
- [The two engines](docs/MODELS_GUIDE.md) — how each model works and when to reach for it
- [Firebase schema](docs/FIREBASE.md) — the target collections, rules and indexes for when the store moves off localhost

## Licences

Hunyuan3D-2.1 is released under the Tencent Hunyuan Non-Commercial licence; TRELLIS
under MIT. Check both before shipping anything commercial.
