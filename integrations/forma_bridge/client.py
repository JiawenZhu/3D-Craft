"""Shared CLI/MCP client. No automatic retries of billable submissions."""
from __future__ import annotations

import hashlib
import json
import mimetypes
import os
import re
import tempfile
import time
from contextlib import ExitStack
from pathlib import Path
from urllib.parse import urlsplit

import httpx

ENGINES = ("trellis-2", "hunyuan3d-2.1", "rodin")
FORMATS = {"glb": ".glb", "obj": ".zip", "stl": ".stl", "ply": ".ply"}
DIRECTIONS = ("front", "back", "left", "right", "unknown")


def identifier(value: str, prefix: str) -> str:
    if not re.fullmatch(re.escape(prefix) + r"[A-Za-z0-9-]+", value):
        raise ValueError(f"Invalid {prefix} identifier")
    return value


class StudioClient:
    def __init__(self, *, workspace=None, base_url=None, transport=None):
        self.workspace = Path(workspace or os.getenv("FORMA_WORKSPACE") or Path.cwd()).expanduser().resolve()
        if not self.workspace.is_dir():
            raise ValueError("FORMA_WORKSPACE must be an existing directory")
        self.base_url = (base_url or os.getenv("FORMA_API_URL", "http://127.0.0.1:8000")).rstrip("/")
        url = urlsplit(self.base_url)
        # The current Studio API has no tenant authentication. Fail closed rather
        # than implying a remote URL is an authenticated commercial service.
        if url.scheme not in ("http", "https") or url.hostname not in ("localhost", "127.0.0.1", "::1") or url.username or url.password or url.query or url.fragment or url.path:
            raise ValueError("This preview bridge supports a loopback Studio API only")
        self.http = httpx.Client(base_url=self.base_url, timeout=60, follow_redirects=False, transport=transport)

    def close(self):
        self.http.close()

    def path(self, name: str) -> Path:
        p = (self.workspace / name).resolve()
        if not p.is_relative_to(self.workspace) or p == self.workspace:
            raise ValueError("File must be inside FORMA_WORKSPACE")
        return p

    def request(self, method, route, **kwargs):
        try:
            response = self.http.request(method, route, **kwargs)
        except httpx.TransportError as exc:
            raise RuntimeError("Studio API did not respond. A submitted job may still be running; check Studio before submitting again.") from exc
        if response.status_code >= 400:
            raise RuntimeError(f"Studio API returned HTTP {response.status_code}: {response.text[:600]}")
        if response.is_redirect:
            raise RuntimeError("Unexpected API redirect")
        return response.json()

    def health(self):
        return self.request("GET", "/api/health")

    def assets(self, limit=20):
        if not 1 <= limit <= 500:
            raise ValueError("limit must be between 1 and 500")
        return self.request("GET", "/api/assets")[:limit]

    def generate(self, prompt="", images=None, directions=None, workflow="concept", engine="trellis-2", seed=None):
        images, directions = images or [], directions or []
        if engine not in ENGINES or workflow not in ("concept", "direct"):
            raise ValueError("Unsupported engine or workflow")
        if not prompt.strip() and not images:
            raise ValueError("Provide a prompt or at least one image")
        if len(images) > 5 or (workflow == "concept" and len(images) > 1):
            raise ValueError("Concept workflow takes one image; direct workflow takes up to five")
        if workflow == "direct" and not images and engine != "rodin":
            raise ValueError("This engine needs an image; use concept workflow for text input")
        if directions and (len(directions) != len(images) or any(d not in DIRECTIONS for d in directions)):
            raise ValueError("Supply one supported direction per image")
        if len(images) > 1:
            if workflow != "direct" or len(directions) != len(images) or "unknown" in directions or len(set(directions)) != len(directions):
                raise ValueError("Multiple images require unique, explicit view directions")
            if engine == "hunyuan3d-2.1" and set(directions) != {"front", "back", "left"}:
                raise ValueError("Hunyuan multiview requires front, back and left")
        cfg = {"engine": engine, "prompt": prompt, "effort": "high", "quality": "default", "texture": True, "targetFaces": 40000, "batch": 1, "seed": seed}
        with ExitStack() as stack:
            files = []
            for name in images:
                p = self.path(name)
                if p.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp", ".avif") or not p.is_file() or not 0 < p.stat().st_size <= 20 * 1024 * 1024:
                    raise ValueError("Each image must be a PNG, JPEG, WebP or AVIF file of at most 20 MB")
                files.append(("image" if workflow == "concept" else "images", (p.name, stack.enter_context(p.open("rb")), mimetypes.guess_type(p.name)[0])))
            data = {"settings": json.dumps(cfg)}
            if workflow == "concept":
                data["prompt"] = prompt
                result = self.request("POST", "/api/pipelines", data=data, files=files)
                return {"id": result["run_id"], "workflow": workflow}
            if directions:
                data["directions"] = directions
            result = self.request("POST", "/api/generate", data=data, files=files)
            return {"id": result["job_id"], "workflow": workflow}

    def status(self, generation_id):
        prefix = "run-" if generation_id.startswith("run-") else "job-"
        identifier(generation_id, prefix)
        resource = "pipelines" if prefix == "run-" else "jobs"
        raw = self.request("GET", f"/api/{resource}/{generation_id}")
        state = raw.get("status", raw.get("stage"))
        asset_ids = raw.get("assetIds") or ([raw["assetId"]] if raw.get("assetId") else [])
        return {"id": generation_id, "status": state, "assetIds": asset_ids, "details": raw}

    def wait(self, generation_id, timeout=1800):
        deadline = time.monotonic() + timeout
        while True:
            result = self.status(generation_id)
            if result["status"] in ("done", "failed", "cancelled"):
                return result
            if time.monotonic() >= deadline:
                raise TimeoutError(f"Wait timed out; generation {generation_id} is still on the server. Resume with status.")
            time.sleep(min(3, max(0, deadline - time.monotonic())))

    def download(self, asset_id, output, format="glb"):
        identifier(asset_id, "a-")
        if format not in FORMATS:
            raise ValueError("Supported formats: glb, obj (ZIP bundle), stl, ply")
        dest = self.path(output)
        if dest.suffix.lower() != FORMATS[format]:
            raise ValueError(f"Use a {FORMATS[format]} output filename for {format}")
        if dest.exists():
            raise FileExistsError(f"Refusing to overwrite {dest.name}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        digest, size = hashlib.sha256(), 0
        tmp = None
        try:
            with self.http.stream("GET", f"/api/assets/{asset_id}/export", params={"format": format}) as response:
                response.raise_for_status()
                if response.status_code != 200:
                    raise RuntimeError("Unexpected export response")
                with tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as f:
                    tmp = Path(f.name)
                    for chunk in response.iter_bytes():
                        size += len(chunk)
                        if size > 512 * 1024 * 1024:
                            raise ValueError("Export exceeds the 512 MB bridge limit")
                        f.write(chunk)
                        digest.update(chunk)
            if not size:
                raise ValueError("Empty export")
            with tmp.open("rb") as f:
                signature = f.read(4)
            if (format == "glb" and signature != b"glTF") or (format == "obj" and signature[:2] != b"PK"):
                raise ValueError("Export contents do not match requested format")
            # link is atomic and fails if the destination appeared mid-download.
            os.link(tmp, dest)
        finally:
            if tmp:
                tmp.unlink(missing_ok=True)
        return {"assetId": asset_id, "path": str(dest), "format": format, "bytes": size, "sha256": digest.hexdigest()}
