"""Shared helpers: image prep, mesh inspection, provider selection."""
from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

from ..config import HF_TOKEN, PROVIDER, SPACES


def prep_image(src: Path, dst_dir: Path, max_side: int = 1024) -> Path:
    """Normalise a reference image: RGBA-safe, sane size, PNG on disk."""
    dst_dir.mkdir(parents=True, exist_ok=True)
    img = Image.open(src)
    if img.mode not in ("RGB", "RGBA"):
        img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
    if max(img.size) > max_side:
        scale = max_side / max(img.size)
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    out = dst_dir / f"{src.stem}_prep.png"
    img.save(out)
    return out


def mesh_stats(path: Path) -> dict:
    """Face / vertex counts and file size for a produced mesh."""
    stats = {
        "faces": 0,
        "vertices": 0,
        "fileSizeMb": round(path.stat().st_size / 1_048_576, 2) if path.exists() else 0.0,
        "textureRes": 0,
        "meshes": 0,
        "materials": 0,
        "dimensions": [0.0, 0.0, 0.0],
    }
    try:
        import trimesh

        scene = trimesh.load(str(path), force="scene")
        faces = verts = tex = 0
        geoms = getattr(scene, "geometry", {})
        materials = set()
        for geom in geoms.values():
            faces += int(len(getattr(geom, "faces", [])))
            verts += int(len(getattr(geom, "vertices", [])))
            mat = getattr(getattr(geom, "visual", None), "material", None)
            if mat is not None:
                materials.add(id(mat))
            img = getattr(mat, "baseColorTexture", None) or getattr(mat, "image", None)
            if img is not None and getattr(img, "size", None):
                tex = max(tex, max(img.size))

        extents = getattr(scene, "extents", None)
        dims = [round(float(x), 4) for x in extents] if extents is not None else [0.0, 0.0, 0.0]
        stats.update(faces=faces, vertices=verts, textureRes=tex,
                     meshes=len(geoms), materials=len(materials), dimensions=dims)
    except Exception:
        pass
    return stats


def adopt(src: str | Path, dst: Path) -> Path:
    """Copy an engine output (often a temp file) into our storage directory."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(str(src), dst)
    return dst


def space_client(engine_id: str):
    """A gradio_client bound to the engine's hosted Space (None if unusable)."""
    try:
        from gradio_client import Client
    except ImportError:
        return None
    space = SPACES.get(engine_id)
    if not space:
        return None
    kwargs = {"hf_token": HF_TOKEN} if HF_TOKEN else {}
    return Client(space, **kwargs)


def resolve_provider(engine_id: str, local_ok: bool) -> str:
    """
    Honour RODIN_PROVIDER, falling back to whatever can actually run.

    `auto` prefers fal: it is what makes this usable as a product (seconds, not
    minutes). Native local is the free fallback, and the hosted Space is the
    last resort because its anonymous quota is too small to rely on.
    """
    from .fal_api import available as fal_available

    api_ok = fal_available()[0]
    if PROVIDER in ("api", "fal"):
        return "api"
    if PROVIDER == "local":
        return "local"
    if PROVIDER == "space":
        return "space"
    if api_ok:
        return "api"
    return "local" if local_ok else "space"
