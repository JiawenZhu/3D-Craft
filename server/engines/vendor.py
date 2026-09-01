"""Put the vendored upstream repos on sys.path when they have been cloned."""
from __future__ import annotations

import sys
from pathlib import Path

from ..config import REPOS

# repo dir -> the subdirectory that holds the importable package
VENDORED = {
    "Hunyuan3D-2.1": ["hy3dshape", "hy3dpaint"],
    "TRELLIS": ["."],
}


def bootstrap() -> list[str]:
    """Prepend every vendored package root; returns what was added."""
    added: list[str] = []
    for repo, subs in VENDORED.items():
        base = REPOS / repo
        if not base.is_dir():
            continue
        for sub in subs:
            p = (base / sub).resolve()
            if p.is_dir() and str(p) not in sys.path:
                sys.path.insert(0, str(p))
                added.append(str(p))
    return added


bootstrap()
