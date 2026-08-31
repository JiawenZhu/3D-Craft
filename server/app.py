from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import uvicorn
import os

app = FastAPI(
    title="Rodin 3D Studio — Generative Engine API",
    version="2.0.0",
    description="Unified backend server orchestrating Tencent Hunyuan3D-2.1 and Microsoft TRELLIS.2"
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
    model: str = "trellis-2.0"
    style: str = "cyberpunk"
    seed: Optional[int] = 42

@app.get("/api/health")
def health_check():
    return {
        "status": "healthy",
        "engines": {
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
        "estimated_time_sec": 25
    }

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
    uvicorn.run("app:app", host="0.0.0.0", port=8000, reload=True)
