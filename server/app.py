"""
Rodin 3D Studio — local inference API.

Fronts Tencent Hunyuan3D-2.1 and Microsoft TRELLIS.2. Each engine runs either
natively (when torch + the CUDA kernels are present) or against its official
Hugging Face Space; see server/engines/.
"""
from __future__ import annotations

import json
import shutil
import tempfile
import uuid
from pathlib import Path

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from . import engines, jobs
from .config import EXPORTS, HOST, INBOX, PORT, PROVIDER, ROOT, STORAGE
from .engines.base import GenRequest

app = FastAPI(title="Rodin 3D Studio API", version="2.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)


def _device() -> tuple[str, str]:
    try:
        import torch
    except ImportError:
        return "remote", "not installed"
    if torch.cuda.is_available():
        return f"cuda:{torch.cuda.get_device_name(0)}", torch.__version__
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps", torch.__version__
    return "cpu", torch.__version__


@app.get("/api/health")
def health() -> dict:
    device, torch_version = _device()
    return {
        "status": "ok",
        "device": device,
        "torch": torch_version,
        "provider": PROVIDER,
        "engines": engines.status_all(),
    }


@app.post("/api/generate")
async def generate(
    settings: str = Form(...),
    images: list[UploadFile] = File(default=[]),
    directions: list[str] = Form(default=[]),
) -> dict:
    try:
        cfg = json.loads(settings)
    except json.JSONDecodeError as exc:
        raise HTTPException(400, f"bad settings payload: {exc}") from exc

    engine_id = cfg.get("engine", "trellis-2")
    if engine_id not in engines.ENGINES:
        raise HTTPException(400, f"unknown engine {engine_id!r}")

    # Uploads land in a scratch dir the engines read from.
    scratch = Path(tempfile.mkdtemp(prefix="rodin-in-"))
    saved: list[Path] = []
    for upload in images:
        if not upload.filename:
            continue
        dest = scratch / f"{uuid.uuid4().hex[:8]}_{Path(upload.filename).name}"
        with dest.open("wb") as fh:
            shutil.copyfileobj(upload.file, fh)
        saved.append(dest)

    req = GenRequest(
        prompt=cfg.get("prompt", ""),
        negative_prompt=cfg.get("negativePrompt", ""),
        images=saved,
        directions=list(directions)[: len(saved)],
        seed=cfg.get("seed"),
        steps=int(cfg.get("steps", 50)),
        guidance=float(cfg.get("guidance", 7.5)),
        target_faces=int(cfg.get("targetFaces", 40_000)),
        texture=bool(cfg.get("texture", True)),
        quad_remesh=bool(cfg.get("quadRemesh", False)),
        remove_background=bool(cfg.get("removeBackground", True)),
        effort=cfg.get("effort", "high"),
        quality=cfg.get("quality", "default"),
        batch=int(cfg.get("batch", 1)),
        geo_mode=cfg.get("geoMode", "sharp"),
        pose_mode=cfg.get("poseMode", "none"),
        source_ref=cfg.get("sourceRef"),
    )

    name = (req.prompt.strip() or (saved[0].name.split("_", 1)[-1] if saved else "Untitled"))
    return {"job_id": jobs.submit(engine_id, req, name)}


@app.get("/api/jobs/{job_id}")
def job(job_id: str) -> dict:
    payload = jobs.get_job(job_id)
    if not payload:
        raise HTTPException(404, "no such job")
    return payload


IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".avif"}
# filename suffix -> the direction tag both engines understand
DIRECTION_HINTS = {
    "front": "front", "back": "back", "left": "left", "right": "right",
    "fl": "front-left", "fr": "front-right", "bl": "back-left", "br": "back-right",
    "up": "up", "top": "up", "down": "down", "bottom": "down",
}


