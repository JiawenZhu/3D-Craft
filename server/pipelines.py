"""
The concept pipeline: photo + a few words -> written prompt -> concept render -> mesh.

A run is a DOCUMENT, not an in-memory promise. Every stage transition is written
to disk the moment it happens, so the node graph in the browser is the run's
actual progress rather than a guess between polls, and a refresh mid-run loses
nothing. That is also why this file looks like a database schema: the shape here
is the shape that moves to Firestore later, unchanged — see docs/FIREBASE.md.

    source ──► prompt ──► concept ──► model3d
    the photo  Gemini     Gemini      TRELLIS / Hunyuan / Rodin
    they gave  writes it  renders it  reconstructs it

Each node carries its own status, so a failure is attributed to the stage that
caused it instead of collapsing into "generation failed", and a retry can start
from that stage rather than from the top — the concept costs a few cents and the
mesh costs more, so re-running only what is wrong is worth the bookkeeping.
"""
from __future__ import annotations

import json
import shutil
import threading
import time
import traceback
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from . import gemini, jobs
from .config import RUNS
from .engines.base import GenRequest

INDEX = RUNS / "index.json"
_lock = threading.Lock()
# Gemini calls are network-bound and safe to overlap; the 3D stage still funnels
# through jobs.py's single worker, which is the one that must not run concurrently.
_pool = ThreadPoolExecutor(max_workers=3, thread_name_prefix="rodin-pipe")

STAGES = ("source", "prompt", "concept", "model3d")
STAGE_LABEL = {
    "source": "Your image",
    "prompt": "Gemini writes the prompt",
    "concept": "Concept render",
    "model3d": "3D reconstruction",
}


def _now() -> int:
    return int(time.time() * 1000)


# ------------------------------------------------------------------ persistence
def _run_dir(run_id: str) -> Path:
    return RUNS / run_id


def _doc_path(run_id: str) -> Path:
    return _run_dir(run_id) / "run.json"


