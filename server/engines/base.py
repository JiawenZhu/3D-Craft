"""Engine contract shared by the Hunyuan3D, TRELLIS and hybrid backends."""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Protocol


@dataclass
class GenRequest:
    """One generation, already normalised out of the UI's settings payload."""
    prompt: str = ""
    negative_prompt: str = ""
    images: list[Path] = field(default_factory=list)
    directions: list[str] = field(default_factory=list)
    seed: int | None = None
    steps: int = 50
    guidance: float = 7.5
    target_faces: int = 40_000
    texture: bool = True
    quad_remesh: bool = False
    remove_background: bool = True
    effort: str = "high"
    quality: str = "default"
    batch: int = 1
    geo_mode: str = "sharp"
    pose_mode: str = "none"

    @property
    def is_text(self) -> bool:
        return not self.images and bool(self.prompt.strip())


@dataclass
class GenResult:
    """Files an engine produced, plus whatever it can tell us about them."""
    mesh_path: Path
    splat_path: Path | None = None
    thumb_path: Path | None = None
    provider: str = "local"
    note: str = ""


# stage id, 0..1 progress within the run, human message
Progress = Callable[[str, float, str], None]


class Engine(Protocol):
    id: str
    label: str

    def status(self) -> dict:
        """`{installed, loaded, note, provider}` — cheap, no model loading."""
        ...

    def generate(self, req: GenRequest, out_dir: Path, on: Progress) -> GenResult:
        ...