@app.get("/api/inbox")
def inbox() -> list[dict]:
    """
    Reference images handed over by the image/animation side.

    A trailing `_front` / `_back` / … in the filename is read as a direction so
    multi-view sets arrive pre-tagged.
    """
    items: list[dict] = []
    for path in sorted(INBOX.rglob("*"), key=lambda p: -p.stat().st_mtime if p.is_file() else 0):
        if not path.is_file() or path.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        stem = path.stem.lower()
        direction = "unknown"
        for suffix, tag in DIRECTION_HINTS.items():
            if stem.endswith(f"_{suffix}") or stem.endswith(f"-{suffix}"):
                direction = tag
                break
        rel = path.relative_to(INBOX).as_posix()
        # When the folder lives under public/, prefer the path the dev server and
        # the built app serve directly: same-origin, no CORS, no API hop.
        try:
            public_rel = INBOX.resolve().relative_to((ROOT.parent / "public").resolve())
            public_url = f"/{public_rel.as_posix()}/{rel}"
        except ValueError:
            public_url = None
        items.append({
            "name": path.name,
            "url": public_url or f"/inbox/{rel}",
            "apiUrl": f"/inbox/{rel}",
            "direction": direction,
            "sizeKb": round(path.stat().st_size / 1024),
            "modifiedAt": int(path.stat().st_mtime * 1000),
        })
    return items


@app.get("/inbox/{name:path}")
def inbox_file(name: str) -> FileResponse:
    target = (INBOX / name).resolve()
    if not str(target).startswith(str(INBOX.resolve())) or not target.is_file():
        raise HTTPException(404, "not found")
    return FileResponse(target)


@app.get("/api/assets")
def assets() -> list[dict]:
    return jobs.list_assets()


# What we can genuinely produce from a GLB with trimesh. FBX and USDZ are
# deliberately absent: trimesh cannot write them, and handing over a renamed GLB
# is worse than not offering the format.
EXPORT_FORMATS = {
    "glb": ("model.glb", "model/gltf-binary"),
    # OBJ is not self-contained: trimesh writes material.mtl and the texture
    # beside it, so shipping the .obj alone gives you untextured geometry
    # pointing at files you do not have. Bundle the set instead.
    "obj": ("model-obj.zip", "application/zip"),
    "ply": ("model.ply", "application/octet-stream"),
    "stl": ("model.stl", "application/octet-stream"),
}


@app.get("/api/assets/{asset_id}/export")
def export_asset(asset_id: str, format: str = "glb") -> FileResponse:
    """Convert an asset on demand. Results are cached next to the source mesh."""
    fmt = format.lower().strip()
    if fmt not in EXPORT_FORMATS:
        raise HTTPException(400, f"unsupported format {fmt!r}; have {sorted(EXPORT_FORMATS)}")

    src = (STORAGE / asset_id / "model.glb").resolve()
    if not str(src).startswith(str(STORAGE.resolve())) or not src.is_file():
        raise HTTPException(404, "no mesh for that asset")

    filename, media_type = EXPORT_FORMATS[fmt]
    if fmt == "glb":
        return FileResponse(src, media_type=media_type, filename=filename)

    work = EXPORTS / asset_id
    work.mkdir(parents=True, exist_ok=True)
    out = work / f"model.{fmt}"
    if not out.exists() or out.stat().st_mtime < src.stat().st_mtime:
        import trimesh

        # force="mesh" flattens the scene graph; OBJ/PLY/STL have no notion of one
        mesh = trimesh.load(str(src), force="mesh")
        mesh.export(str(out))

    if fmt != "obj":
        return FileResponse(out, media_type=media_type, filename=filename)

    bundle = work / "model-obj.zip"
    if not bundle.exists() or bundle.stat().st_mtime < out.stat().st_mtime:
        import zipfile

        with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(out, "model.obj")
            # trimesh writes the material and texture beside the .obj
            for extra in sorted(work.glob("material*")):
                z.write(extra, extra.name)
    return FileResponse(bundle, media_type=media_type, filename=filename)


@app.delete("/api/assets/{asset_id}")
def remove(asset_id: str) -> dict:
    jobs.delete_asset(asset_id)
    return {"ok": True}


@app.get("/files/{asset_id}/{name:path}")
def files(asset_id: str, name: str) -> FileResponse:
    # keep traversal inside STORAGE
    root = (STORAGE / asset_id).resolve()
    target = (root / name).resolve()
    if not str(target).startswith(str(STORAGE.resolve())) or not target.is_file():
        raise HTTPException(404, "not found")
    return FileResponse(target)


def main() -> None:
    import uvicorn

    uvicorn.run("server.app:app", host=HOST, port=PORT, reload=False)


if __name__ == "__main__":
    main()
