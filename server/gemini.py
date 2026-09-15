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
import os
import re
from pathlib import Path

import httpx

from .config import (
    GEMINI_API_KEY,
    GEMINI_IMAGE_MODEL,
    GEMINI_TEXT_MODEL,
    USE_VERTEX_API,
    VERTEX_API_KEY,
    VERTEX_LOCATION,
    VERTEX_PROJECT_ID,
)

BASE = "https://generativelanguage.googleapis.com/v1beta"
TIMEOUT = 180


class GeminiError(RuntimeError):
    pass


def _get_vertex_auth_header() -> dict[str, str]:
    """Retrieve Google Cloud IAM Bearer token or Vertex API Key header."""
    token = os.getenv("GOOGLE_OAUTH_ACCESS_TOKEN")
    if not token:
        try:
            import google.auth
            import google.auth.transport.requests

            creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
            auth_req = google.auth.transport.requests.Request()
            creds.refresh(auth_req)
            token = creds.token
        except Exception:
            token = None
    if token:
        return {"Authorization": f"Bearer {token}"}
    key = VERTEX_API_KEY or GEMINI_API_KEY
    if key:
        return {"x-goog-api-key": key}
    return {}


def available() -> tuple[bool, str]:
    """Cheap, no network — can the concept stage run at all?"""
    if USE_VERTEX_API:
        has_key = bool(VERTEX_API_KEY or GEMINI_API_KEY)
        has_oauth = bool(os.getenv("GOOGLE_OAUTH_ACCESS_TOKEN"))
        if not (has_key or has_oauth):
            try:
                import google.auth

                creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
                has_oauth = bool(creds)
            except Exception:
                pass
        if not (has_key or has_oauth):
            return False, f"Vertex AI enabled for project '{VERTEX_PROJECT_ID}', but no credentials or API key set"
        return True, f"Vertex AI ({VERTEX_LOCATION}/{VERTEX_PROJECT_ID}): {GEMINI_TEXT_MODEL} + {GEMINI_IMAGE_MODEL}"
    if not GEMINI_API_KEY:
        return False, "GEMINI_API_KEY not set"
    return True, f"{GEMINI_TEXT_MODEL} + {GEMINI_IMAGE_MODEL}"


def _scrub(text: str) -> str:
    """Never let secrets reach a log line or an HTTP response body."""
    if not text:
        return text
    scrubbed = text
    if GEMINI_API_KEY:
        scrubbed = scrubbed.replace(GEMINI_API_KEY, "***")
    if VERTEX_API_KEY:
        scrubbed = scrubbed.replace(VERTEX_API_KEY, "***")
    # Mask any Bearer tokens
    scrubbed = re.sub(r"(Bearer\s+)[A-Za-z0-9\-\._~+/]+=*", r"\1***", scrubbed, flags=re.IGNORECASE)
    # Mask any Google API key pattern (AIzaSy...)
    scrubbed = re.sub(r"AIzaSy[A-Za-z0-9_-]{33}", "AIzaSy***", scrubbed)
    return scrubbed


def _call(model: str, body: dict) -> dict:
    ok, why = available()
    if not ok:
        raise GeminiError(why)

    headers = {"Content-Type": "application/json"}
    params = {}
    if USE_VERTEX_API:
        url = (
            f"https://{VERTEX_LOCATION}-aiplatform.googleapis.com/v1beta1"
            f"/projects/{VERTEX_PROJECT_ID}/locations/{VERTEX_LOCATION}/publishers/google/models/{model}:generateContent"
        )
        headers.update(_get_vertex_auth_header())
    else:
        url = f"{BASE}/models/{model}:generateContent"
        params = {"key": GEMINI_API_KEY}

    r = httpx.post(
        url,
        params=params if params else None,
        headers=headers,
        json=body,
        timeout=TIMEOUT,
    )
    if not r.is_success:
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
rounded forms, clean readable silhouette, gentle studio key light from the upper left
with a soft fill, no harsh shadows, saturated but not neon colours, plain near-black background"""

PROMPT_SYSTEM = f"""You are an expert 3D art director and vision AI.
You write the single image prompt that turns somebody's rough photo into a clean 3D asset render. That render is then fed to an image-to-3D model (TRELLIS / Hunyuan3D), so you are writing for the reconstructor.

STEP 1: UNDERSTAND THE CORE CONCEPT (ACTION & ESSENCE):
First, deeply analyze what the subject is fundamentally doing, experiencing, or interacting with.
Examples:
- Action / motion: 'cheerfully sipping boba milk tea through a straw', 'curiously smelling a blooming lotus flower', 'running forward with dynamic speed', 'casting a glowing magical spell', 'peacefully resting on its paws'.
- Interaction: what is it holding, looking at, or wearing?
- Emotion & posture: playful, curious, heroic, determined, sitting upright.
Explicitly capture this in 'core_concept'.

