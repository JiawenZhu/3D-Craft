"""
3D Craft — local inference API.

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

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, Request
from fastapi.responses import JSONResponse
import os
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse

from . import pricing, engines, gemini, jobs, pipelines, thumbnails
from .mobile import router as mobile_router
from .mobile_ai import router as mobile_ai_router
from .gallery import router as gallery_router
from .community import router as community_router
from .config import EXPORTS, HOST, INBOX, PORT, PROVIDER, ROOT, RUNS, STORAGE
from .engines.base import GenRequest

app = FastAPI(title="3D Craft API", version="2.1.0")
from .billing import router as billing_router
app.include_router(billing_router)
from .revenuecat_billing import router as revenuecat_billing_router
app.include_router(revenuecat_billing_router)
from .showcase import router as showcase_router
app.include_router(showcase_router)
from .cloud_library import router as cloud_library_router
app.include_router(cloud_library_router)
app.include_router(mobile_router)
app.include_router(mobile_ai_router)
app.include_router(gallery_router)
app.include_router(community_router)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"],
)


@app.middleware("http")
async def protect_legacy_workspace(request: Request, call_next):
    """Old global web endpoints cannot bypass the owner-scoped commercial API."""
    path = request.url.path
    legacy = (path.startswith(("/api/generate", "/api/jobs", "/api/pipelines", "/api/concept-set", "/api/assets", "/api/inbox", "/runs/", "/files/", "/inbox/")))
    from .config import IS_PRODUCTION
    local_review = (not IS_PRODUCTION and os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") == "1"
                    and request.client and request.client.host in ("127.0.0.1", "::1", "testclient"))
    if legacy and request.method != "OPTIONS" and not local_review:
        from .identity import require_account, require_paid
        try:
            owner = require_account(request.headers.get("authorization", ""))
            require_paid(owner)
            # Legacy storage and pipelines are global, without owner binding or
            # trusted settlement. Fail closed instead of exposing other accounts.
            raise HTTPException(503, "The paid workspace is being connected. No credits have been charged.")
        except HTTPException as error:
            return JSONResponse({"detail": error.detail}, status_code=error.status_code)
    return await call_next(request)


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


@app.get("/api/pricing")
def provider_pricing():
    return pricing.catalog()


@app.get("/api/health")
def health() -> dict:
    device, torch_version = _device()
    gem_ok, gem_note = gemini.available()
    return {
        "status": "ok",
        "device": device,
        "torch": torch_version,
        "provider": PROVIDER,
        "engines": engines.status_all(),
        # The concept stage is optional: without a key the studio still runs
        # image -> 3D directly, so the UI needs to know which it can offer.
        "gemini": {"available": gem_ok, "note": gem_note},
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

    engine_id = cfg.get("engine", "rodin")
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


# ---------------------------------------------------------------- pipelines
@app.post("/api/pipelines")
async def start_pipeline(
    prompt: str = Form(""),
    settings: str = Form("{}"),
    image: UploadFile | None = File(default=None),
    sourceRef: str = Form(""),
) -> dict:
    """
    photo + words -> written prompt -> concept render -> mesh.

    The upload is copied into the run folder rather than referenced from the
    temp dir, because a run outlives the request that created it and the node
    graph still has to show the source image tomorrow.
    """
    ok, why = gemini.available()
    if not ok:
        raise HTTPException(503, f"the concept stage is unavailable: {why}")

    try:
        cfg = json.loads(settings)
    except json.JSONDecodeError as exc:
        raise HTTPException(400, f"bad settings payload: {exc}") from exc

    engine_id = cfg.get("engine", "rodin")
    if engine_id not in engines.ENGINES:
        raise HTTPException(400, f"unknown engine {engine_id!r}")

    saved: Path | None = None
    scratch: Path | None = None
    if image is not None and image.filename:
        scratch = Path(tempfile.mkdtemp(prefix="rodin-pipe-"))
        saved = scratch / Path(image.filename).name
        with saved.open("wb") as fh:
            shutil.copyfileobj(image.file, fh)

    if saved is None and not prompt.strip():
        raise HTTPException(400, "give it an image, a prompt, or both")

    try:
        run_id = pipelines.create(
            user_prompt=prompt,
            settings=cfg,
            source=saved,
            source_ref=sourceRef or None,
        )
    finally:
        if scratch:
            shutil.rmtree(scratch, ignore_errors=True)
    return {"run_id": run_id}


@app.get("/api/pipelines")
def list_pipelines() -> list[dict]:
    return pipelines.list_runs()


@app.get("/api/pipelines/{run_id}")
def get_pipeline(run_id: str) -> dict:
    doc = pipelines.read(run_id)
    if not doc:
        raise HTTPException(404, "no such run")
    return doc


@app.post("/api/pipelines/{run_id}/retry")
def retry_pipeline(run_id: str, stage: str = Form(...), prompt: str | None = Form(None)) -> dict:
    """
    Re-run from one stage onward.

    Restarting from the top would re-charge the concept render to fix a mesh,
    so each stage is separately retryable and everything upstream is kept.

    `prompt` is the user's own words when `stage` is "prompt", and the written
    prompt itself when `stage` is "concept" — see pipelines.retry.
    """
    if not pipelines.read(run_id):
        raise HTTPException(404, "no such run")
    if not pipelines.retry(run_id, stage, prompt):
        raise HTTPException(409, "that run is still going, or the stage is not retryable")
    return {"ok": True}


@app.post("/api/concept-set")
def create_concept_set(
    image: UploadFile | None = File(None),
    image_url: str | None = Form(None),
    prompt: str = Form(""),
    count: int = Form(4),
) -> dict:
    """
    Generate candidate concept variations from an uploaded photo or image reference
    before 3D reconstruction.
    """
    scratch: Path | None = None
    source_path: Path | None = None

    if image is not None and image.filename:
        scratch = Path(tempfile.mkdtemp(prefix="rodin-cset-"))
        source_path = scratch / Path(image.filename).name
        with source_path.open("wb") as fh:
            shutil.copyfileobj(image.file, fh)
    elif image_url:
        clean_url = image_url.split("?")[0]
        if clean_url.startswith("/runs/"):
            rel = clean_url.removeprefix("/runs/")
            cand = RUNS / rel
            if cand.is_file():
                source_path = cand
        elif clean_url.startswith("/files/"):
            rel = clean_url.removeprefix("/files/")
            cand = STORAGE / rel
            if cand.is_file():
                source_path = cand
        elif clean_url.startswith("/images/"):
            rel = clean_url.removeprefix("/images/")
            cand = ROOT.parent / "public" / "images" / rel
            if cand.is_file():
                source_path = cand

    if source_path is None and not prompt.strip():
        raise HTTPException(400, "Provide an image or a prompt to generate concept images.")

    try:
        set_id = f"cset-{uuid.uuid4().hex[:10]}"
        set_dir = RUNS / set_id
        set_dir.mkdir(parents=True, exist_ok=True)

        cset = gemini.make_concept_set(prompt, source_path, count=count)
        rendered_images = []
        if source_path and source_path.is_file():
            saved_source = set_dir / f"source{source_path.suffix.lower() or '.png'}"
            shutil.copyfile(source_path, saved_source)
            rendered_images.append({
                "id": f"{set_id}-orig",
                "url": f"/runs/{set_id}/{saved_source.name}",
                "label": "Original (Direct 3D)",
                "isOriginal": True,
            })

        for i, item in enumerate(cset["images"]):
            ext = ".png" if "png" in item["mime"] else ".jpg"
            filename = f"concept_{i}{ext}"
            file_dest = set_dir / filename
            file_dest.write_bytes(item["bytes"])
            rendered_images.append({
                "id": f"{set_id}-{i}",
                "url": f"/runs/{set_id}/{filename}",
                "label": item["label"],
                "direction": item.get("direction"),
                "isOriginal": False,
            })

        return {
            "id": set_id,
            "title": cset["title"],
            "subject": cset["subject"],
            "core_concept": cset.get("core_concept", ""),
            "image_assessment": cset.get("image_assessment", ""),
            "prompt": cset["prompt"],
            "notes": cset["notes"],
            "images": rendered_images,
            "warnings": cset.get("warnings", []),
            "validation": cset.get("validation"),
            "total_ms": cset["total_ms"],
        }
    finally:
        if scratch:
            shutil.rmtree(scratch, ignore_errors=True)


@app.post("/api/pipelines/{run_id}/select-concept")
def select_pipeline_concept(run_id: str, image_url: str = Form(...)) -> dict:
    if not pipelines.select_concept(run_id, image_url):
        raise HTTPException(404, "no such run")
    return {"ok": True}


@app.post("/api/pipelines/{run_id}/direct-recon")
def direct_pipeline_recon(run_id: str) -> dict:
    if not pipelines.direct_recon(run_id):
        raise HTTPException(404, "no such run or no source image")
    return {"ok": True}


@app.delete("/api/pipelines/{run_id}")
def delete_pipeline(run_id: str) -> dict:
    pipelines.delete(run_id)
    return {"ok": True}


@app.get("/runs/{run_id}/{name:path}")
def run_file(run_id: str, name: str) -> FileResponse:
    root = (RUNS / run_id).resolve()
    target = (root / name).resolve()
    if not str(target).startswith(str(RUNS.resolve())) or not target.is_file():
        raise HTTPException(404, "not found")
    return FileResponse(target)


@app.get("/api/assets")
def assets() -> list[dict]:
    return jobs.list_assets()


@app.get("/api/assets/{asset_id}/thumbnail-display")
def thumbnail_display(asset_id: str) -> FileResponse:
    # Same public example registry as /api/assets; no arbitrary filesystem or
    # network reference is accepted from a query parameter.
    asset = next((item for item in jobs.list_assets() if item["id"] == asset_id and item.get("visibility", "public") == "public"), None)
    if asset is None:
        raise HTTPException(404, "Asset not found")
    try:
        path, transparent = thumbnails.display_path(asset)
    except FileNotFoundError:
        raise HTTPException(404, "Thumbnail not found") from None
    return FileResponse(path, media_type="image/png" if transparent else None,
                        headers={"Cache-Control": "private, max-age=86400" if transparent else "no-cache",
                                 "X-Craft-Thumbnail": "transparent-display" if transparent else "original-fallback"})


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
