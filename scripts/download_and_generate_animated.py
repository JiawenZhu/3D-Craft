import os
import json
import urllib.request
import fal_client
from pathlib import Path
from dotenv import load_dotenv

root_dir = Path(__file__).resolve().parent.parent
load_dotenv(root_dir / ".env")

models_dir = root_dir / "public" / "models"
images_dir = root_dir / "public" / "images"
models_dir.mkdir(parents=True, exist_ok=True)
images_dir.mkdir(parents=True, exist_ok=True)

def download_file(url: str, dest: Path):
    print(f"📥 Downloading {url} -> {dest}")
    urllib.request.urlretrieve(url, dest)
    print(f"✅ Saved ({dest.stat().st_size} bytes)")

def run_animated_pipeline():
    # 1. Download the first generated Cyber Samurai
    with open(root_dir / "fal_trellis_output.json") as f:
        first_data = json.load(f)
    
    download_file(first_data["concept_image_url"], images_dir / "cyber_samurai.jpg")
    download_file(first_data["trellis_result"]["model_mesh"]["url"], models_dir / "cyber_samurai.glb")

    # 2. Generate an animated/stylized character
    anime_prompt = (
        "Full body anime stylized celestial crystal sorceress, magical flowing twin tails, "
        "glowing crystal catalyst orb, gold filigree trim, dynamic floating pose, "
        "clean white studio background, Genshin Impact style 3D game model concept turnaround, vibrant colors 8k"
    )
    print(f"\n✨ Generating Animated Stylized Concept Art with Flux...")
    anime_flux = fal_client.subscribe(
        "fal-ai/flux/schnell",
        arguments={
            "prompt": anime_prompt,
            "image_size": "square_hd",
            "num_inference_steps": 4,
            "seed": 108
        }
    )
    anime_img_url = anime_flux["images"][0]["url"]
    download_file(anime_img_url, images_dir / "crystal_sorceress.jpg")

    # 3. Synthesize 3D with Trellis
    print(f"\n🧠 Synthesizing 3D Crystal Sorceress with fal-ai/trellis...")
    anime_trellis = fal_client.subscribe(
        "fal-ai/trellis",
        arguments={
            "image_url": anime_img_url,
            "ss_sampling_steps": 12,
            "slat_sampling_steps": 12,
            "mesh_simplify": 0.95,
            "texture_size": 1024
        },
        with_logs=True
    )
    anime_glb_url = anime_trellis["model_mesh"]["url"]
    download_file(anime_glb_url, models_dir / "crystal_sorceress.glb")

    print("\n🎉 Both 3D assets successfully generated and stored locally in public/models/!")

if __name__ == "__main__":
    run_animated_pipeline()
