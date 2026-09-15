"""
Hyper3D Rodin, via fal.

The commercial model this whole workspace is modelled on. There is no open
release, so it is API-only — but it sits on the same FAL_KEY as the other two,
which makes it a fair third lane in the A/B compare.
"""
from __future__ import annotations

from pathlib import Path

from ..config import FAL_ENDPOINTS, FAL_PRICES
from . import fal_api
from .base import GenRequest, GenResult, Progress
from .common import adopt, prep_image

# our effort tiers -> Rodin's own quality enum
QUALITY = {
    "extreme-low": "extra-low",
    "low": "low",
    "medium": "medium",
    "high": "high",
    "extreme-high": "high",
}

ESTIMATES = {"extreme-low": 15, "low": 25, "medium": 40, "high": 70, "extreme-high": 70}


class RodinEngine:
    id = "rodin"
    label = "Rodin (Ultra)"

    def status(self) -> dict:
        ok, why = fal_api.available()
        return {
            "installed": ok,
            "loaded": False,
            "note": (f"fal.ai · {FAL_ENDPOINTS['rodin']} · ${FAL_PRICES['rodin']:.2f}/gen"
                     if ok else f"needs a fal key ({why})"),
            "provider": "api" if ok else "unavailable",
            "effortSeconds": ESTIMATES,
            "pricePerGen": FAL_PRICES["rodin"],
        }

    def generate(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        ok, why = fal_api.available()
        if not ok:
            raise RuntimeError(f"Rodin is API-only and {why}. Set FAL_KEY and restart the server.")
        if not req.images and not req.prompt.strip():
            raise RuntimeError("Rodin needs an image or a prompt.")
        if len(req.images) > 5:
            raise ValueError("Rodin accepts at most five reference views. Remove extra images before generating.")

        urls: list[str] = []
        thumb_src: Path | None = None
        if req.images:
            on("preprocessing", 0.05, "Uploading references to fal")
            for p in req.images[:5]:
                prepped = prep_image(p, out_dir / "input")
                thumb_src = thumb_src or prepped
                urls.append(fal_api.upload(prepped))

        args = {
            "prompt": req.prompt or "",
            # These are views of ONE object; fuse invents a feature blend.
            "condition_mode": "concat",
            "seed": (req.seed or 0) % 65_536,
            "geometry_file_format": "glb",
            "material": "PBR" if req.texture else "Shaded",
            "quality": QUALITY.get(req.effort, "medium"),
            "use_hyper": req.geo_mode == "focal",
            "tier": "Sketch" if req.quality == "speedy" else "Regular",
            "TAPose": req.pose_mode in ("t-pose", "a-pose"),
        }
        if urls:
            args["input_image_urls"] = urls

        result = fal_api.run(FAL_ENDPOINTS["rodin"], args, on, "latent", 0.12, 0.9)

        url = fal_api.pick_file(result, "model_mesh", "model_meshes")
        if not url:
            raise RuntimeError(f"fal returned no mesh (keys: {sorted(result)})")

        on("packaging", 0.94, "Downloading GLB")
        mesh = fal_api.download(url, out_dir / "model.glb")
        return GenResult(
            mesh_path=mesh,
            thumb_path=adopt(thumb_src, out_dir / "thumb.png") if thumb_src else None,
            provider="api",
            note=f"fal.ai · {FAL_ENDPOINTS['rodin']} · ${FAL_PRICES['rodin']:.2f} · {args['quality']}",
        )
