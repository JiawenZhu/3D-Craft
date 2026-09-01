"""Engine registry."""
from __future__ import annotations

from .base import GenRequest, GenResult, Progress  # noqa: F401
from .hunyuan import HunyuanEngine
from .hybrid import HybridEngine
from .rodin import RodinEngine
from .trellis import TrellisEngine

_hunyuan = HunyuanEngine()
_trellis = TrellisEngine()
_hybrid = HybridEngine(_trellis, _hunyuan)
_rodin = RodinEngine()

ENGINES = {e.id: e for e in (_hunyuan, _trellis, _rodin, _hybrid)}


def get(engine_id: str):
    if engine_id not in ENGINES:
        raise KeyError(f"unknown engine {engine_id!r}; have {sorted(ENGINES)}")
    return ENGINES[engine_id]


def status_all() -> dict:
    return {eid: e.status() for eid, e in ENGINES.items()}
