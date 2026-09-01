"""
fal.ai Trellis 3D Generative Bridge
Direct API integration for Microsoft TRELLIS Image-to-3D via fal.ai serverless endpoints.
"""

import os
from typing import Optional, Dict, Any

class FalTrellisClient:
    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.environ.get("FAL_KEY")
        if self.api_key:
            os.environ["FAL_KEY"] = self.api_key

    def is_configured(self) -> bool:
        return bool(os.environ.get("FAL_KEY"))

    def generate_from_image(self, image_url: str) -> Dict[str, Any]:
        """
        Submits an image to fal-ai/trellis and returns the 3D model (GLB) & Gaussian Splats.
        """
        if not self.is_configured():
            raise RuntimeError("FAL_KEY environment variable is not set. Please configure .env or export FAL_KEY.")

        try:
            import fal_client

            def on_queue_update(update):
                if hasattr(update, "logs"):
                    for log in update.logs:
                        print(f"[fal-ai/trellis] {log.get('message', '')}")

            result = fal_client.subscribe(
                "fal-ai/trellis",
                arguments={
                    "image_url": image_url
                },
                with_logs=True,
                on_queue_update=on_queue_update
            )
            return result
        except ImportError:
            print("[FalTrellisClient] fal-client package not installed. Using direct HTTP API fallback.")
            import urllib.request
            import json

            req = urllib.request.Request(
                "https://queue.fal.run/fal-ai/trellis",
                data=json.dumps({"image_url": image_url}).encode("utf-8"),
                headers={
                    "Authorization": f"Key {os.environ.get('FAL_KEY')}",
                    "Content-Type": "application/json"
                }
            )
            with urllib.request.urlopen(req) as resp:
                return json.loads(resp.read().decode("utf-8"))
