import os
import json
import fal_client
from pathlib import Path
from dotenv import load_dotenv

# Load .env
root_dir = Path(__file__).resolve().parent.parent
load_dotenv(root_dir / ".env")

print("🔑 Testing FAL_KEY:", os.environ.get("FAL_KEY")[:8] + "..." if os.environ.get("FAL_KEY") else "None")

def test_pipeline():
    # Step 1: Generate high quality 2D concept art using Flux Schnell on fal.ai
    prompt = (
        "Full body futuristic cyberpunk robotic assassin warrior in obsidian carbon armor, "
        "glowing cyan neon energy trim, photon katana, dynamic heroic stance, "
        "ultra-clean white background, 3D character design turnaround, hyper-detailed, octane render 8k"
    )
    print(f"\n🎨 Step 1: Generating 2D concept art with Flux Schnell on fal.ai...")
    print(f"Prompt: {prompt}")

    flux_result = fal_client.subscribe(
        "fal-ai/flux/schnell",
        arguments={
            "prompt": prompt,
            "image_size": "square_hd",
            "num_inference_steps": 4,
            "seed": 42
        },
        with_logs=True
    )
    
    image_url = flux_result["images"][0]["url"]
    print(f"✅ 2D Concept Art generated successfully!")
    print(f"Image URL: {image_url}")

    # Step 2: Feed into Microsoft TRELLIS on fal.ai
    print(f"\n🧠 Step 2: Synthesizing 3D Model with fal-ai/trellis...")
    
    def on_trellis_update(update):
        if hasattr(update, "logs") and update.logs:
            for log in update.logs:
                print(f"  [Trellis Log] {log.get('message', '')}")

    trellis_result = fal_client.subscribe(
        "fal-ai/trellis",
        arguments={
            "image_url": image_url,
            "ss_sampling_steps": 12,
            "slat_sampling_steps": 12,
            "mesh_simplify": 0.95,
            "texture_size": 1024
        },
        with_logs=True,
        on_queue_update=on_trellis_update
    )

    print("\n🎉 Step 3: 3D Generation Complete!")
    print(json.dumps(trellis_result, indent=2))
    
    # Save output metadata
    output_file = root_dir / "fal_trellis_output.json"
    with open(output_file, "w") as f:
        json.dump({
            "concept_image_url": image_url,
            "trellis_result": trellis_result
        }, f, indent=2)
    print(f"\nSaved output info to {output_file}")

if __name__ == "__main__":
    test_pipeline()
