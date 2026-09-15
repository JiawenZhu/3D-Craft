"""
Tencent Hunyuan3D-2.1
https://huggingface.co/spaces/tencent/Hunyuan3D-2.1

Two providers:
  space  — drives the official Space (`/generation_all`, `/shape_generation`).
           This is the path that works on any machine, including Apple Silicon.
  local  — the native pipeline from Tencent-Hunyuan/Hunyuan3D-2.1. The shape
           model is plain PyTorch; the PBR paint stage needs the CUDA-only
           custom rasterizer, so texturing is skipped when it is unavailable.
"""
from __future__ import annotations

import os
from dataclasses import replace
from pathlib import Path

from ..config import FAL_ENDPOINTS, FAL_PRICES, WEIGHTS
from . import fal_api
from . import vendor  # noqa: F401  (puts the vendored repo on sys.path)
from .base import GenRequest, GenResult, Progress
from .common import adopt, prep_image, resolve_provider, space_client

SHAPE_WEIGHTS = WEIGHTS / "hunyuan3d-2.1"

# Wall-clock estimates per effort tier, by where the work actually runs. The
# MPS numbers are measured on an M5 Pro: this DiT is ~3.3B params and Metal is
# roughly an order of magnitude off an A10G here.
ESTIMATES = {
    "cuda":  {"extreme-low": 8, "low": 14, "medium": 22, "high": 38, "extreme-high": 70},
    "mps":   {"extreme-low": 360, "low": 520, "medium": 760, "high": 1150, "extreme-high": 1900},
    "cpu":   {"extreme-low": 900, "low": 1400, "medium": 2100, "high": 3200, "extreme-high": 5200},
    "api":   {"extreme-low": 20, "low": 28, "medium": 40, "high": 60, "extreme-high": 95},
    "space": {"extreme-low": 60, "low": 80, "medium": 110, "high": 170, "extreme-high": 280},
}

# Effort tier -> (diffusion steps, octree resolution)
EFFORT = {
    "extreme-low": (12, 192),
    "low": (20, 256),
    "medium": (30, 256),
    "high": (40, 320),
    "extreme-high": (60, 384),
}

# The Space takes up to four canonical views by name.
VIEW_SLOTS = ["front", "back", "left", "right"]
DIRECTION_TO_SLOT = {
    "front": "front", "front-left": "left", "front-right": "right",
    "left": "left", "right": "right",
    "back": "back", "back-left": "back", "back-right": "back",
}


def _device() -> str:
    try:
        import torch
    except ImportError:
        return "cpu"
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


