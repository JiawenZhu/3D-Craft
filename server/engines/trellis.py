"""
Microsoft TRELLIS.2
https://huggingface.co/spaces/microsoft/TRELLIS.2

Two providers:
  space  — drives the official Space. TRELLIS.2's Gradio app is stateful:
           /start_session -> /preprocess_image -> /image_to_3d -> /extract_glb,
           all on one client so the session hash is shared.
  local  — the native pipeline from microsoft/TRELLIS. It needs CUDA-only
           kernels (spconv, diff-gaussian-rasterization, nvdiffrast), so it is
           only selected on an NVIDIA box.
"""
from __future__ import annotations

from pathlib import Path

from ..config import FAL_ENDPOINTS, FAL_PRICES, WEIGHTS, TRELLIS_RESOLUTIONS, TRELLIS_PRICES
from . import fal_api
from .base import GenRequest, GenResult, Progress
from .common import adopt, prep_image, resolve_provider, space_client

# Wall-clock estimates per effort tier. There is no MPS/CPU row because the
# native pipeline is CUDA-only; anywhere else the Space does the work.
ESTIMATES = {
    "cuda":  {"extreme-low": 5, "low": 9, "medium": 16, "high": 30, "extreme-high": 60},
    "api":   {"extreme-low": 10, "low": 14, "medium": 20, "high": 30, "extreme-high": 50},
    "space": {"extreme-low": 35, "low": 50, "medium": 75, "high": 120, "extreme-high": 200},
}

# Effort tier -> (sparse-structure steps, slat steps, latent resolution)
EFFORT = {
    "extreme-low": (6, 6, "512"),
    "low": (10, 10, "512"),
    "medium": (12, 12, "1024"),
    "high": (18, 18, "1024"),
    "extreme-high": (25, 25, "1536"),
}


