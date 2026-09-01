"""
Gemini adapter — the concept stage that sits in front of the 3D engines.

SERVER ONLY. GEMINI_API_KEY is read here and nowhere else; the React app talks
to this process and never to Google. The key must never be given a VITE_ prefix,
because Vite inlines anything so named straight into the browser bundle.

Two calls live here and they do different jobs:

  write_prompt()  a text model reads the user's rough photo and their few words,
                  and writes the full image prompt. This is the step that turns
                  "make it a knight" into something an image model can execute.
  make_image()    an image model renders that prompt, with the user's photo
                  attached as a reference so the result is still THEIR subject.

Why bother, when the 3D engines already accept a photo? Because image-to-3D is
only as good as its input, and a phone snapshot is close to the worst case: a
cluttered background the segmenter has to guess at, one arm cropped, hard shadows
baked into the albedo. The concept pass re-renders the same subject as a clean,
evenly-lit, fully-visible asset on a plain backdrop — which is exactly the input
TRELLIS and Hunyuan are strongest on.
"""
from __future__ import annotations

import base64
import mimetypes
import time
from pathlib import Path

import requests

from .config import GEMINI_API_KEY, GEMINI_IMAGE_MODEL, GEMINI_TEXT_MODEL

BASE = "https://generativelanguage.googleapis.com/v1beta"
TIMEOUT = 180


class GeminiError(RuntimeError):
    pass


def available() -> tuple[bool, str]:
    """Cheap, no network — can the concept stage run at all?"""
    if not GEMINI_API_KEY:
        return False, "GEMINI_API_KEY not set"
    return True, f"{GEMINI_TEXT_MODEL} + {GEMINI_IMAGE_MODEL}"


def _scrub(text: str) -> str:
    """Never let the key reach a log line or an HTTP response body."""
    return text.replace(GEMINI_API_KEY, "***") if GEMINI_API_KEY else text


def _call(model: str, body: dict) -> dict:
    ok, why = available()
    if not ok:
        raise GeminiError(why)
    r = requests.post(
        f"{BASE}/models/{model}:generateContent",
        params={"key": GEMINI_API_KEY},
        json=body,
        timeout=TIMEOUT,
    )
    if not r.ok:
        detail = ""
        try:
            detail = r.json().get("error", {}).get("message", "")
        except Exception:
            detail = r.text[:300]
        raise GeminiError(f"{model}: {r.status_code} {_scrub(detail)}")
    return r.json()


def _inline(path: Path) -> dict:
    mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    return {"inlineData": {"mimeType": mime, "data": base64.b64encode(path.read_bytes()).decode()}}


# --------------------------------------------------------------------- prompt
# The house look, described once. Every gallery asset shares it, and a concept
# that drifts off it produces a mesh that looks foreign next to the others.
STYLE = """a stylised game-ready 3D character render: soft matte surfaces,
rounded forms, slightly oversized head and hands, clean readable silhouette,
gentle studio key light from the upper left with a soft fill, no harsh shadows,
saturated but not neon colours, plain near-black background"""

PROMPT_SYSTEM = f"""You write the single image prompt that turns somebody's rough
photo into a clean 3D asset render. That render is then fed to an image-to-3D
model, so you are really writing for the reconstructor, not for a viewer.

Five rules, and they all come from what breaks reconstruction:

1. ONE SUBJECT, WHOLE. The entire object in frame with margin on every side.
   Nothing cropped, nothing leaving the frame, nothing else in shot. A cut-off
   foot becomes a hole in the mesh.
2. PLAIN BACKGROUND. Flat near-black, no floor, no horizon, no cast shadow, no
   props. Anything back there gets reconstructed as geometry.
3. THREE-QUARTER FRONT VIEW, eye level, full body, upright and centred. Not a
   dynamic pose, not a dutch angle, not a close-up.
4. EVEN, SOFT LIGHT. No hard rim, no deep shade, no blown highlight — those bake
   into the albedo and the mesh inherits fake shading forever.
5. NO TEXT anywhere: no logos, no lettering, no watermark, no signage.

The style is fixed and you always state it: {STYLE}.

Read the attached photo for WHAT the thing is — its shapes, colours, materials
and proportions — and keep those. The user's words say what to CHANGE. Where the
photo and the words disagree, the words win. Where the words are silent, the
photo wins; do not invent details it does not support.

Write:
- title: 2-4 words, name of the asset. Becomes the filename and the card label.
- subject: one clause naming the thing plainly ("a red ceramic teapot").
- prompt: the full image prompt, one paragraph, imperative, self-contained.
  It must carry the style and all five rules explicitly — the image model sees
  this text and nothing else you wrote.
- notes: one short sentence to the user about the call you made. What you kept
  from their photo, what you changed. Never generic, never a restatement."""

PROMPT_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string"},
        "subject": {"type": "string"},
        "prompt": {"type": "string"},
        "notes": {"type": "string"},
    },
    "required": ["title", "subject", "prompt", "notes"],
}


def write_prompt(user_prompt: str, image: Path | None = None) -> dict:
    """Turn a rough photo plus a few words into a full image prompt."""
    parts: list[dict] = []
    if image and image.is_file():
        parts.append(_inline(image))
    said = user_prompt.strip() or "(the user said nothing — go by the photo alone)"
    parts.append({"text": f"the user's words: {said}\n\nWrite the prompt."})

    started = time.time()
    json_body = {
        "contents": [{"role": "user", "parts": parts}],
        "systemInstruction": {"parts": [{"text": PROMPT_SYSTEM}]},
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": PROMPT_SCHEMA,
        },
    }
    data = _call(GEMINI_TEXT_MODEL, json_body)

    cand = (data.get("candidates") or [{}])[0]
    text = next(
        (p["text"] for p in (cand.get("content") or {}).get("parts") or [] if p.get("text")),
        None,
    )
    if not text:
        raise GeminiError(f"no prompt returned ({cand.get('finishReason', 'empty')})")

    import json as _json

    out = _json.loads(text)
    out["model"] = GEMINI_TEXT_MODEL
    out["ms"] = int((time.time() - started) * 1000)
    return out


# ---------------------------------------------------------------------- image
def make_image(prompt: str, refs: list[Path] | None = None, aspect: str = "1:1") -> dict:
    """Render the concept. Returns the bytes plus what it took to get them."""
    parts: list[dict] = [_inline(p) for p in (refs or []) if p.is_file()]
    parts.append({"text": prompt})

    started = time.time()
    data = _call(
        GEMINI_IMAGE_MODEL,
        {
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
                "imageConfig": {"aspectRatio": aspect},
            },
        },
    )

    cand = (data.get("candidates") or [{}])[0]
    blob = next(
        (p["inlineData"] for p in (cand.get("content") or {}).get("parts") or [] if p.get("inlineData")),
        None,
    )
    if not blob:
        raise GeminiError(f"no image returned ({cand.get('finishReason', 'empty')})")

    return {
        "bytes": base64.b64decode(blob["data"]),
        "mime": blob.get("mimeType", "image/png"),
        "model": GEMINI_IMAGE_MODEL,
        "ms": int((time.time() - started) * 1000),
    }
