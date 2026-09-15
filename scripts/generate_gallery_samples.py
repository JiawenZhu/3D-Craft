#!/usr/bin/env python3
"""Produce a reviewed gallery batch through the studio's normal Rodin workflow.

Default is read-only status. --submit explicitly submits only never-attempted
entries, and --wait polls/reconciles existing jobs. Interrupted or uncertain
submissions are NEVER automatically repeated. No provider SDK is called here.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import time
from urllib.parse import urlparse

import httpx
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "docs/design/gallery-samples/manifest.json"
ACTIVE = {"submitted", "running", "submitting", "uncertain"}


def now():
    return datetime.now(timezone.utc).isoformat()


def save(path, manifest):
    samples = manifest.get("samples", [])
    for entry in samples:
        if entry.get("status") == "done":
            entry.update(stage="ready", progress=100)
    if samples:
        done = sum(entry.get("status") == "done" for entry in samples)
        manifest["completedCount"] = done
        manifest["progress"] = round(done / len(samples) * 100, 1)
        manifest["status"] = ("complete" if done == len(samples) else
            "generating" if any(entry.get("status") in ACTIVE for entry in samples) else
            "needs-review" if any(entry.get("status") in {"failed", "uncertain", "needs-review"} for entry in samples) else "ready")
    manifest["updatedAt"] = now()
    temp = path.with_suffix(".json.tmp")
    with temp.open("w") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write("\n")
        file.flush()
        os.fsync(file.fileno())
    os.replace(temp, path)


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_image(entry):
    path = Path(entry["conceptPath"])
    if not path.is_absolute():
        path = ROOT / path
    path = path.resolve()
    approved_root = (ROOT / "docs/design/gallery-samples").resolve()
    if not path.is_relative_to(approved_root) or not path.is_file():
        raise ValueError(f"{entry['slug']}: concept must be an existing PNG in docs/design/gallery-samples")
    with Image.open(path) as image:
        if image.format != "PNG" or min(image.size) < 512:
            raise ValueError(f"{entry['slug']}: concept must be a valid PNG of at least 512 px")
        image.verify()
    return path


def settings(entry, batch_id):
    return {
        "engine": "rodin", "prompt": entry.get("reconstructionPrompt") or
            f"{entry['name']}. Reconstruct the single object in the supplied concept image as a textured 3D game asset. Preserve the silhouette, proportions, facial features, colors and visible materials. The image is the primary reference. Do not invent additional objects or merge duplicate subjects.",
        "effort": "high", "quality": "default", "texture": True, "batch": 1,
        "targetFaces": 100_000, "geoMode": "sharp", "poseMode": "none",
        "removeBackground": True, "seed": 42,
        "sourceRef": f"gallery:{batch_id}:{entry['slug']}",
    }


def copy_source(entry, path):
    # Preserve the full-quality concept separately from the engine's normalized
    # thumbnail. This is display/provenance metadata, never a reconstruction edit.
    destination = ROOT / "server/storage/gallery-samples" / (entry["slug"] + ".png")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and checksum(destination) != checksum(path):
        raise ValueError(f"{entry['slug']}: published concept differs; use a new slug instead of overwriting it")
    if not destination.exists():
        shutil.copyfile(path, destination)
    entry["sourceImageUrl"] = f"/files/gallery-samples/{entry['slug']}.png"


def submit(client, base, entry, manifest, manifest_path):
    if entry.get("status", "ready") != "ready" or entry.get("jobId") or entry.get("submissionAttemptedAt"):
        return False
    path = source_image(entry)
    fingerprint = checksum(path)
    if entry.get("conceptSha256") and entry["conceptSha256"] != fingerprint:
        raise ValueError(f"{entry['slug']}: concept changed after review")
    entry["conceptSha256"] = fingerprint
    cfg = settings(entry, manifest["batchId"])
    copy_source(entry, path)
    entry.update(status="submitting", submissionAttemptedAt=now(), settings=cfg,
                 sourceRef=cfg["sourceRef"])
    # Durable BEFORE the cost-bearing request. A crash in the response window
    # leaves an ambiguous record, which may be reconciled but never resubmitted.
    save(manifest_path, manifest)
    try:
        with path.open("rb") as file:
            response = client.post(base + "/api/generate", data={"settings": json.dumps(cfg), "directions": "front"},
                                   files={"images": (path.name, file, "image/png")}, timeout=60)
        response.raise_for_status()
        job_id = response.json().get("job_id")
        if not isinstance(job_id, str) or not job_id.startswith("job-"):
            raise ValueError("The server did not return a job ID")
        entry.update(jobId=job_id, status="submitted")
        print(f"{entry['slug']}: submitted {job_id}", flush=True)
    except (httpx.HTTPError, ValueError):
        entry.update(status="uncertain", error="Submission response was unsuccessful or ambiguous. Do not retry automatically; reconcile the existing job/asset first.")
        print(f"{entry['slug']}: uncertain submission; automatic resubmission disabled", flush=True)
    save(manifest_path, manifest)
    return True


def annotate(client, base, entry, asset, manifest, manifest_path):
    # A thumbnail is not completion: require the real textured triangle asset.
    model_url = asset.get("modelUrl", "")
    model_path = ROOT / "server/storage" / model_url.removeprefix("/files/")
    valid_location = model_url.startswith(f"/files/{asset['id']}/") and model_path.resolve().is_relative_to((ROOT / "server/storage").resolve())
    raw = model_path.read_bytes() if valid_location and model_path.is_file() else b""
    valid_glb = len(raw) >= 20 and raw[:4] == b"glTF" and struct.unpack_from("<I", raw, 4)[0] == 2
    if asset.get("engine") != "rodin" or not valid_glb or not asset.get("faces") or not asset.get("materials") or not asset.get("textureRes"):
        entry.update(status="needs-review", assetId=asset["id"], error="Generation returned without a verified textured Rodin GLB. No additional generation was started.")
        save(manifest_path, manifest)
        return
    entry.update(modelSha256=hashlib.sha256(raw).hexdigest(), dimensions=asset.get("dimensions"), materials=asset.get("materials"))
    source_url = entry.get("sourceImageUrl") or f"/files/gallery-samples/{entry['slug']}.png"
    fields = {
        "name": entry["name"], "kind": entry["kind"], "description": entry["description"],
        "sourceImageUrl": source_url,
        "galleryExample": {"batchId": manifest["batchId"], "slug": entry["slug"],
            "conceptSha256": entry["conceptSha256"], "description": entry["description"]},
    }
    response = client.post(base + f"/api/assets/{asset['id']}/gallery-example", json=fields, timeout=15)
    response.raise_for_status()
    entry.update(status="done", assetId=asset["id"], modelUrl=asset["modelUrl"], sourceImageUrl=source_url,
                 faces=asset.get("faces"), textureRes=asset.get("textureRes"), completedAt=now())
    entry.pop("error", None)
    save(manifest_path, manifest)
    print(f"{entry['slug']}: ready {asset['id']}", flush=True)


def reconcile(client, base, entry, manifest, manifest_path, assets):
    if entry.get("status") == "done":
        return
    marker = entry.get("sourceRef")
    matches = [asset for asset in assets if marker and asset.get("sourceRef") == marker]
    if len(matches) > 1:
        entry.update(status="needs-review", error="More than one asset matches this submission marker; no new generation started.")
        save(manifest_path, manifest)
        return
    if matches:
        annotate(client, base, entry, matches[0], manifest, manifest_path)
        return
    job_id = entry.get("jobId")
    if not job_id:
        return
    response = client.get(base + f"/api/jobs/{job_id}", timeout=15)
    if response.status_code == 404:
        entry.update(status="uncertain", error="Job is no longer in server memory. Waiting for an asset with its exact sourceRef; automatic resubmission disabled.")
        save(manifest_path, manifest)
        return
    response.raise_for_status()
    job = response.json()
    if job.get("stage") == "done" and job.get("assets"):
        annotate(client, base, entry, job["assets"][0], manifest, manifest_path)
        return
    if job.get("stage") == "failed":
        entry.update(status="failed", error="The existing model job failed. Inspect the server job before explicitly approving another paid attempt.")
    else:
        entry.update(status="running", stage=job.get("stage"), progress=job.get("progress"))
    save(manifest_path, manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--base-url", default="http://127.0.0.1:8001")
    parser.add_argument("--submit", action="store_true", help="Submit reviewed, never-attempted entries exactly once")
    parser.add_argument("--wait", action="store_true", help="Poll existing submissions until terminal or timeout")
    parser.add_argument("--only", help="Comma-separated slugs")
    parser.add_argument("--timeout", type=int, default=3600)
    parser.add_argument("--poll-seconds", type=float, default=5)
    args = parser.parse_args()
    base = args.base_url.rstrip("/")
    parsed = urlparse(base)
    if parsed.scheme != "http" or parsed.hostname not in ("127.0.0.1", "localhost", "::1"):
        parser.error("This production helper is restricted to a loopback studio API")
    manifest_path = args.manifest.resolve()
    lock_path = manifest_path.with_suffix(".lock")
    with lock_path.open("a") as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error("Another gallery production process holds this manifest")
        manifest = json.loads(manifest_path.read_text())
        entries = manifest["samples"]
        for entry in entries:
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", entry["slug"]):
                parser.error("Invalid sample slug")
        if len({entry['slug'] for entry in entries}) != len(entries):
            parser.error("Duplicate sample slugs")
        if args.only:
            chosen = set(args.only.split(","))
            if chosen - {entry['slug'] for entry in entries}:
                parser.error("Unknown sample slug")
            entries = [entry for entry in entries if entry['slug'] in chosen]
        if not args.submit and not args.wait:
            for entry in entries:
                print(f"{entry['slug']}: {entry.get('status','ready')} {entry.get('assetId') or entry.get('jobId') or ''}")
            return
        client = httpx.Client(trust_env=False)  # Do not proxy loopback assets or credentials.
        response = client.get(base + "/api/health", timeout=30)
        response.raise_for_status()
        health = response.json()
        rodin = health.get("engines", {}).get("rodin", {})
        if args.submit and not rodin.get("installed"):
            raise RuntimeError("Rodin is not configured on the running studio API")
        if args.submit:
            # Validate all reviewed files before submitting any model.
            for entry in entries:
                if entry.get('status','ready') == 'ready': source_image(entry)
            for entry in entries:
                submit(client, base, entry, manifest, manifest_path)
        deadline = time.monotonic() + args.timeout
        while True:
            response = client.get(base + "/api/assets", timeout=20)
            response.raise_for_status()
            assets = response.json()
            for entry in entries:
                if entry.get('status') in ACTIVE:
                    try:
                        reconcile(client, base, entry, manifest, manifest_path, assets)
                    except httpx.HTTPError:
                        print(f"{entry['slug']}: status/annotation unavailable; keeping submission record", flush=True)
            if not args.wait or not any(entry.get('status') in ACTIVE for entry in entries):
                break
            if time.monotonic() >= deadline:
                print("Polling deadline reached. Resume with --wait; existing jobs will not be resubmitted.", flush=True)
                break
            time.sleep(max(1, args.poll_seconds))
        counts = {status: sum(entry.get('status') == status for entry in entries) for status in sorted({entry.get('status','ready') for entry in entries})}
        save(manifest_path, manifest)
        print(json.dumps(counts, sort_keys=True))


if __name__ == "__main__":
    main()
