import os
import json
import urllib.request
import fal_client
from pathlib import Path
from dotenv import load_dotenv

root_dir = Path(__file__).resolve().parent.parent
load_dotenv(root_dir / ".env")

gallery_dir = root_dir / "public" / "images" / "gallery"
gallery_dir.mkdir(parents=True, exist_ok=True)

ITEMS = [
  {
    "id": "item-clean-wizard",
    "title": "Chibi Wizard Apprentice",
    "filename": "rodin_clean_wizard.jpg",
    "prompt": "A clean isolated 3D character model render of a cute chibi wizard apprentice child wearing deep indigo robes with golden starry embroidery and a tall wizard hat, holding a wooden staff with a glowing cyan crystal orb, isolated on pure solid black studio background, no background clutter, soft rim lighting, Pixar 3D style 8k"
  },
  {
    "id": "item-clean-mech",
    "title": "Cute Robot Companion",
    "filename": "rodin_clean_mech.jpg",
    "prompt": "A clean isolated 3D character model render of a cute spherical white robot companion with glowing cyan digital eye screen, brass antenna, magnetic floating hands, isolated on pure solid black studio background, no background elements, studio rim lighting, 3D asset render 8k"
  },
  {
    "id": "item-clean-ramen",
    "title": "Miniature Ramen Stall",
    "filename": "rodin_clean_ramen.jpg",
    "prompt": "A clean isolated 3D diorama model render of a miniature Japanese ramen counter food stall with red lanterns and steaming bowls on round wooden base, isolated on pure solid black studio background, no background clutter, octane render 8k"
  }
]

def download_file(url: str, dest: Path):
    urllib.request.urlretrieve(url, dest)

def generate_clean():
    print(f"🚀 Generating clean isolated 3D images with fal.ai Flux...")
    for item in ITEMS:
        dest_path = gallery_dir / item["filename"]
        print(f"Generating: {item['title']}...")
        try:
            res = fal_client.subscribe(
                "fal-ai/flux/schnell",
                arguments={
                    "prompt": item["prompt"],
                    "image_size": "square_hd",
                    "num_inference_steps": 4,
                    "seed": 100
                }
            )
            img_url = res["images"][0]["url"]
            download_file(img_url, dest_path)
            print(f"  ✅ Saved to {dest_path.name}")
        except Exception as e:
            print(f"  ❌ Error: {e}")

if __name__ == "__main__":
    generate_clean()
