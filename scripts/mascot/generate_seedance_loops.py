#!/usr/bin/env python3
"""Generate the six mascot waiting loops with fal Seedance 2.5 image-to-video.

One submission per clip, no automatic retries. The original concept art is
both the first and the last frame so every clip returns to its start pose and
loops without a visible seam. Audio is disabled; the app plays these muted.

Endpoint verified against https://fal.ai/models/bytedance/seedance-2.5/image-to-video/api
on 2026-09-18. Reads FAL_KEY from the environment or the repository .env and
never prints it.

Usage: venv/bin/python scripts/mascot/generate_seedance_loops.py [--only dragon-thinking ...]
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/design/mascot-animations"
ENDPOINT = "bytedance/seedance-2.5/image-to-video"
QUEUE = f"https://queue.fal.run/{ENDPOINT}"
# fal serves request status/results under the app root, not the full endpoint path.
REQUESTS = "https://queue.fal.run/bytedance/seedance-2.5/requests"
POLL_SECONDS = 10
TIMEOUT_SECONDS = 20 * 60

COMMON = (
    " Locked-off static camera, no zoom, no pan, no cut. Keep the exact same character design, "
    "colors, proportions and the plain pale background from the image. No text, no extra characters, "
    "no new props except the soft glowing light described. Gentle, friendly, slow cartoon motion. "
    "The character ends in exactly the same pose it started in so the clip loops seamlessly."
)

CHARACTERS = {
    "dragon": ("source/cloud-dragon-960.jpg", "the small blue baby dragon"),
    "panda": ("source/panda-chef-960.jpg", "the panda chef"),
}

PHASES = {
    "thinking": (
        "{who} is thinking: it blinks slowly twice, tilts its head gently to one side with a curious "
        "smile, a tiny soft glowing orb of light floats and bobs above its head, then it tilts back."
    ),
    "concept": (
        "{who} draws in the air like a friendly magician: {limb} sweeps in a smooth arc leaving a "
        "trail of glowing sparkling light strokes that sketch a simple shape, the glowing lines "
        "shimmer and fade away, then {limb} returns to rest."
    ),
    "model": (
        "{who} sculpts in 3D: a small translucent glowing cube of light appears between its hands, "
        "slowly rotates and orbits while the hands shape it with gentle kneading gestures, then the "
        "cube softly dissolves into sparkles and the hands return to rest."
    ),
}

LIMBS = {"dragon": "one front claw", "panda": "the wooden spoon, held like a wand,"}


def fal_key() -> str:
    key = os.environ.get("FAL_KEY", "").strip()
    if not key:
        for line in (ROOT / ".env").read_text().splitlines():
            if line.startswith("FAL_KEY="):
                key = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not key:
        raise SystemExit("FAL_KEY is not configured")
    return key


def data_uri(path: Path) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(path.read_bytes()).decode()


def jobs(only: set[str]) -> list[dict]:
    result = []
    for character, (image, who) in CHARACTERS.items():
        for phase, template in PHASES.items():
            name = f"{character}-{phase}"
            if only and name not in only:
                continue
            prompt = template.format(who=who.capitalize() if template.startswith("{who}") else who,
                                     limb=LIMBS[character]) + COMMON
            result.append({"name": name, "image": image, "prompt": prompt})
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=[])
    args = parser.parse_args()
    headers = {"Authorization": f"Key {fal_key()}", "Content-Type": "application/json"}
    raw = OUT / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    log_path = OUT / "seedance-log.json"
    log = json.loads(log_path.read_text()) if log_path.exists() else {}

    pending = {}
    # Resume anything already submitted instead of paying for it twice.
    for name, entry in log.items():
        if entry.get("status") in ("submitted", "timed_out_locally") and (not args.only or name in args.only):
            rid = entry["request_id"]
            pending[name] = ({"name": name}, {"status_url": f"{REQUESTS}/{rid}/status",
                                              "response_url": f"{REQUESTS}/{rid}"})
            print(f"{name}: resuming {rid}")
    for job in jobs(set(args.only)):
        if job["name"] in log and log[job["name"]].get("status") != "submit_failed":
            continue  # never resubmit a clip that was already charged or is in flight
        image = data_uri(OUT / job["image"])
        body = {
            "prompt": job["prompt"],
            "image_url": image,
            "end_image_url": image,
            "resolution": "480p",
            "duration": "4",
            "generate_audio": False,
        }
        response = requests.post(QUEUE, headers=headers, json=body, timeout=120)
        if response.status_code >= 300:
            print(f"{job['name']}: submit failed HTTP {response.status_code}: {response.text[:400]}")
            log[job["name"]] = {"status": "submit_failed", "http": response.status_code,
                                "detail": response.text[:400], "prompt": job["prompt"]}
            continue
        submitted = response.json()
        print(f"{job['name']}: submitted {submitted.get('request_id')}")
        pending[job["name"]] = (job, submitted)
        log[job["name"]] = {"status": "submitted", "request_id": submitted.get("request_id"),
                            "endpoint": ENDPOINT, "prompt": job["prompt"],
                            "source": job["image"], "resolution": "480p", "duration_s": 4}
        log_path.write_text(json.dumps(log, indent=2))

    deadline = time.time() + TIMEOUT_SECONDS
    while pending and time.time() < deadline:
        time.sleep(POLL_SECONDS)
        for name, (job, submitted) in list(pending.items()):
            status = requests.get(submitted["status_url"], headers=headers, timeout=60).json()
            if status.get("status") != "COMPLETED":
                continue
            result = requests.get(submitted["response_url"], headers=headers, timeout=60)
            del pending[name]
            if result.status_code >= 300:
                print(f"{name}: failed HTTP {result.status_code}: {result.text[:400]}")
                log[name].update(status="failed", detail=result.text[:400])
            else:
                payload = result.json()
                video = requests.get(payload["video"]["url"], timeout=300)
                (raw / f"{name}.mp4").write_bytes(video.content)
                log[name].update(status="completed", seed=payload.get("seed"),
                                 bytes=len(video.content))
                print(f"{name}: saved raw/{name}.mp4 ({len(video.content)} bytes)")
            log_path.write_text(json.dumps(log, indent=2))
    for name in pending:
        log[name]["status"] = "timed_out_locally"
        print(f"{name}: still pending after timeout; not retried")
    log_path.write_text(json.dumps(log, indent=2))


if __name__ == "__main__":
    main()