def read(run_id: str) -> dict | None:
    path = _doc_path(run_id)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def _write(doc: dict) -> None:
    doc["updatedAt"] = _now()
    path = _doc_path(doc["id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write-then-rename: a poll that lands mid-write would otherwise read a
    # truncated file and the whole board would flicker to "failed".
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(doc, indent=1))
    tmp.replace(path)
    _index_put(doc)


def _index_put(doc: dict) -> None:
    """A small denormalised list so the history strip is one read, not N."""
    with _lock:
        items = _load_index()
        row = {
            "id": doc["id"],
            "title": doc.get("title") or "Untitled run",
            "status": doc["status"],
            "createdAt": doc["createdAt"],
            "updatedAt": doc["updatedAt"],
            "conceptUrl": _node(doc, "concept").get("imageUrl"),
            "sourceUrl": _node(doc, "source").get("imageUrl"),
            "assetId": doc.get("assetId"),
        }
        items = [row] + [i for i in items if i["id"] != doc["id"]]
        INDEX.parent.mkdir(parents=True, exist_ok=True)
        INDEX.write_text(json.dumps(items[:200], indent=1))


def _load_index() -> list[dict]:
    if not INDEX.exists():
        return []
    try:
        return json.loads(INDEX.read_text())
    except Exception:
        return []


def list_runs() -> list[dict]:
    with _lock:
        return _load_index()


def delete(run_id: str) -> None:
    with _lock:
        items = [i for i in _load_index() if i["id"] != run_id]
        INDEX.write_text(json.dumps(items, indent=1))
    shutil.rmtree(_run_dir(run_id), ignore_errors=True)


# ------------------------------------------------------------------ node access
def _node(doc: dict, kind: str) -> dict:
    return next((n for n in doc["nodes"] if n["kind"] == kind), {})


def _set(doc: dict, kind: str, **fields) -> dict:
    node = _node(doc, kind)
    node.update(fields)
    if fields.get("status") == "running" and not node.get("startedAt"):
        node["startedAt"] = _now()
    if fields.get("status") in ("done", "failed"):
        node["finishedAt"] = _now()
    _write(doc)
    return node


def _blank_node(kind: str) -> dict:
    return {
        "id": f"n-{kind}",
        "kind": kind,
        "label": STAGE_LABEL[kind],
        "status": "pending",
        "startedAt": None,
        "finishedAt": None,
        "error": None,
    }


# ------------------------------------------------------------------------ create
def create(
    *,
    user_prompt: str,
    settings: dict,
    source: Path | None,
    source_ref: str | None = None,
    owner: str = "local",
) -> str:
    """Lay the run down on disk, then hand it to a worker."""
    run_id = f"run-{uuid.uuid4().hex[:10]}"
    folder = _run_dir(run_id)
    folder.mkdir(parents=True, exist_ok=True)

    source_url = None
    if source and source.is_file():
        dest = folder / f"source{source.suffix.lower() or '.png'}"
        shutil.copyfile(source, dest)
        source_url = f"/runs/{run_id}/{dest.name}"

    doc = {
        "id": run_id,
        "ownerId": owner,
        "title": (user_prompt.strip()[:48] or "Untitled run"),
        "status": "running",
        "createdAt": _now(),
        "updatedAt": _now(),
        "input": {
            "prompt": user_prompt,
            "imageUrl": source_url,
            # Where the photo came from, when it was a gallery image rather than
            # an upload — the result can then be traced back to it.
            "sourceRef": source_ref,
        },
        "settings": {
            "engine": settings.get("engine", "trellis-2"),
            "effort": settings.get("effort", "high"),
            "quality": settings.get("quality", "default"),
            "targetFaces": int(settings.get("targetFaces", 40_000)),
            "texture": bool(settings.get("texture", True)),
            "quadRemesh": bool(settings.get("quadRemesh", False)),
            "removeBackground": bool(settings.get("removeBackground", True)),
            "seed": settings.get("seed"),
            "steps": int(settings.get("steps", 50)),
            "guidance": float(settings.get("guidance", 7.5)),
            "isPrivate": bool(settings.get("isPrivate", False)),
        },
        "nodes": [_blank_node(k) for k in STAGES],
        "assetId": None,
        "error": None,
    }
    _set(doc, "source", status="done", imageUrl=source_url, text=user_prompt or None)
    _pool.submit(_drive, run_id, "prompt")
    return run_id


def retry(run_id: str, from_stage: str, new_prompt: str | None = None) -> bool:
    """Re-run from one stage onward, leaving everything before it untouched."""
    doc = read(run_id)
    if not doc or from_stage not in ("prompt", "concept", "model3d"):
        return False
    if doc["status"] == "running":
        return False

    if new_prompt is not None:
        doc["input"]["prompt"] = new_prompt
        doc["title"] = new_prompt.strip()[:48] or doc["title"]
        _set(doc, "source", text=new_prompt or None)

    # Everything downstream of the retry point is now stale.
    for kind in STAGES[STAGES.index(from_stage):]:
        node = _node(doc, kind)
        node.update(_blank_node(kind))
    doc["status"] = "running"
    doc["error"] = None
    _write(doc)
    _pool.submit(_drive, run_id, from_stage)
    return True


# ------------------------------------------------------------------------ worker
def _drive(run_id: str, from_stage: str) -> None:
    doc = read(run_id)
    if not doc:
        return
    try:
        start = STAGES.index(from_stage)
        if start <= STAGES.index("prompt"):
            _stage_prompt(doc)
        if start <= STAGES.index("concept"):
            _stage_concept(doc)
        _stage_model(doc)

        doc["status"] = "done"
        doc["error"] = None
        _write(doc)
    except Exception as exc:
        message = f"{type(exc).__name__}: {exc}"
        doc = read(run_id) or doc
        doc["status"] = "failed"
        doc["error"] = message
        # Whichever node was still running is the one that broke.
        for node in doc["nodes"]:
            if node["status"] == "running":
                node["status"] = "failed"
                node["error"] = message
                node["finishedAt"] = _now()
        _write(doc)
        traceback.print_exc()


def _stage_prompt(doc: dict) -> None:
    _set(doc, "prompt", status="running")
    source = _local(doc, _node(doc, "source").get("imageUrl"))
    written = gemini.write_prompt(doc["input"]["prompt"], source)
    doc["title"] = written.get("title") or doc["title"]
    _set(
        doc, "prompt",
        status="done",
        text=written["prompt"],
        subject=written.get("subject"),
        notes=written.get("notes"),
        model=written.get("model"),
        ms=written.get("ms"),
    )


def _stage_concept(doc: dict) -> None:
    _set(doc, "concept", status="running")
    prompt = _node(doc, "prompt").get("text")
    if not prompt:
        raise RuntimeError("no prompt to render — re-run the prompt stage first")

    source = _local(doc, _node(doc, "source").get("imageUrl"))
    made = gemini.make_image(prompt, refs=[p for p in (source,) if p])

    ext = ".png" if "png" in made["mime"] else ".jpg"
    dest = _run_dir(doc["id"]) / f"concept{ext}"
    dest.write_bytes(made["bytes"])
    _set(
        doc, "concept",
        status="done",
        imageUrl=f"/runs/{doc['id']}/{dest.name}",
        model=made.get("model"),
        ms=made.get("ms"),
        sizeKb=round(len(made["bytes"]) / 1024),
    )


def _stage_model(doc: dict) -> None:
    """Hand the concept to the 3D engines through the existing job queue."""
    _set(doc, "model3d", status="running", message="Queued")
    concept = _local(doc, _node(doc, "concept").get("imageUrl"))
    if not concept:
        raise RuntimeError("no concept image to reconstruct")

    cfg = doc["settings"]
    req = GenRequest(
        prompt=_node(doc, "prompt").get("subject") or doc["input"]["prompt"],
        images=[concept],
        directions=["front"],
        seed=cfg.get("seed"),
        steps=int(cfg.get("steps", 50)),
        guidance=float(cfg.get("guidance", 7.5)),
        target_faces=int(cfg.get("targetFaces", 40_000)),
        texture=bool(cfg.get("texture", True)),
        quad_remesh=bool(cfg.get("quadRemesh", False)),
        remove_background=bool(cfg.get("removeBackground", True)),
        effort=cfg.get("effort", "high"),
        quality=cfg.get("quality", "default"),
        batch=1,
        # The mesh points back at the concept it came from, not at the user's
        # original photo — that is the image it actually reconstructs, and it is
        # what the workbench should re-prompt against.
        source_ref=_node(doc, "concept").get("imageUrl"),
    )

    job_id = jobs.submit(cfg.get("engine", "trellis-2"), req, doc["title"])
    _set(doc, "model3d", jobId=job_id)

    while True:
        time.sleep(1.0)
        payload = jobs.get_job(job_id)
        if not payload:
            raise RuntimeError("the 3D job disappeared from the queue")
        _set(
            doc, "model3d",
            status="running",
            progress=payload["progress"],
            message=payload["message"],
            stage=payload["stage"],
        )
        if payload["stage"] == "done":
            asset = (payload.get("assets") or [None])[0]
            doc["assetId"] = payload["assetIds"][0] if payload["assetIds"] else None
            # Point the asset back at this run, so re-prompting it from the
            # workbench can go through the concept stage instead of feeding the
            # same concept image to the reconstructor with different words.
            if doc["assetId"]:
                jobs.annotate_asset(doc["assetId"], {"runId": doc["id"]})
            _set(
                doc, "model3d",
                status="done",
                progress=100,
                message="Complete",
                assetId=doc["assetId"],
                modelUrl=(asset or {}).get("modelUrl"),
                thumbUrl=(asset or {}).get("thumbUrl"),
                faces=(asset or {}).get("faces"),
                provider=(asset or {}).get("provider"),
            )
            return
        if payload["stage"] == "failed":
            raise RuntimeError(payload.get("error") or payload.get("message") or "3D generation failed")


def _local(doc: dict, url: str | None) -> Path | None:
    """`/runs/<id>/<name>` back to the file it serves."""
    if not url:
        return None
    name = url.rsplit("/", 1)[-1]
    path = _run_dir(doc["id"]) / name
    return path if path.is_file() else None
