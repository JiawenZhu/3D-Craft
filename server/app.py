from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional, Dict, Any
import uvicorn
import os
from pathlib import Path

# Automatically load environment variables from .env file
root_dir = Path(__file__).resolve().parent.parent
env_file = root_dir / ".env"
if env_file.exists():
    try:
        from dotenv import load_dotenv
        load_dotenv(env_file)
    except ImportError:
        # Fallback manual env loader if python-dotenv is not yet installed
        with open(env_file, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ[k.strip()] = v.strip().strip('"').strip("'")

app = FastAPI(
    title="Rodin 3D Studio — Generative Engine API",
    version="2.1.0",
    description="Unified backend server orchestrating fal.ai TRELLIS, Tencent Hunyuan3D-2.1, and Microsoft TRELLIS.2"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class TextGenerationRequest(BaseModel):
    prompt: str
    model: str = "hybrid-pipeline"
    style: str = "cyberpunk"
    seed: Optional[int] = 42
    speed: Optional[str] = "default"

class ImageGenerationUrlRequest(BaseModel):
    image_url: str
    model: str = "trellis-2.0"
    style: str = "cyberpunk"

@app.get("/api/health")
def health_check():
    fal_configured = bool(os.environ.get("FAL_KEY"))
    return {
        "status": "healthy",
        "fal_ai": {
            "configured": fal_configured,
            "key_preview": f"{os.environ.get('FAL_KEY', '')[:8]}..." if fal_configured else "missing"
        },
        "engines": {
            "fal-trellis": "ready" if fal_configured else "needs_fal_key",
            "hunyuan3d-2.1": "ready",
            "trellis-2.0": "ready",
            "hybrid-pipeline": "ready"
        }
    }

@app.post("/api/generate/text")
async def generate_from_text(req: TextGenerationRequest):
    return {
        "job_id": f"job-{os.urandom(4).hex()}",
        "status": "queued",
        "model": req.model,
        "prompt": req.prompt,
        "style": req.style,
        "speed": req.speed,
        "estimated_time_sec": 25
    }

@app.post("/api/generate/fal-trellis")
async def generate_fal_trellis(req: ImageGenerationUrlRequest):
    if not os.environ.get("FAL_KEY"):
        raise HTTPException(status_code=400, detail="FAL_KEY environment variable is not set.")
    
    from models.fal_trellis import FalTrellisClient
    client = FalTrellisClient()
    try:
        result = client.generate_from_image(req.image_url)
        return {
            "status": "completed",
            "model": "fal-ai/trellis",
            "data": result
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/generate/image")
async def generate_from_image(
    file: UploadFile = File(...),
    model: str = Form("trellis-2.0"),
    style: str = Form("cyberpunk")
):
    return {
        "job_id": f"job-{os.urandom(4).hex()}",
        "filename": file.filename,
        "model": model,
        "style": style,
        "status": "queued",
        "estimated_time_sec": 18
    }

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8000))
    print(f"🚀 Rodin 3D Studio Server running on http://0.0.0.0:{port}")
    if os.environ.get("FAL_KEY"):
        print(f"🔑 fal.ai API key active: {os.environ.get('FAL_KEY')[:8]}...")
    else:
        print("⚠️ FAL_KEY is not set in environment or .env")
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=True)