STEP 2: IMAGE ASSESSMENT:
Evaluate the input photo:
- Does it look great and clean (clear silhouette, good lighting)?
- Or does it need cleanup (busy background, table reflections, blur, cut-off limbs, logos)?
State this in 'image_assessment' (e.g. 'Great pose and clear details; suitable for direct 3D or multi-angle generation' or 'Has background clutter and reflections; recommended to generate clearer studio concepts').

STEP 3: FIDELITY & IDENTITY PRESERVATION:
The final 3D asset MUST LOOK AS CLOSE AS POSSIBLE TO THE ORIGINAL REFERENCE PHOTO.
Users expect the exact same character/subject, not a generic reimagining.

Meticulously inspect the reference photo and explicitly describe:
1. FACIAL FEATURES & EYES (ABSOLUTELY ESSENTIAL):
   - Eye state & appearance: If eyes are wide open in the photo, explicitly mandate:
     "large, glossy, wide-open round black eyes with bright white catchlights looking directly forward (DO NOT render closed eyes, smiling slits, or winking eyes)".
     If closed in the photo, specify closed.
   - Facial expression & muzzle: mouth shape (e.g. cute open mouth sipping from straw), nose color/shape, cheeks, whiskers.
   - Exact facial geometry: round chubby face, cute ear placement and inner ear colors.

2. COLOR PATTERNS & MARKINGS:
   - Precisely map out all colors and patterns: e.g. dark charcoal patch over right eye/ear, warm ginger orange patch over left ear/forehead, creamy white chin, chest, and muzzle, banded tail.

3. POSTURE, PROPORTIONS & DETAILS:
   - Faithfully replicate the subject's exact pose and the core concept action.
   - Match limb positions, head-to-body scale, and paw details (e.g. visible pink toe beans).

4. ACCESSORIES, ATTIRE & OBJECTS:
   - Describe every accessory with exact materials, patterns, and colors (e.g. natural woven straw boater hat with red-and-white gingham checkered ribbon band, transparent cup with dark boba tapioca pearls settled at the bottom and creamy milk tea, pink drinking straw).

