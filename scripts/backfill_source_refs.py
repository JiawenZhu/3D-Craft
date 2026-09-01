#!/usr/bin/env python
"""
Link existing assets back to the inbox image they were generated from.

Assets created before source_ref existed have no link, so their gallery card
cannot show the 3D badge. Inputs are re-encoded on the way in, so hashes do not
survive — but the prepped filename keeps the original stem
(`<uuid>_<stem>_prep.png`), which is enough to recover the link.

Also prunes storage directories left behind by failed jobs.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from server.config import INBOX, STORAGE  # noqa: E402

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".avif"}


# stem -> inbox path
inbox_by_stem: dict[str, str] = {}
for p in INBOX.rglob("*"):
    if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES:
        inbox_by_stem[p.stem] = f"/inbox/{p.relative_to(INBOX).as_posix()}"


def original_stem(prepped: Path) -> str:
    """`3f2a10bb_gold_paladin_prep.png` -> `gold_paladin`."""
    stem = prepped.stem
    if stem.endswith("_prep"):
        stem = stem[: -len("_prep")]
    head, _, tail = stem.partition("_")
    # strip the 8-char upload id we prefix on the way in
    return tail if len(head) == 8 and all(c in "0123456789abcdef" for c in head) else stem

index_path = STORAGE / "assets.json"
if not index_path.exists():
    print("no assets yet")
    raise SystemExit(0)

assets = json.loads(index_path.read_text())
linked = 0
for a in assets:
    if a.get("sourceRef"):
        continue
    for prepped in sorted((STORAGE / a["id"] / "input").glob("*")):
        ref = inbox_by_stem.get(original_stem(prepped))
        if ref:
            a["sourceRef"] = ref
            linked += 1
            print(f"  linked  {a['id']}  {a['name'][:32]:34} -> {ref}")
            break

index_path.write_text(json.dumps(assets, indent=1))
remaining = sum(1 for a in assets if not a.get("sourceRef"))
print(f"\nlinked {linked}, {remaining} still unlinked (generated from an upload, not the gallery)")

# storage dirs with no mesh are leftovers from failed jobs
known = {a["id"] for a in assets}
pruned = 0
for d in STORAGE.iterdir():
    if d.is_dir() and d.name.startswith("a-") and d.name not in known and not (d / "model.glb").exists():
        import shutil

        shutil.rmtree(d, ignore_errors=True)
        pruned += 1
if pruned:
    print(f"pruned {pruned} orphaned director{'y' if pruned == 1 else 'ies'} from failed jobs")
