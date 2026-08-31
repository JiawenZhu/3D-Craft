# Local Deployment & Inference Setup

Rodin 3D Studio can run entirely locally against on-premise GPUs (NVIDIA CUDA or Apple Silicon MPS) or connect directly to Hugging Face Spaces via Gradio API.

---

## 1. System Requirements

- **GPU**: NVIDIA RTX 3080/4080/4090 (16GB+ VRAM recommended) or Apple Silicon M2/M3/M4 Max/Ultra (32GB+ Unified Memory).
- **RAM**: 32 GB System RAM.
- **Disk**: 40 GB SSD storage for model weights.

---

## 2. Quickstart Frontend & Local Server

```bash
# 1. Install frontend dependencies
cd /Users/jiawenzhu/Developer/rodin-3d-studio
npm install

# 2. Start Vite 3D Studio interface
npm run dev

# 3. Start Python API server (in separate terminal)
python3 -m venv venv
source venv/bin/activate
pip install -r server/requirements.txt
python server/app.py
```

---

## 3. Connecting to Hugging Face Spaces

The studio is pre-configured with zero-configuration client bridges that connect seamlessly to the live Hugging Face Spaces endpoints:

- **Hunyuan3D-2.1**: `tencent/Hunyuan3D-2.1`
- **Microsoft TRELLIS.2**: `microsoft/TRELLIS.2`

You can also pass your own private Hugging Face User Access Token via `.env`:
```bash
HF_TOKEN=hf_your_access_token_here
```
