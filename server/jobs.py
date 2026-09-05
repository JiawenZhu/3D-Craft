"""In-memory job queue plus the on-disk asset index."""
from __future__ import annotations

import json
import threading
import time
import traceback
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import asdict, dataclass, field
from pathlib import Path

from . import engines
from .config import EXPORTS, STORAGE
from .engines.base import GenRequest
from .engines.common import mesh_stats

INDEX = STORAGE / "assets.json"
_lock = threading.Lock()
# one worker: these pipelines are not safe to run concurrently on one GPU
_pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="rodin-gen")

TINTS = ["#d18b2f", "#8771ff", "#5aa6c0", "#c4553a", "#6f9a63", "#caa14e", "#b98d5f"]
SHAPES = ["figure", "mech", "creature", "prop", "vehicle"]


@dataclass
class Job:
    id: str
    engine: str
    prompt: str
    stage: str = "queued"
    progress: float = 0.0
    message: str = "Queued"
    startedAt: int = field(default_factory=lambda: int(time.time() * 1000))
    finishedAt: int | None = None
    error: str | None = None
    assetIds: list[str] = field(default_factory=list)


_jobs: dict[str, Job] = {}


# --------------------------------------------------------------- asset index
def _load_index() -> list[dict]:
    if not INDEX.exists():
        return []
    try:
        return json.loads(INDEX.read_text())
    except Exception:
        return []


def _save_index(items: list[dict]) -> None:
    INDEX.parent.mkdir(parents=True, exist_ok=True)
    INDEX.write_text(json.dumps(items, indent=1))


def list_assets() -> list[dict]:
    with _lock:
        return _load_index()


def delete_asset(asset_id: str) -> None:
    with _lock:
        items = [a for a in _load_index() if a["id"] != asset_id]
        _save_index(items)
    import shutil

    for folder in (STORAGE / asset_id, EXPORTS / asset_id):
        if folder.exists():
            shutil.rmtree(folder, ignore_errors=True)


def annotate_asset(asset_id: str, fields: dict) -> None:
    """
    Add to an asset after the fact.

    The pipeline is the only caller: it learns the run id it produced the mesh
    under only once jobs.py has already written the record, and an asset that
    cannot name its run cannot be re-prompted through the concept stage.
    """
    with _lock:
        items = _load_index()
        for item in items:
            if item["id"] == asset_id:
                item.update(fields)
                _save_index(items)
                return


def _record(asset: dict) -> None:
    with _lock:
        items = _load_index()
        items.insert(0, asset)
        _save_index(items[:500])


# --------------------------------------------------------------------- jobs
def get_job(job_id: str) -> dict | None:
    job = _jobs.get(job_id)
    if not job:
        return None
    payload = asdict(job)
    index = {a["id"]: a for a in list_assets()}
    payload["assets"] = [index[i] for i in job.assetIds if i in index]
    return payload


def submit(engine_id: str, req: GenRequest, name_hint: str) -> str:
    engine = engines.get(engine_id)  # raises early on a bad id
    job = Job(id=f"job-{uuid.uuid4().hex[:10]}", engine=engine_id, prompt=req.prompt)
    _jobs[job.id] = job
    _pool.submit(_run, job, engine, req, name_hint)
    return job.id


def _run(job: Job, engine, req: GenRequest, name_hint: str) -> None:
    def on(stage: str, p: float, message: str) -> None:
        job.stage = stage
        job.progress = round(min(99.0, max(0.0, p * 100)), 1)
        job.message = message

    try:
        made: list[str] = []
        for i in range(max(1, req.batch)):
            asset_id = f"a-{uuid.uuid4().hex[:10]}"
            out_dir = STORAGE / asset_id
            out_dir.mkdir(parents=True, exist_ok=True)

            span = 1.0 / max(1, req.batch)
            base = i * span

            def on_i(stage: str, p: float, message: str, _b=base, _s=span) -> None:
                suffix = f" ({i + 1}/{req.batch})" if req.batch > 1 else ""
                on(stage, _b + p * _s, message + suffix)

            per = GenRequest(**{**req.__dict__, "batch": 1,
                                "seed": None if req.seed is None else req.seed + i})
            result = engine.generate(per, out_dir, on_i)

            stats = mesh_stats(result.mesh_path)
            asset = {
                "id": asset_id,
                "name": (name_hint or "Untitled asset")[:48],
                "prompt": req.prompt or f"image → 3d ({engine.label})",
                "engine": engine.id,
                "createdAt": int(time.time() * 1000),
                "modelUrl": f"/files/{asset_id}/{result.mesh_path.name}",
                "splatUrl": f"/files/{asset_id}/{result.splat_path.name}" if result.splat_path else None,
                "thumbUrl": f"/files/{asset_id}/{result.thumb_path.name}" if result.thumb_path else None,
                "seedShape": SHAPES[i % len(SHAPES)],
                "tint": TINTS[(int(time.time()) + i) % len(TINTS)],
                "faces": stats["faces"],
                "vertices": stats["vertices"],
                "meshes": stats["meshes"],
                "materials": stats["materials"],
                "dimensions": stats["dimensions"],
                "textureRes": stats["textureRes"],
                "fileSizeMb": stats["fileSizeMb"],
                "liked": False,
                "likes": 0,
                "author": "you",
                "visibility": "public",
                "local": True,
                "provider": result.provider,
                "note": result.note,
                "sourceRef": req.source_ref,
            }
            _record(asset)
            made.append(asset_id)

        job.assetIds = made
        job.stage = "done"
        job.progress = 100.0
        job.message = "Complete"
        job.finishedAt = int(time.time() * 1000)
    except Exception as exc:
        job.stage = "failed"
        job.error = f"{type(exc).__name__}: {exc}"
        job.message = str(exc)[:220] or type(exc).__name__
        job.finishedAt = int(time.time() * 1000)
        traceback.print_exc()