class HunyuanEngine:
    id = "hunyuan3d-2.1"
    label = "Hunyuan3D-2.1"

    def __init__(self) -> None:
        self._pipe = None

    # ------------------------------------------------------------------ status
    def _local_available(self) -> tuple[bool, str]:
        try:
            import torch
        except ImportError:
            return False, "torch not installed — run ./scripts/setup.sh --local"
        if not (SHAPE_WEIGHTS / "hunyuan3d-dit-v2-1").exists():
            return False, "weights missing — run ./scripts/setup.sh --weights"
        try:
            from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline  # noqa: F401
        except ImportError as exc:
            return False, f"hy3dshape not importable ({exc}); clone Hunyuan3D-2.1 into server/vendor"
        dev = ("cuda" if torch.cuda.is_available()
               else "mps" if torch.backends.mps.is_available() else "cpu")
        return True, f"native shape pipeline on {dev}"

    def status(self) -> dict:
        ok, note = self._local_available()
        provider = resolve_provider(self.id, ok)
        if provider == "space":
            note = "using the hosted Hugging Face Space" + ("" if ok else f" ({note})")
        price = 0.0
        if provider == "api":
            price = FAL_PRICES["hunyuan3d-2.1"]
            note = f"fal.ai · {FAL_ENDPOINTS['hunyuan3d-2.1']} · ${price:.2f}/gen (${FAL_PRICES['hunyuan3d-2.1-textured']:.2f} textured)"
        key = provider if provider in ("api", "space") else _device()
        return {
            "installed": provider == "api" or ok or provider == "space",
            "loaded": self._pipe is not None,
            "note": note,
            "provider": provider,
            "effortSeconds": ESTIMATES.get(key, ESTIMATES["cpu"]),
            "pricePerGen": price,
        }

    # ---------------------------------------------------------------- generate
    def generate(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        ok, _ = self._local_available()
        provider = resolve_provider(self.id, ok)
        if provider == "api":
            return self._generate_fal(req, out_dir, on)
        if provider == "local":
            return self._generate_local(req, out_dir, on)
        return self._generate_space(req, out_dir, on)

    # -- fal.ai ------------------------------------------------------------
    def _generate_fal(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        if not req.images:
            raise RuntimeError("Hunyuan3D-2.1 is image-conditioned — add a reference image.")

        # fal's v2 MV contract requires front/back/left, with no right slot.
        # Never fill missing slots with unrelated images or relabel diagonals.
        selected = {"front": req.images[0]}
        if len(req.images) > 1:
            if len(req.directions) != len(req.images):
                raise ValueError("Multi-view requires a direction for every image.")
            selected = {}
            for path, direction in zip(req.images, req.directions):
                if direction not in ("front", "back", "left") or direction in selected:
                    raise ValueError("Hunyuan fal multi-view needs exactly front, back and left views, each once.")
                selected[direction] = path
            if set(selected) != {"front", "back", "left"}:
                raise ValueError("Hunyuan fal multi-view needs front, back and left views. Select one image for single-view.")
        on("preprocessing", 0.05, "Uploading reference to fal")
        uploads = {direction: fal_api.upload(prep_image(p, out_dir / "input" / direction))
                   for direction, p in selected.items()}

        steps, octree = EFFORT.get(req.effort, EFFORT["high"])
        if req.quality == "speedy":
            steps = max(8, int(steps * 0.6))

        shared = {
            "seed": req.seed if req.seed is not None else 0,
            "num_inference_steps": int(steps),
            "guidance_scale": float(req.guidance),
            "octree_resolution": int(octree),
            "textured_mesh": bool(req.texture),
        }

        # The multi-view endpoint wants named views and needs at least three.
        if len(uploads) > 1:
            endpoint = FAL_ENDPOINTS["hunyuan3d-2.1-mv"]
            slots = {f"{direction}_image_url": url for direction, url in uploads.items()}
            args = {**shared, **slots}
        else:
            endpoint = FAL_ENDPOINTS["hunyuan3d-2.1"]
            args = {**shared, "input_image_url": uploads["front"]}

        result = fal_api.run(endpoint, args, on, "latent", 0.12, 0.9)

        url = fal_api.pick_file(result, "model_glb_pbr", "model_glb", "model_mesh")
        if not url:
            raise RuntimeError(f"fal returned no mesh (keys: {sorted(result)})")

        on("packaging", 0.94, "Downloading GLB")
        mesh = fal_api.download(url, out_dir / "model.glb")
        price = (.051 if req.texture else .017) if len(uploads) > 1 else FAL_PRICES["hunyuan3d-2.1-textured" if req.texture else "hunyuan3d-2.1"]
        return GenResult(
            mesh_path=mesh, thumb_path=adopt(Path(prep_image(req.images[0], out_dir / "input")), out_dir / "thumb.png"),
            provider="api", note=f"fal.ai · {endpoint} · ${price:g}",
        )

    # -- hosted Space ------------------------------------------------------
    def _generate_space(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        from gradio_client import handle_file

        on("preprocessing", 0.05, "Connecting to the Hunyuan3D-2.1 Space")
        client = space_client(self.id)
        if client is None:
            raise RuntimeError("gradio_client unavailable; run ./scripts/setup.sh")

        if not req.images:
            raise RuntimeError(
                "Hunyuan3D-2.1 is image-conditioned. Drop a reference image, or "
                "generate one first with a text-to-image model."
            )

        # Map each reference onto the Space's four named view slots.
        views: dict[str, str | None] = {v: None for v in VIEW_SLOTS}
        primary = str(prep_image(req.images[0], out_dir / "input"))
        if len(req.images) > 1:  # only engage the multi-view slots for a real set
            for img, direction in zip(req.images, req.directions or []):
                slot = DIRECTION_TO_SLOT.get(direction)
                if slot and views[slot] is None:
                    views[slot] = str(prep_image(img, out_dir / "input"))
        # The Space always wants the primary in `image`; the four named slots are
        # additive. Passing only mv_* trips its "provide a caption or an image".

        steps, octree = EFFORT.get(req.effort, EFFORT["high"])
        if req.quality == "speedy":
            steps = max(8, int(steps * 0.6))

        # NOTE: the Space's /shape_generation endpoint currently raises TypeError
        # for every input, so /generation_all is the only usable entry point.
        endpoint = "/generation_all"
        on("latent", 0.15, f"Hunyuan3D-DiT · {steps} steps @ octree {octree}")

        # gradio 4.x wants filepath params wrapped, and None for empty slots
        def f(path: str | None):
            return handle_file(path) if path else None

        result = client.predict(
            image=f(primary),
            mv_image_front=f(views["front"]),
            mv_image_back=f(views["back"]),
            mv_image_left=f(views["left"]),
            mv_image_right=f(views["right"]),
            steps=float(steps),
            guidance_scale=float(req.guidance),
            seed=float(req.seed if req.seed is not None else 1234),
            octree_resolution=float(octree),
            check_box_rembg=bool(req.remove_background),
            num_chunks=8000.0,
            randomize_seed=req.seed is None,
            api_name=endpoint,
        )

        # /generation_all -> (white mesh, textured mesh, html, stats, seed)
        # /shape_generation -> (mesh, html, stats, seed)
        files = [r for r in result if isinstance(r, str) and r.lower().endswith((".glb", ".obj", ".ply"))]
        if not files:
            raise RuntimeError(f"Space returned no mesh (got {[type(r).__name__ for r in result]})")
        on("texture", 0.85, "Downloading result")
        chosen = files[-1] if req.texture else files[0]  # honor the shape-only selection
        mesh = adopt(chosen, out_dir / f"model{Path(chosen).suffix or '.glb'}")
        thumb = adopt(primary, out_dir / "thumb.png")
        on("packaging", 0.97, "Writing GLB")
        return GenResult(mesh_path=mesh, thumb_path=thumb, provider="space",
                         note=f"tencent/Hunyuan3D-2.1 · {endpoint}")

    # -- native pipeline ---------------------------------------------------
    def _generate_local(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        import torch
        from PIL import Image
        from hy3dshape.pipelines import Hunyuan3DDiTFlowMatchingPipeline

        if torch.cuda.is_available():
            device, dtype = "cuda", torch.float16
        elif torch.backends.mps.is_available():
            # ~3.3B params: fp32 needs ~14 GB of weights alone and can push a Mac
            # into a hard kill. fp16 halves it and is the dtype upstream ships.
            # Override with RODIN_MPS_DTYPE=float32 if you hit NaNs.
            device = "mps"
            dtype = torch.float32 if os.getenv("RODIN_MPS_DTYPE") == "float32" else torch.float16
        else:
            device, dtype = "cpu", torch.float32

        if self._pipe is None:
            on("preprocessing", 0.04, f"Loading Hunyuan3D-DiT onto {device}")
            self._pipe = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained(
                str(SHAPE_WEIGHTS), subfolder="hunyuan3d-dit-v2-1",
                device=device, dtype=dtype, use_safetensors=False, variant="fp16",
            )

        steps, octree = EFFORT.get(req.effort, EFFORT["high"])
        if req.quality == "speedy":
            steps = max(8, int(steps * 0.6))

        image = prep_image(req.images[0], out_dir / "input")
        if req.remove_background:
            on("preprocessing", 0.08, "Removing background")
            try:
                from hy3dshape.rembg import BackgroundRemover

                Image.open(image).convert("RGBA").save(image)
                BackgroundRemover()(Image.open(image)).save(image)
            except Exception:
                pass  # the pipeline tolerates an un-matted input

        # `dmc` needs the CUDA-only diso kernel; `mc` is skimage and runs anywhere.
        try:
            import diso  # noqa: F401

            mc_algo = "dmc" if device == "cuda" else "mc"
        except ImportError:
            mc_algo = "mc"

        on("latent", 0.2, f"Shape diffusion · {steps} steps @ octree {octree}")
        generator = torch.Generator().manual_seed(req.seed) if req.seed is not None else None
        meshes = self._pipe(
            image=str(image),
            num_inference_steps=steps,
            guidance_scale=req.guidance,
            octree_resolution=octree,
            generator=generator,
            mc_algo=mc_algo,
            output_type="trimesh",
            enable_pbar=False,
        )
        mesh_out = meshes[0][0] if isinstance(meshes[0], list) else meshes[0]

        raw_faces = len(mesh_out.faces)
        on("mesh", 0.85, f"Extracting mesh ({mc_algo}) · {raw_faces:,} faces")

        decimated = None
        if req.target_faces and raw_faces > req.target_faces:
            try:
                # trimesh 5 routes this through fast_simplification; without that
                # package it raises rather than silently returning the full mesh.
                mesh_out = mesh_out.simplify_quadric_decimation(face_count=req.target_faces)
                decimated = len(mesh_out.faces)
                on("mesh", 0.9, f"Decimated {raw_faces:,} → {decimated:,} faces")
            except Exception as exc:
                on("mesh", 0.9, f"Decimation unavailable ({type(exc).__name__}) — keeping {raw_faces:,} faces")

        mesh = out_dir / "model.glb"
        mesh_out.export(str(mesh))

        note = f"native · {device}/{str(dtype).split('.')[-1]} · {mc_algo}"
        if decimated:
            note += f" · decimated {raw_faces:,}→{decimated:,}"
        if req.texture:
            note += " · geometry only (Hunyuan Paint needs the CUDA rasterizer)"
        return GenResult(mesh_path=mesh, thumb_path=adopt(image, out_dir / "thumb.png"),
                         provider="local", note=note)


class HunyuanWhiteEngine:
    """An explicit shape-only product; callers cannot accidentally enable paint."""
    id = "hunyuan3d-2-white"
    label = "Hunyuan 3D 2 · White mesh"

    def __init__(self, base):
        self._base = base

    def status(self):
        status = dict(self._base.status())
        status["note"] += " · White mesh (no texture)"
        return status

    def generate(self, req, out_dir, on):
        return self._base.generate(replace(req, texture=False), out_dir, on)
