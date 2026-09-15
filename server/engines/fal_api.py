"""
fal.ai provider — serverless hosting for the same models we run locally.

Auth is the FAL_KEY environment variable, read by fal_client itself. The key
stays in this process: the browser never sees it, which is what fal's own docs
require ("use a server-side proxy").
"""
from __future__ import annotations

import os
from pathlib import Path

import httpx

from ..config import FAL_KEY
from .base import Progress


class FalError(RuntimeError):
    pass


def available() -> tuple[bool, str]:
    """Can we call fal at all? Cheap — no network."""
    if not FAL_KEY:
        return False, "FAL_KEY not set"
    try:
        import fal_client  # noqa: F401
    except ImportError:
        return False, "fal-client not installed — run ./scripts/setup.sh"
    return True, "fal.ai"


def upload(path: Path) -> str:
    """Put a local reference image on fal's CDN and return its URL."""
    import fal_client

    os.environ.setdefault("FAL_KEY", FAL_KEY or "")
    return fal_client.upload_file(str(path))


def run(endpoint: str, arguments: dict, on: Progress, stage: str, lo: float, hi: float) -> dict:
    """
    Call a fal endpoint and stream its queue status into our progress callback.

    `lo`/`hi` bound the slice of the overall job this call represents, so the
    ring keeps moving sensibly whether this is the only step or one of several.
    """
    import fal_client

    ok, why = available()
    if not ok:
        raise FalError(why)
    os.environ.setdefault("FAL_KEY", FAL_KEY or "")

    seen: list[str] = []

    def handle(update) -> None:
        name = type(update).__name__
        if name == "Queued":
            on(stage, lo, f"Queued at fal · position {getattr(update, 'position', '?')}")
        elif name == "InProgress":
            for log in getattr(update, "logs", None) or []:
                msg = (log.get("message") or "").strip() if isinstance(log, dict) else str(log)
                if msg and msg not in seen:
                    seen.append(msg)
            # fal does not report fractional progress, so ease toward `hi`
            frac = min(0.9, 0.15 * len(seen) or 0.3)
            on(stage, lo + (hi - lo) * frac, seen[-1][:70] if seen else "Running on fal")

    try:
        return fal_client.subscribe(endpoint, arguments, with_logs=True, on_queue_update=handle)
    except Exception as exc:
        raise FalError(f"{endpoint}: {type(exc).__name__}: {exc}") from exc


def pick_file(result: dict, *keys: str) -> str | None:
    """fal returns file objects as {url, content_type, file_name, file_size}."""
    for key in keys:
        node = result.get(key)
        if isinstance(node, dict) and node.get("url"):
            return node["url"]
        if isinstance(node, str) and node.startswith("http"):
            return node
        if isinstance(node, list) and node:
            first = node[0]
            if isinstance(first, dict) and first.get("url"):
                return first["url"]
    return None


def download(url: str, dest: Path) -> Path:
    """Copy a fal result into our own storage — their URLs are not permanent."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    with httpx.stream("GET", url, timeout=180) as r:
        r.raise_for_status()
        with dest.open("wb") as fh:
            for chunk in r.iter_bytes(1 << 16):
                fh.write(chunk)
    return dest
