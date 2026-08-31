"""
Client bridge for Tencent Hunyuan3D-2.1
Supports Hugging Face Spaces Gradio Client and local model pipelines.
"""

from gradio_client import Client
import os
import tempfile

class Hunyuan3DClient:
    def __init__(self, space_id: str = "tencent/Hunyuan3D-2.1"):
        self.space_id = space_id
        self._client = None

    def _get_client(self):
        if not self._client:
            try:
                self._client = Client(self.space_id)
            except Exception as e:
                print(f"[Hunyuan3DClient] Warning: Could not connect to Space {self.space_id}: {e}")
        return self._client

    def generate_from_text(self, prompt: str, steps: int = 50, seed: int = 42) -> str:
        """
        Synthesizes 3D mesh (.glb) from a natural language text prompt.
        """
        client = self._get_client()
        if not client:
            raise RuntimeError("Hunyuan3D Space client not connected")
        
        result = client.predict(
            prompt=prompt,
            num_inference_steps=steps,
            seed=seed,
            api_name="/text_to_3d"
        )
        return result

    def generate_from_image(self, image_path: str, texture_res: int = 4096) -> str:
        """
        Synthesizes 3D character mesh (.glb) from a single 2D concept image.
        """
        client = self._get_client()
        if not client:
            raise RuntimeError("Hunyuan3D Space client not connected")
        
        result = client.predict(
            image=image_path,
            texture_size=texture_res,
            api_name="/image_to_3d"
        )
        return result
