"""Explicit image renderers; configuration readiness is not entitlement proof."""
from . import gemini

DEFAULT_MODEL = "gemini-3-pro-image"
CODEX_MODEL = "codex-gpt-image-2"
MODEL_IDS = (DEFAULT_MODEL, CODEX_MODEL)


def catalog(account: dict | None = None) -> dict:
    account = account or {}
    models = []
    for ident, name, provider, quality, size, ready, reason in [
        (DEFAULT_MODEL, "Gemini 3 Pro Image", "google", "Pro", "2K", bool(gemini.GEMINI_API_KEY), "Configure Gemini image generation on the studio server"),
        (CODEX_MODEL, "GPT Image 2 · ChatGPT account", "chatgpt", "Account default", "Native", bool(account.get("connected") and account.get("imageGenerationSupported")), account.get("imageGenerationReason") or "Connect your own ChatGPT account in Profile"),
    ]:
        models.append({"id": ident, "name": name, "provider": provider, "quality": quality, "imageSize": size,
                       "available": ready, "unavailableReason": None if ready else reason})
    return {"models": models, "defaultModel": DEFAULT_MODEL}


def require_available(ident: str, account: dict | None = None) -> dict:
    model = next((item for item in catalog(account)["models"] if item["id"] == ident), None)
    if model is None:
        raise ValueError("Unknown image model")
    if not model["available"]:
        raise RuntimeError(model["unavailableReason"])
    return model