5. RECONSTRUCTION-SAFE CLEANUP (ONLY remove what breaks 3D geometry):
   - Background: Pure solid flat near-black background (#121212), strictly NO floor, NO table reflections, NO ground shadows, NO background clutter, NO bokeh.
   - Framing: Entire subject fully in frame with generous margin on all sides, centered, eye-level three-quarter front view.
   - Text & Branding: Remove all brand text, logos, or writing (e.g. unbranded clear cup).
   - Lighting: Soft, balanced, even studio lighting with gentle soft fill, preserving natural surface colors.

The style is fixed and you always state it: {STYLE}.

Write:
- core_concept: concise phrase describing the core action/motion/essence of the subject ('Chubby calico kitten cheerfully sipping boba milk tea through a straw').
- image_assessment: brief 1-sentence note on image quality and whether it is ready for direct 3D or needs clearer rendering.
- title: 2-4 words, name of the asset. Becomes the filename and the card label.
- subject: one clause naming the thing plainly ("a cute calico kitten drinking boba tea").
- prompt: the full image prompt, one paragraph, imperative, self-contained, incorporating the core concept, facial, eye, color, and accessory details above.
- notes: one short sentence to the user about what you kept and what background elements were removed for clean 3D reconstruction."""

PROMPT_SCHEMA = {
    "type": "object",
    "properties": {
        "core_concept": {"type": "string"},
        "image_assessment": {"type": "string"},
        "title": {"type": "string"},
        "subject": {"type": "string"},
        "prompt": {"type": "string"},
        "notes": {"type": "string"},
    },
    "required": ["core_concept", "image_assessment", "title", "subject", "prompt", "notes"],
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
def make_image(prompt: str, refs: list[Path] | None = None, aspect: str = "1:1", image_size: str | None = None, model: str | None = None) -> dict:
    """Render the concept. Returns the bytes plus what it took to get them."""
    if image_size not in (None, "1K", "2K", "4K"):
        raise ValueError("image_size must be 1K, 2K, or 4K")
    image_model = model or GEMINI_IMAGE_MODEL
    if model is not None and model != "gemini-3-pro-image":
        raise ValueError("Unknown Gemini image model")
    valid_refs = [p for p in (refs or []) if p.is_file()]
    parts: list[dict] = [_inline(p) for p in valid_refs]

    if valid_refs:
        text_content = (
            "Reference Image Fidelity: Faithfully preserve the exact visual identity, facial features, "
            "eye shape and open state (keep eyes wide open if open in reference, do NOT close eyes), "
            "expression, colors, markings, and proportions of the subject shown in the attached reference image. "
            "Render this exact subject cleanly on a flat dark background (#121212) with studio lighting for 3D reconstruction:\n\n"
            + prompt
        )
    else:
        text_content = prompt

    parts.append({"text": text_content})

    started = time.time()
    data = _call(
        image_model,
        {
            "contents": [{"role": "user", "parts": parts}],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
                "imageConfig": {"aspectRatio": aspect, **({"imageSize": image_size} if image_size else {})},
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
        "model": image_model,
        "provider": "google",
        "ms": int((time.time() - started) * 1000),
    }


def make_concept_set(
    user_prompt: str,
    image: Path | None = None,
    count: int = 4,
    base_prompt: str | None = None,
    mode: str = "angles",
    image_size: str | None = None,
    on_progress=None,
    on_image=None,
    image_model: str | None = None,
    prompt_writer=None,
    view_auditor=None,
    image_renderer=None,
) -> dict:
    """
    Generate candidate concept images (different angles or clearer studio renders) from a photo.
    Runs variations concurrently and returns the generated images with prompt metadata.
    All variations strictly preserve the subject's core concept and visual identity.
    """
    from concurrent.futures import ThreadPoolExecutor
    from tempfile import TemporaryDirectory

    renderer = make_image
    if image_model is not None and image_renderer is None:
        from .image_models import DEFAULT_MODEL
        if image_model == DEFAULT_MODEL:
            from functools import partial
            renderer = partial(make_image, model=image_model)
        else:
            raise ValueError("Unknown image model")

    if image_renderer is not None:
        renderer = image_renderer

    count = max(1, min(4, count))
    t0 = time.time()
    if on_progress:
        on_progress("analyzing_reference", 0, count, {})
    if mode == "reference":
        if image is None or not image.is_file():
            raise ValueError("Reference generation requires an image")
        # Use the user's actual instructions and original image, without a planner
        # rewriting their appearance or imposing the project's default style.
        base_prompt = user_prompt.strip() or "Create a polished game character concept from this reference."
    if base_prompt:
        prompt_text = base_prompt
        title = "Concept Asset"
        subject = ""
        notes = "Rendered from existing prompt."
        core_concept = ""
        image_assessment = ""
    else:
        written = (prompt_writer or write_prompt)(user_prompt, image)
        prompt_text = written["prompt"]
        title = written.get("title", "Concept Asset")
        subject = written.get("subject", "")
        notes = written.get("notes", "")
        core_concept = written.get("core_concept", "")
        image_assessment = written.get("image_assessment", "")

    metadata = {"title": title, "subject": subject, "core_concept": core_concept,
                "image_assessment": image_assessment, "prompt": prompt_text, "notes": notes}
    image_options = {"image_size": image_size} if image_size else {}

    # A shared canonical image anchors proportions/materials across views.
    # Independent text-to-image variations frequently change pose and markings.
    views = [
        ("Front · 0°", "front", "camera directly in front at eye level, zero azimuth"),
        ("Back · 180°", "back", "camera directly behind at eye level, 180 degree azimuth; show the BACK, no face visible unless physically turned backward"),
        ("Left · 90°", "left", "camera looking at the subject's LEFT side at eye level, exact side profile"),
        ("Right · 270°", "right", "camera looking at the subject's RIGHT side at eye level, opposite side profile"),
    ][:count]
    if mode == "clear":
        views = [("Clean studio view", None, "preserve the reference camera angle")]

    if mode == "reference":
        views = [(f"Concept {i + 1}", None, "preserve the original camera angle") for i in range(count)]

    def view_prompt(camera: str) -> str:
        if mode == "reference":
            return (
                "Create ONE concept image from the attached original reference. "
                "Follow the user's requested changes below. Preserve all unmentioned features: "
                "recognizable identity, face, proportions, pose, camera angle, colors, markings, "
                "clothing and accessories. Do not force a cartoon style, invent accessories, "
                "or produce a turnaround/grid. Keep the complete subject clearly visible with "
                "soft neutral lighting and a simple pale background suitable for a 3D reference. "
                "Explicit user changes take priority over preservation.\nUser instructions: " + prompt_text
            )
        return (
            f"Subject description: {prompt_text}\n\n"
            "TURNAROUND CAMERA CONTRACT (overrides any camera, pose or gaze instructions above): "
            f"{camera}. Orthographic camera, fixed focal scale, full subject occupying about 80% "
            "of image height with all extremities in frame. Output exactly ONE view, never a grid. "
            "Rotate ONLY the camera around the same frozen object. Do not rotate its head, "
            "move eyes to face the camera, change pose, swap left/right markings, move accessories, "
            "change object spacing, or redesign any part. Match the first reference's geometry, "
            "proportions, textures and silhouette. Preserve visibility and occlusion naturally. "
            "Flat #121212 background, no floor, no cast shadow, even diffuse neutral lighting, "
            "no depth of field, no text, no added texture detail. Infer hidden surfaces conservatively."
        )

    refs = [p for p in (image,) if p and p.is_file()]
    results: list[dict] = []
    warnings: list[str] = []
    label, direction, camera = views[0]
    if on_progress:
        on_progress("rendering_canonical", 0, len(views), metadata)
    canonical = renderer(view_prompt(camera), refs=refs, **image_options)
    first = {"label": label, "direction": direction, **canonical}
    if on_image:
        on_image(first, metadata)
    results.append(first)
    if on_progress:
        on_progress("rendering_views", 1, len(views), metadata)
    with TemporaryDirectory(prefix="rodin-turnaround-") as tmp:
        anchor = Path(tmp) / ("canonical.png" if "png" in canonical["mime"] else "canonical.jpg")
        anchor.write_bytes(canonical["bytes"])

        def render_view(view: tuple) -> dict:
            label, direction, camera = view
            made = renderer(view_prompt(camera), refs=refs if mode == "reference" else [anchor], **image_options)
            return {"label": label, "direction": direction, **made}

        with ThreadPoolExecutor(max_workers=3) as ex:
            futures = [(view, ex.submit(render_view, view)) for view in views[1:]]
            for view, future in futures:
                try:
                    item = future.result()
                    if on_image:
                        on_image(item, metadata)
                    results.append(item)
                    if on_progress:
                        on_progress("rendering_views", len(results), len(views), metadata)
                except Exception:
                    # A missing side is missing, never relabel the next success.
                    warnings.append(f"{view[0]} could not be generated; review the remaining views.")

    if on_progress:
        on_progress("validating_views", len(results), len(views), metadata)
    validation = {"usable": False, "issues": ["Only one view is available."]}
    if mode == "reference":
        validation = {"usable": False, "issues": []}
    if len(results) > 1 and mode != "reference":
        try:
            with TemporaryDirectory(prefix="rodin-view-check-") as tmp:
                paths = []
                for i, item in enumerate(results):
                    path = Path(tmp) / (f"{i}.png" if "png" in item["mime"] else f"{i}.jpg")
                    path.write_bytes(item["bytes"])
                    paths.append(path)
                validation = (view_auditor or assess_turnaround)(paths, [item["direction"] for item in results])
        except Exception:
            validation = {"usable": False, "issues": ["View consistency could not be verified. Use a single view."]}
    if not validation["usable"]:
        warnings.extend(validation["issues"])


    return {
        "title": title,
        "subject": subject,
        "core_concept": core_concept,
        "image_assessment": image_assessment,
        "prompt": prompt_text,
        "notes": notes,
        "images": results,
        "warnings": warnings,
        "validation": validation,
        "total_ms": int((time.time() - t0) * 1000),
    }


def turnaround_instructions(directions: list[str]) -> str:
    return (
        "Audit these proposed multi-view references for image-to-3D reconstruction. "
        "Image 0 is the canonical front. The others claim these directions in order: "
        + ", ".join(directions) + ". "
        "Approve ONLY if every image is a plausible rigid camera rotation around the ENTIRE same frozen scene. "
        "Check camera angle, relative object positions, occlusion, pose, facial identity, markings and accessories. "
        "A rotated person on an unchanged front-facing sofa is INVALID. A rear view that shows seated bodies "
        "through a sofa back is INVALID. Objects must occlude one another naturally from the new camera. "
        "Do not approve merely because the subject/style looks similar. Reject uncertain sets. "
        "Return usable (boolean) and issues (short English explanations). This is a visual consistency check, "
        "not proof of the real unseen back of the object."
    )


def assess_turnaround(paths: list[Path], directions: list[str]) -> dict:
    """Conservative vision gate: claimed camera labels are not evidence of valid views."""
    parts = [{"text": turnaround_instructions(directions)}]
    parts.extend(_inline(p) for p in paths)
    data = _call(GEMINI_TEXT_MODEL, {
        "contents": [{"role": "user", "parts": parts}],
        "generationConfig": {"responseMimeType": "application/json", "responseSchema": {
            "type": "object", "properties": {"usable": {"type": "boolean"},
                "issues": {"type": "array", "items": {"type": "string"}}},
            "required": ["usable", "issues"],
        }},
    })
    import json
    parts_out = ((data.get("candidates") or [{}])[0].get("content") or {}).get("parts") or []
    raw = json.loads(next(p["text"] for p in parts_out if p.get("text")))
    if type(raw.get("usable")) is not bool or not isinstance(raw.get("issues"), list):
        raise GeminiError("Invalid turnaround assessment")
    return {"usable": raw["usable"] and not raw["issues"], "issues": [str(x) for x in raw["issues"]]}
