"""Paths and runtime settings for the Rodin studio backend."""
from __future__ import annotations

import os
from pathlib import Path

# Load a repo-root .env before anything reads os.getenv, so FAL_KEY / HF_TOKEN can
# live in a gitignored file instead of every shell that starts the server.
try:
    from dotenv import load_dotenv

    load_dotenv(Path(__file__).resolve().parent.parent / ".env")
except ImportError:
    pass

ROOT = Path(__file__).resolve().parent
STORAGE = Path(os.getenv("RODIN_STORAGE", ROOT / "storage"))
WEIGHTS = Path(os.getenv("RODIN_WEIGHTS", ROOT / "weights"))
REPOS = Path(os.getenv("RODIN_REPOS", ROOT / "vendor"))
# Hand-off folder: the image/animation side drops references here. It lives under
# public/ so Vite serves the files directly too; the API still lists it so new
# drops show up without a rebuild.
REPO_ROOT = ROOT.parent
INBOX = Path(os.getenv("RODIN_INBOX", REPO_ROOT / "public" / "images" / "explore"))
# Converted downloads, kept apart from the generated assets so they can be
# cleared without touching anything that cannot be regenerated for free.
EXPORTS = Path(os.getenv("RODIN_EXPORTS", ROOT / "exports"))
# Pipeline runs: one folder per run holding the source photo, the concept image
# and run.json. Deliberately NOT inside STORAGE — assets are meshes and runs are
# the history that produced them, and the Firestore split later is the same one.
RUNS = Path(os.getenv("RODIN_RUNS", ROOT / "runs"))

for _p in (STORAGE, WEIGHTS, REPOS, INBOX, EXPORTS, RUNS):
    _p.mkdir(parents=True, exist_ok=True)

HOST = os.getenv("RODIN_HOST", "127.0.0.1")
PORT = int(os.getenv("RODIN_PORT", "8000"))

HF_TOKEN = os.getenv("HF_TOKEN") or os.getenv("HUGGING_FACE_HUB_TOKEN")

# fal.ai serverless inference. Set FAL_KEY in the shell that starts the server —
# it must never reach the browser, which is why the React app only ever talks to
# this process and never to fal directly.
FAL_KEY = os.getenv("FAL_KEY")

# Gemini — the concept stage that runs before the 3D engines. Server-side only.
# Never define this as VITE_GEMINI_API_KEY: Vite inlines VITE_* into the browser
# bundle, which publishes the key to everyone who loads the page.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
# The planner writes every prompt the image model executes, so a weaker text
# model degrades the concept and no amount of image quality rescues it.
GEMINI_TEXT_MODEL = os.getenv("RODIN_GEMINI_TEXT_MODEL", "gemini-3.7-flash")
# The concept image sets the ceiling on the mesh — image-to-3D cannot recover
# detail that was never rendered — so this defaults to the pro model.
GEMINI_IMAGE_MODEL = os.getenv("RODIN_GEMINI_IMAGE_MODEL", "gemini-3-pro-image")

# Which provider each engine should try first.
#   auto  -> fal.ai when FAL_KEY is set, else a native local pipeline,
#            else the model's hosted Hugging Face Space
#   api   -> fal.ai only
#   local -> native only (fails loudly if unavailable)
#   space -> hosted Hugging Face Space only
PROVIDER = os.getenv("RODIN_PROVIDER", "auto").lower()

# fal endpoint ids, overridable so a new model version is a config change.
FAL_ENDPOINTS = {
    "trellis-2": os.getenv("RODIN_FAL_TRELLIS", "fal-ai/trellis"),
    "hunyuan3d-2.1": os.getenv("RODIN_FAL_HUNYUAN", "fal-ai/hunyuan3d/v2"),
    "hunyuan3d-2.1-mv": os.getenv("RODIN_FAL_HUNYUAN_MV", "fal-ai/hunyuan3d/v2/multi-view"),
    "rodin": os.getenv("RODIN_FAL_RODIN", "fal-ai/hyper3d/rodin"),
}

# Published list price per generation, shown in the UI so cost is never a surprise.
FAL_PRICES = {
    "trellis-2": 0.02,
    "hunyuan3d-2.1": 0.16,          # 0.48 when textured_mesh=True
    "hunyuan3d-2.1-textured": 0.48,
    "rodin": 0.40,
}

SPACES = {
    "hunyuan3d-2.1": os.getenv("RODIN_HUNYUAN_SPACE", "tencent/Hunyuan3D-2.1"),
    "trellis-2": os.getenv("RODIN_TRELLIS_SPACE", "microsoft/TRELLIS.2"),
}

HF_REPOS = {
    "hunyuan3d-2.1": "tencent/Hunyuan3D-2.1",
    "trellis-2": "microsoft/TRELLIS-image-large",
}
