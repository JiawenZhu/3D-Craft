"""Copy exact Explore meshes into the Godot source tree with provenance."""
import hashlib
import json
import shutil
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
NAMES = ['retro_camper_van','yellow_mini_car','spherical_robot','boba_cat','castle_tower','fairytale_cottage','magma_cube','baby_emerald_dragon','lantern_cat']
out=ROOT/'games/forma-playground/assets'
out.mkdir(parents=True,exist_ok=True)
manifest=[]
for name in NAMES:
    source=ROOT/'public/models'/f'{name}.glb'
    target=out/source.name
    if not target.exists() or hashlib.sha256(target.read_bytes()).digest()!=hashlib.sha256(source.read_bytes()).digest():
        shutil.copyfile(source,target)
    manifest.append({'id':name,'source':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'bytes':source.stat().st_size})
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Prepared {len(manifest)} existing Explore GLBs')
