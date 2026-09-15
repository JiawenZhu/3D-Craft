"""Cached transparent DISPLAY thumbnails; originals and reconstruction refs are immutable.

Local macOS uses built-in Vision. Other platforms return the original thumbnail
until a semantic segmentation provider is installed; never use a brightness key.
"""
from __future__ import annotations
import hashlib
import os
import platform
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import unquote, urlsplit
from PIL import Image
from .config import EXPORTS, ROOT, STORAGE

CACHE = EXPORTS / "display-thumbnails-v1"
HELPER = ROOT / "helpers" / "thumbnail_foreground.swift"
_lock = threading.Lock()
MAX_SOURCE_BYTES = 20 * 1024 * 1024


def source_path(asset: dict) -> Path | None:
    """Only the registry's own local asset thumbnail is eligible, never a URL fetch."""
    ident = str(asset.get("id", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", ident):
        return None
    raw = asset.get("thumbUrl")
    if not isinstance(raw, str):
        return None
    parsed = urlsplit(raw)
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
        return None
    prefix = f"/files/{ident}/"
    decoded = unquote(parsed.path)
    if not decoded.startswith(prefix):
        return None
    root = (STORAGE / ident).resolve()
    # Reject asset folder symlinks escaping storage as well as filename traversal.
    if not root.is_relative_to(STORAGE.resolve()):
        return None
    source = (root / decoded.removeprefix(prefix)).resolve()
    if not source.is_relative_to(root) or not source.is_file():
        return None
    return source


def decorate(asset: dict) -> dict:
    source = source_path(asset)
    if source is None or asset.get("visibility", "public") != "public":
        return dict(asset)
    # Metadata lookup is cheap; inference only runs when the image is requested.
    return {**asset, "thumbDisplayUrl": f"/api/assets/{asset['id']}/thumbnail-display?v={source.stat().st_mtime_ns}"}


def _transparent_png(path: Path) -> bool:
    try:
        with Image.open(path) as im:
            im.load()
            return im.format == "PNG" and "A" in im.getbands() and im.getchannel("A").getextrema()[0] < 240 and im.getchannel("A").getextrema()[1] > 0
    except (OSError, ValueError):
        return False


def _segment(source: Path, output: Path) -> bool:
    if platform.system() != "Darwin" or not shutil.which("swiftc"):
        return False
    helper_hash = hashlib.sha256(HELPER.read_bytes()).hexdigest()[:16]
    binary = CACHE / ("foreground-" + helper_hash)
    if not binary.is_file():
        partial = binary.with_suffix(".building")
        try:
            built = subprocess.run(["swiftc", "-O", str(HELPER), "-o", str(partial)],
                                   capture_output=True, timeout=90, check=False)
            if built.returncode != 0:
                return False
            os.replace(partial, binary)
        finally:
            partial.unlink(missing_ok=True)
    result = subprocess.run([str(binary), str(source), str(output)], capture_output=True, timeout=45, check=False)
    return result.returncode == 0


def display_path(asset: dict) -> tuple[Path, bool]:
    source = source_path(asset)
    if source is None:
        raise FileNotFoundError("No local thumbnail for this asset")
    if source.stat().st_size > MAX_SOURCE_BYTES:
        return source, False
    digest = hashlib.sha256(source.read_bytes() + HELPER.read_bytes()).hexdigest()
    destination = CACHE / (digest + ".png")
    with _lock:
        if destination.is_file() and _transparent_png(destination):
            return destination, True
        CACHE.mkdir(parents=True, exist_ok=True)
        failed = CACHE / (digest + ".failed")
        if failed.exists() and time.time() - failed.stat().st_mtime < 300:
            return source, False
        partial = CACHE / (digest + ".partial.png")
        try:
            if _segment(source, partial) and _transparent_png(partial):
                os.replace(partial, destination)
                failed.unlink(missing_ok=True)
                return destination, True
        except (OSError, subprocess.SubprocessError):
            pass
        finally:
            partial.unlink(missing_ok=True)
        # Short negative cache avoids repeatedly invoking unsupported inference.
        failed.touch()
        return source, False
