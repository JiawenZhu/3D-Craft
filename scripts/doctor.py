#!/usr/bin/env python
"""Report exactly what this machine can run, and how."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

GREEN, YELLOW, RED, DIM, OFF = "\033[32m", "\033[33m", "\033[31m", "\033[2m", "\033[0m"


def line(ok: bool | None, label: str, detail: str = "") -> None:
    mark = {True: f"{GREEN}✓{OFF}", False: f"{RED}✗{OFF}", None: f"{YELLOW}•{OFF}"}[ok]
    print(f"  {mark} {label:<26} {DIM}{detail}{OFF}")


print("\nRodin 3D Studio — environment\n")

print(" runtime")
line(True, "python", sys.version.split()[0])
try:
    import torch

    dev = ("cuda" if torch.cuda.is_available()
           else "mps" if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available()
           else "cpu")
    line(True, "torch", f"{torch.__version__} · {dev}")
except ImportError:
    line(None, "torch", "not installed — ./scripts/setup.sh --local")

for mod in ("fastapi", "gradio_client", "trimesh", "fal_client"):
    try:
        __import__(mod)
        line(True, mod)
    except ImportError:
        line(False, mod, "run ./scripts/setup.sh")

print("\n engines")
try:
    from server import engines

    for eid, st in engines.status_all().items():
        line(st["installed"], f"{eid}", f"provider={st['provider']} · {st['note']}")
except Exception as exc:
    line(False, "registry", f"{type(exc).__name__}: {exc}")

print("\n fal.ai")
try:
    from server.engines import fal_api
    ok, why = fal_api.available()
    line(ok, "FAL_KEY", "set" if ok else why)
    if ok:
        from server.config import FAL_ENDPOINTS, FAL_PRICES
        for eid, ep in FAL_ENDPOINTS.items():
            price = FAL_PRICES.get(eid)
            line(True, eid, f"{ep}" + (f" · ${price:.2f}/gen" if price else ""))
except Exception as exc:
    line(False, "fal provider", f"{type(exc).__name__}: {exc}")

print("\n hosted spaces")
try:
    import requests

    for name, url in [
        ("tencent/Hunyuan3D-2.1", "https://tencent-hunyuan3d-2-1.hf.space/info"),
        ("microsoft/TRELLIS.2", "https://microsoft-trellis-2.hf.space/gradio_api/info"),
    ]:
        try:
            r = requests.get(url, timeout=20)
            line(r.ok, name, f"HTTP {r.status_code}")
        except Exception as exc:
            line(False, name, f"{type(exc).__name__}")
except ImportError:
    line(False, "requests", "run ./scripts/setup.sh")

print("\n weights")
from server.config import WEIGHTS  # noqa: E402

for name, sub in [("Hunyuan3D-2.1", "hunyuan3d-2.1"), ("TRELLIS-image-large", "trellis-image-large")]:
    p = WEIGHTS / sub
    if p.exists():
        size = sum(f.stat().st_size for f in p.rglob("*") if f.is_file()) / 2**30
        line(True, name, f"{size:.1f} GB at {p}")
    else:
        line(None, name, "not downloaded — ./scripts/setup.sh --weights")
print()
