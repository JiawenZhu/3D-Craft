#!/usr/bin/env python
"""
Fetch what native local inference needs: the upstream source repos and the
model weights.

  python scripts/fetch_weights.py            shape weights (~3 GB) + repos
  python scripts/fetch_weights.py --paint    + Hunyuan3D PBR paint (CUDA only)
  python scripts/fetch_weights.py --trellis  + TRELLIS-image-large (CUDA only)
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from huggingface_hub import snapshot_download  # noqa: E402

from server.config import HF_TOKEN, REPOS, WEIGHTS  # noqa: E402

WANT_PAINT = "--paint" in sys.argv or "--all" in sys.argv
WANT_TRELLIS = "--trellis" in sys.argv or "--all" in sys.argv

REPO_URLS = {
    "Hunyuan3D-2.1": "https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1.git",
}
if WANT_TRELLIS:
    REPO_URLS["TRELLIS"] = "https://github.com/microsoft/TRELLIS.git"

for name, url in REPO_URLS.items():
    dest = REPOS / name
    if dest.exists():
        print(f"▸ {name} already cloned")
        continue
    print(f"▸ cloning {url}")
    subprocess.run(["git", "clone", "--depth", "1", url, str(dest)], check=True)

TARGETS: list[tuple[str, str, list[str] | None]] = [
    # Shape generation runs on CUDA, MPS and CPU — this is the part that works
    # natively on an Apple Silicon Mac.
    ("tencent/Hunyuan3D-2.1", "hunyuan3d-2.1", ["hunyuan3d-dit-v2-1/*", "hunyuan3d-vae-v2-1/*"]),
]
if WANT_PAINT:
    TARGETS.append(("tencent/Hunyuan3D-2.1", "hunyuan3d-2.1", ["hunyuan3d-paintpbr-v2-1/*"]))
if WANT_TRELLIS:
    TARGETS.append(("microsoft/TRELLIS-image-large", "trellis-image-large", None))

for repo, sub, allow in TARGETS:
    dest = WEIGHTS / sub
    print(f"▸ {repo} {allow or '(everything)'} -> {dest}")
    snapshot_download(repo_id=repo, local_dir=str(dest), allow_patterns=allow,
                      token=HF_TOKEN, max_workers=8)

# The matting model is a ~1 GB lazy download inside rembg; pull it now so the
# first generation is not stalled behind it.
print("▸ warming the background-removal model")
try:
    sys.path.insert(0, str(REPOS / "Hunyuan3D-2.1" / "hy3dshape"))
    from hy3dshape.rembg import BackgroundRemover
    from PIL import Image

    BackgroundRemover()(Image.new("RGBA", (64, 64), (255, 0, 0, 255)))
    print("  matting model cached")
except Exception as exc:
    print(f"  skipped ({type(exc).__name__}: {exc}) — it will download on first use")

print("\n✓ weights ready in", WEIGHTS)
if not HF_TOKEN:
    print("  tip: export HF_TOKEN=… for faster, rate-limit-free downloads")
