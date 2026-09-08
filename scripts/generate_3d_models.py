import os
import urllib.request
from pathlib import Path
from dotenv import load_dotenv
import fal_client

root_dir = Path(__file__).resolve().parent.parent
load_dotenv(root_dir / ".env")

explore_dir = root_dir / "public" / "images" / "explore"
models_dir = root_dir / "public" / "models"
models_dir.mkdir(parents=True, exist_ok=True)

TARGETS = [
    {
        "name": "Fairytale Wooden Cottage",
        "image": "rodin_clean_cottage_1788235864897.jpg",
        "output": "fairytale_cottage.glb"
    },
    {
        "name": "Bright Yellow Mini Vintage Car",
        "image": "rodin_clean_taxi_1788235881061.jpg",
        "output": "yellow_mini_car.glb"
    },
    {
        "name": "Baby Emerald Dragon",
        "image": "rodin_clean_dragon_1788235904609.jpg",
        "output": "baby_emerald_dragon.glb"
    },
    {
        "name": "Chibi Wizard Apprentice",
        "image": "rodin_clean_wizard.jpg",
        "output": "chibi_wizard.glb"
    },
    {
        "name": "Spherical Robot Companion",
        "image": "rodin_clean_mech.jpg",
        "output": "spherical_robot.glb"
    },
    {
        "name": "Japanese Ramen Stall Counter",
        "image": "rodin_clean_ramen.jpg",
        "output": "ramen_stall.glb"
    },
    {
        "name": "Calico Boba Milk Tea Cat",
        "image": "rodin_boba_cat_1788235650982.jpg",
        "output": "boba_cat.glb"
    },
    {
        "name": "Chibi Lunar Explorer Astronaut",
        "image": "rodin_chibi_astronaut_1788235666098.jpg",
        "output": "chibi_astronaut.glb"
    },
    {
        "name": "Glowing Magma Volcanic Cube",
        "image": "rodin_magma_cube_1788231853691.jpg",
        "output": "magma_cube.glb"
    },
    {
        "name": "Fantasy Castle Watchtower",
        "image": "rodin_castle_tower_1788231881399.jpg",
        "output": "castle_tower.glb"
    }
]

def download_file(url: str, dest: Path):
    print(f"  ⬇️ Downloading GLB from {url[:45]}... to {dest.name}")
    urllib.request.urlretrieve(url, dest)
    print(f"  ✅ Saved {dest.name} ({round(dest.stat().st_size / 1024 / 1024, 2)} MB)")

def generate_one(target):
    img_path = explore_dir / target["image"]
    out_path = models_dir / target["output"]

    if out_path.exists() and out_path.stat().st_size > 10000:
        print(f"⏭️ {target['output']} already exists, skipping.")
        return True

    print(f"\n🚀 [3D Synthesis] Generating {target['name']} ({target['output']})...")
    print(f"  📤 Uploading {img_path.name} to fal storage...")
    uploaded_url = fal_client.upload_file(str(img_path))
    print(f"  ✨ Calling fal-ai/trellis with image URL...")

    res = fal_client.subscribe(
        "fal-ai/trellis",
        arguments={
            "image_url": uploaded_url,
            "texture_size": 1024,
            "mesh_simplify": 0.95
        }
    )

    mesh_url = res.get("model_mesh", {}).get("url")
    if not mesh_url:
        print(f"  ❌ No mesh URL returned: {res}")
        return False

    download_file(mesh_url, out_path)
    return True

if __name__ == "__main__":
    for item in TARGETS:
        try:
            generate_one(item)
        except Exception as e:
            print(f"  ❌ Error for {item['name']}: {e}")
