"""
Hybrid pipeline: TRELLIS.2 for structure, Hunyuan3D-2.1 for PBR texture.

Both stages run through whichever provider each engine resolved to, so this
works with the hosted Spaces as well as with native pipelines.
"""
from __future__ import annotations

from pathlib import Path

from .base import GenRequest, GenResult, Progress


class HybridEngine:
    id = "hybrid"
    label = "Hybrid"

    def __init__(self, trellis, hunyuan) -> None:
        self._trellis = trellis
        self._hunyuan = hunyuan

    def status(self) -> dict:
        t, h = self._trellis.status(), self._hunyuan.status()
        # the hybrid runs both stages back to back, so its cost is their sum
        merged = {k: t["effortSeconds"][k] + h["effortSeconds"].get(k, 0) for k in t["effortSeconds"]}
        return {
            "installed": t["installed"] and h["installed"],
            "loaded": t["loaded"] and h["loaded"],
            "note": f"TRELLIS ({t['provider']}) → Hunyuan ({h['provider']})",
            "provider": f"{t['provider']}+{h['provider']}",
            "effortSeconds": merged,
            "pricePerGen": t.get("pricePerGen", 0.0) + h.get("pricePerGen", 0.0),
        }

    def generate(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        def geo_progress(stage: str, p: float, msg: str) -> None:
            on(stage, p * 0.55, f"TRELLIS · {msg}")

        geo = self._trellis.generate(req, out_dir / "geometry", geo_progress)

        if not req.texture:
            return GenResult(mesh_path=geo.mesh_path, splat_path=geo.splat_path,
                             thumb_path=geo.thumb_path, provider=geo.provider,
                             note="TRELLIS geometry only (texturing off)")

        def tex_progress(stage: str, p: float, msg: str) -> None:
            on("texture", 0.55 + p * 0.42, f"Hunyuan Paint · {msg}")

        try:
            tex = self._hunyuan.generate(req, out_dir / "texture", tex_progress)
        except Exception as exc:  # keep the geometry rather than losing the run
            return GenResult(mesh_path=geo.mesh_path, splat_path=geo.splat_path,
                             thumb_path=geo.thumb_path, provider=geo.provider,
                             note=f"TRELLIS geometry kept; paint stage failed: {exc}")

        return GenResult(mesh_path=tex.mesh_path, splat_path=geo.splat_path,
                         thumb_path=geo.thumb_path or tex.thumb_path,
                         provider=f"{geo.provider}+{tex.provider}",
                         note="TRELLIS structure → Hunyuan3D PBR")
