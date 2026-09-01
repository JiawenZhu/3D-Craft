# Local deployment

## Requirements

| | minimum | notes |
|---|---|---|
| Python | 3.10 – 3.12 | torch has no wheels for 3.13+ yet; `setup.sh` picks a valid one |
| Disk | ~8 GB | Hunyuan3D shape weights alone are 7.5 GB |
| GPU | none required | Hunyuan3D shape runs on MPS and CPU; everything else falls back to the hosted Spaces |

For **full** native inference (both engines, textures included) you need an NVIDIA
GPU with 16 GB+ VRAM — the TRELLIS kernels and the Hunyuan paint rasterizer are
CUDA-only.

## Install

```bash
./scripts/setup.sh --local        # venv at server/.venv + torch for your platform
python scripts/fetch_weights.py   # upstream repos + Hunyuan3D shape weights
npm run doctor                    # what this machine can actually run
npm run server                    # http://127.0.0.1:8000
```

`fetch_weights.py` flags:

- `--paint` — Hunyuan3D PBR paint weights (only useful on CUDA)
- `--trellis` — TRELLIS-image-large weights + the TRELLIS repo (only useful on CUDA)
- `--all` — both

## Providers

Each engine resolves a provider at request time:

- `api` — fal.ai serverless, via `fal_client` (needs `FAL_KEY`)
- `local` — native torch pipeline from `server/vendor/`
- `space` — the model's official Hugging Face Space over `gradio_client`

`RODIN_PROVIDER=auto` (the default) prefers `api` when `FAL_KEY` is set, then `local`
when the package and weights are present, then `space`. Force one with
`RODIN_PROVIDER=local`.

### fal

```bash
export FAL_KEY=...
npm run server
```

Endpoints are overridable so a new model version is a config change, not a code
change: `RODIN_FAL_TRELLIS`, `RODIN_FAL_HUNYUAN`, `RODIN_FAL_HUNYUAN_MV`,
`RODIN_FAL_RODIN`.

Two things the adapter handles that are easy to get wrong:

- **Result URLs are not permanent.** Every generation is downloaded into
  `server/storage/<asset>/model.glb` immediately rather than linked.
- **The key stays server-side.** The React app only ever talks to this process. Do not
  put `FAL_KEY` in a `VITE_*` variable — that ships it to the browser.

Costs are surfaced in the UI: the GENERATE button shows the real dollar total for the
run (engine × batch, both engines when A/B is on) on hover.

## Hugging Face token

Both Spaces are ZeroGPU. Without a token you get a small anonymous quota, and
Hunyuan's `/generation_all` requests a 270 s GPU slot that anonymous callers are not
allowed at all.

```bash
export HF_TOKEN=hf_...
npm run server
```

## Apple Silicon specifics

- The DiT is ~3.3B parameters and loads in **float16** on MPS (~7 GB). float32 needs
  roughly 14 GB of weights alone and can get the process hard-killed on a 48 GB Mac.
  If you see NaN geometry, force the slower path with `RODIN_MPS_DTYPE=float32`.
- Surface extraction uses `mc_algo='mc'` (skimage marching cubes) because the faster
  `dmc` path needs the CUDA-only `diso` kernel.
- **Expect it to be slow.** Measured on an M5 Pro: Extreme-Low (12 steps, octree 192)
  takes ~6 minutes end to end and yields a watertight ~270k-face mesh. The effort
  dropdown pulls its estimates from the server, so the numbers you see are for the
  device you are actually on.
- Decimation needs `fast_simplification` (installed by `setup.sh --local`); without it
  you get the full-resolution mesh and the job log says so.
- Hunyuan3D Paint is skipped; you get clean geometry with no texture. Use TRELLIS.2
  via its Space, or the Hunyuan Space, when you need a textured result.

## API

| route | purpose |
|---|---|
| `GET /api/health` | device, torch version, per-engine provider and status |
| `POST /api/generate` | multipart: `settings` JSON + `images[]` + `directions[]` → `{job_id}` |
| `GET /api/jobs/{id}` | stage, progress, message, and the assets once done |
| `GET /api/assets` | everything generated so far |
| `DELETE /api/assets/{id}` | remove an asset and its files |
| `GET /files/{asset}/{name}` | the produced `.glb` / `.ply` / thumbnail |
