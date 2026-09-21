#!/usr/bin/env python3
"""Generate cat jumping videos using MiniMax H3 (480P and 768P) via fal.ai.

Uses the identical source image and prompt as Seedance 2.5 for direct comparison.
Saves videos locally without uploading to the iOS app.
"""
import os
import sys
import time
import requests
from pathlib import Path
import fal_client

# Ensure FAL_KEY is available
if not os.getenv("FAL_KEY"):
    env_file = Path(__file__).resolve().parent.parent / ".env"
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                if line.startswith("FAL_KEY="):
                    os.environ["FAL_KEY"] = line.split("=", 1)[1].strip().strip('"\'')

if not os.getenv("FAL_KEY"):
    print("Error: FAL_KEY not found in environment or .env file", file=sys.stderr)
    sys.exit(1)

IMAGE_URL = "https://v3b.fal.media/files/b/0aab3d5e/lsvk2tqNP_sSc-Cn1n-E8_lantern_cat.jpg"

PROMPT = (
    "The orange tabby adventurer cat performs a smooth, continuous jumping animation: "
    "it crouches slightly, bends its knees, springs upward into the air, reaches the apex of the jump, "
    "and lands softly back onto its feet, absorbing the landing and returning to its initial standing stance. "
    "Natural dynamic physics and secondary motion on all clothing and props: "
    "the green robe and sleeves billow and flutter upward with air resistance, "
    "the leather belt and the dangling jade pendant swing and bounce realistically with gravity and inertia, "
    "the furry cat ears bounce, and the striped tail sways gracefully to maintain balance. "
    "Locked-off static camera, plain grey studio backdrop identical to the source image, "
    "no zoom, no pan, no cut. Ends in the exact same pose as the start so it loops seamlessly."
)

ENDPOINT = "minimax/h3/image-to-video"

def submit_job(resolution: str):
    print(f"[{resolution}] Submitting to {ENDPOINT}...")
    args = {
        "prompt": PROMPT,
        "image_url": IMAGE_URL,
        "end_image_url": IMAGE_URL,
        "resolution": resolution,
        "duration": 5,
        "prompt_expansion_mode": "disabled",
    }
    handler = fal_client.submit(ENDPOINT, arguments=args)
    print(f"[{resolution}] Request ID: {handler.request_id}")
    return handler

def wait_and_download(resolution: str, handler, out_filename: str):
    print(f"[{resolution}] Waiting for completion...")
    start_t = time.time()
    result = handler.get()
    elapsed = time.time() - start_t
    print(f"[{resolution}] Completed in {elapsed:.1f}s. Result keys: {list(result.keys())}")
    
    video_info = result.get("video")
    if not video_info or "url" not in video_info:
        raise RuntimeError(f"[{resolution}] No video URL in response: {result}")
    
    video_url = video_info["url"]
    print(f"[{resolution}] Video URL: {video_url}")
    
    # Download video
    res = requests.get(video_url, timeout=60)
    res.raise_for_status()
    
    # Save to both local repo root and /tmp
    destinations = [
        Path(__file__).resolve().parent.parent / out_filename,
        Path("/tmp") / out_filename,
    ]
    for dest in destinations:
        with open(dest, "wb") as f:
            f.write(res.content)
        print(f"[{resolution}] Saved {len(res.content)} bytes to {dest}")
        
    return {
        "resolution": resolution,
        "elapsed": elapsed,
        "url": video_url,
        "size_bytes": len(res.content),
        "local_paths": [str(d) for d in destinations],
    }

def main():
    print("=== MiniMax H3 Cat Jump Generation ===")
    print(f"Source Image: {IMAGE_URL}")
    print(f"Prompt: {PROMPT}\n")
    
    # Submit both jobs in parallel
    h_480p = submit_job("480P")
    h_768p = submit_job("768P")
    
    print("\nBoth jobs submitted in parallel. Polling results...\n")
    
    res_480p = wait_and_download("480P", h_480p, "minimax_cat_jump_480p.mp4")
    res_768p = wait_and_download("768P", h_768p, "minimax_cat_jump_768p.mp4")
    
    print("\n=== Generation Finished Successfully ===")
    print("480P Result:", res_480p)
    print("768P Result:", res_768p)

if __name__ == "__main__":
    main()