class TrellisEngine:
    id = "trellis-2"
    label = "TRELLIS.2"

    def __init__(self) -> None:
        self._pipe = None

    # ------------------------------------------------------------------ status
    def _local_available(self) -> tuple[bool, str]:
        try:
            import torch
        except ImportError:
            return False, "torch not installed — run ./scripts/setup.sh --local"
        if not torch.cuda.is_available():
            return False, "TRELLIS needs CUDA kernels (spconv / nvdiffrast); no NVIDIA GPU here"
        if not (WEIGHTS / "trellis-image-large" / "ckpts").exists():
            return False, "weights missing — run ./scripts/setup.sh --weights"
        try:
            import trellis  # noqa: F401
        except ImportError:
            return False, "trellis package not on the path (clone microsoft/TRELLIS)"
        return True, "native SLAT pipeline ready"

    def status(self) -> dict:
        ok, note = self._local_available()
        provider = resolve_provider(self.id, ok)
        if provider == "space":
            note = "using the hosted Hugging Face Space" + ("" if ok else f" ({note})")
        if provider == "api":
            note = f"fal.ai · {FAL_ENDPOINTS['trellis-2']} · ${FAL_PRICES['trellis-2']:.2f}/gen"
        return {
            "installed": provider == "api" or ok or provider == "space",
            "loaded": self._pipe is not None,
            "note": note,
            "provider": provider,
            "effortSeconds": ESTIMATES.get(provider, ESTIMATES["space"]),
            "pricePerGen": FAL_PRICES["trellis-2"] if provider == "api" else 0.0,
        }

    # ---------------------------------------------------------------- generate
    def generate(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        ok, _ = self._local_available()
        provider = resolve_provider(self.id, ok)
        if len(req.images) > 1 and provider != "api":
            raise ValueError("This TRELLIS provider accepts one image. Use the fal multi-view provider or select one reference.")
        if provider == "api":
            return self._generate_fal(req, out_dir, on)
        if provider == "local":
            return self._generate_local(req, out_dir, on)
        return self._generate_space(req, out_dir, on)

    # -- fal.ai ------------------------------------------------------------
    def _generate_fal(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        if not req.images:
            raise RuntimeError("TRELLIS.2 is image-conditioned — add a reference image.")

        src = prep_image(req.images[0], out_dir / "input")
        on("preprocessing", 0.06, "Uploading reference to fal")
        image_urls = [fal_api.upload(src)]
        for i, path in enumerate(req.images[1:], 1):
            image_urls.append(fal_api.upload(prep_image(path, out_dir / "input" / str(i))))
        endpoint = FAL_ENDPOINTS["trellis-multi"] if len(image_urls) > 1 else FAL_ENDPOINTS["trellis-2"]
        image_args = ({"image_urls": image_urls}
                      if len(image_urls) > 1 else {"image_url": image_urls[0]})

        ss_steps, slat_steps, _ = EFFORT.get(req.effort, EFFORT["high"])
        if req.quality == "speedy":
            ss_steps = max(4, int(ss_steps * 0.6))
            slat_steps = max(4, int(slat_steps * 0.6))

        resolution = 1024 if len(image_urls) > 1 else TRELLIS_RESOLUTIONS.get(req.effort, 1024)

        result = fal_api.run(
            endpoint,
            {
                **image_args,
                "seed": req.seed if req.seed is not None else 0,
                "ss_guidance_strength": float(req.guidance),
                "ss_sampling_steps": int(ss_steps),
                "resolution": resolution,
                "shape_slat_guidance_strength": float(req.guidance),
                "shape_slat_sampling_steps": int(slat_steps),
                "tex_slat_sampling_steps": int(slat_steps),
                "decimation_target": max(5000, min(2000000, req.target_faces or 500000)),
                "texture_size": 2048 if req.texture else 1024,
            },
            on, "sparse-structure", 0.12, 0.9,
        )

        url = fal_api.pick_file(result, "model_glb")
        if not url:
            raise RuntimeError(f"fal returned no mesh (keys: {sorted(result)})")

        on("packaging", 0.94, "Downloading GLB")
        mesh = fal_api.download(url, out_dir / "model.glb")
        return GenResult(
            mesh_path=mesh, thumb_path=adopt(src, out_dir / "thumb.png"), provider="api",
            note=f"fal.ai · {endpoint} · {len(image_urls)} reference(s) · {resolution}p · ${TRELLIS_PRICES[resolution]:.2f}",
        )

    # -- hosted Space ------------------------------------------------------
    def _generate_space(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        from gradio_client import handle_file

        if not req.images:
            raise RuntimeError(
                "TRELLIS.2 is image-conditioned. Drop a reference image, or "
                "generate one first with a text-to-image model."
            )

        on("preprocessing", 0.04, "Connecting to the TRELLIS.2 Space")
        client = space_client(self.id)
        if client is None:
            raise RuntimeError("gradio_client unavailable; run ./scripts/setup.sh")

        # The app keeps per-session state between image_to_3d and extract_glb.
        client.predict(api_name="/start_session")

        src = prep_image(req.images[0], out_dir / "input")
        on("preprocessing", 0.1, "Removing background · normalising input")
        prepped = client.predict(input=handle_file(str(src)), api_name="/preprocess_image")

        seed = float(req.seed if req.seed is not None else 0)
        if req.seed is None:
            seed = float(client.predict(randomize_seed=True, seed=0, api_name="/get_seed"))

        ss_steps, slat_steps, resolution = EFFORT.get(req.effort, EFFORT["high"])
        if req.quality == "speedy":
            ss_steps = max(4, int(ss_steps * 0.6))
            slat_steps = max(4, int(slat_steps * 0.6))

        on("sparse-structure", 0.2, f"Sparse structure · {ss_steps} steps @ {resolution}")
        client.predict(
            image=handle_file(prepped if isinstance(prepped, str) else prepped["path"]),
            seed=seed,
            resolution=resolution,
            ss_guidance_strength=float(req.guidance),
            ss_guidance_rescale=0.7,
            ss_sampling_steps=float(ss_steps),
            ss_rescale_t=5.0,
            shape_slat_guidance_strength=float(req.guidance),
            shape_slat_guidance_rescale=0.5,
            shape_slat_sampling_steps=float(slat_steps),
            shape_slat_rescale_t=3.0,
            tex_slat_guidance_strength=1.0,
            tex_slat_guidance_rescale=0.0,
            tex_slat_sampling_steps=float(slat_steps),
            tex_slat_rescale_t=3.0,
            api_name="/image_to_3d",
        )

        on("mesh", 0.75, "Extracting mesh · decimating")
        extracted = client.predict(
            decimation_target=float(max(5_000, req.target_faces)),
            texture_size=float(2048 if req.texture else 1024),
            api_name="/extract_glb",
        )
        glb = extracted[0] if isinstance(extracted, (list, tuple)) else extracted
        if isinstance(glb, dict):
            glb = glb.get("path") or glb.get("url")
        if not glb:
            raise RuntimeError("TRELLIS.2 Space returned no GLB")

        on("packaging", 0.95, "Writing GLB")
        mesh = adopt(glb, out_dir / "model.glb")
        return GenResult(mesh_path=mesh, thumb_path=adopt(src, out_dir / "thumb.png"),
                         provider="space", note="microsoft/TRELLIS.2 · /image_to_3d")

    # -- native pipeline ---------------------------------------------------
    def _generate_local(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        import imageio  # noqa: F401  (pulled in by trellis)
        from PIL import Image
        from trellis.pipelines import TrellisImageTo3DPipeline
        from trellis.utils import postprocessing_utils

        if self._pipe is None:
            on("preprocessing", 0.04, "Loading TRELLIS onto CUDA")
            self._pipe = TrellisImageTo3DPipeline.from_pretrained(str(WEIGHTS / "trellis-image-large"))
            self._pipe.cuda()

        ss_steps, slat_steps, _ = EFFORT.get(req.effort, EFFORT["high"])
        src = prep_image(req.images[0], out_dir / "input")

        on("sparse-structure", 0.2, f"Sparse structure · {ss_steps} steps")
        outputs = self._pipe.run(
            Image.open(src),
            seed=req.seed if req.seed is not None else 0,
            sparse_structure_sampler_params={"steps": ss_steps, "cfg_strength": req.guidance},
            slat_sampler_params={"steps": slat_steps, "cfg_strength": 3.0},
        )

        on("mesh", 0.75, "Extracting mesh from SLAT")
        glb = postprocessing_utils.to_glb(
            outputs["gaussian"][0], outputs["mesh"][0],
            simplify=0.95, texture_size=2048 if req.texture else 1024,
        )
        mesh = out_dir / "model.glb"
        glb.export(str(mesh))

        splat = out_dir / "splat.ply"
        try:
            outputs["gaussian"][0].save_ply(str(splat))
        except Exception:
            splat = None

        return GenResult(mesh_path=mesh, splat_path=splat,
                         thumb_path=adopt(src, out_dir / "thumb.png"),
                         provider="local", note="native · cuda")
