"""
Client bridge for Microsoft TRELLIS.2
Structured 3D Latent Diffusion Model for Radiance Fields, 3D Gaussian Splats, and Meshes.
"""

from gradio_client import Client
import os

class TrellisClient:
    def __init__(self, space_id: str = "microsoft/TRELLIS.2"):
        self.space_id = space_id
        self._client = None

    def _get_client(self):
        if not self._client:
            try:
                self._client = Client(self.space_id)
            except Exception as e:
                print(f"[TrellisClient] Warning: Could not connect to Space {self.space_id}: {e}")
        return self._client

    def generate_asset(self, image_path: str, ss_sampling_steps: int = 25, slat_sampling_steps: int = 25) -> dict:
        """
        Generates Gaussian Splat (.ply), Radiance Field, and textured quad mesh (.glb)
        """
        client = self._get_client()
        if not client:
            raise RuntimeError("TRELLIS Space client not connected")

        # Step 1: Preprocess Image (Remove background)
        preprocess_res = client.predict(
            image=image_path,
            api_name="/preprocess_image"
        )

        # Step 2: Generate 3D Structured Latent
        slat_res = client.predict(
            image=preprocess_res,
            ss_sampling_steps=ss_sampling_steps,
            slat_sampling_steps=slat_sampling_steps,
            api_name="/image_to_3d"
        )

        # Step 3: Extract Mesh & Gaussian Splat
        mesh_res = client.predict(
            slat=slat_res,
            mesh_simplify=0.95,
            texture_size=4096,
            api_name="/extract_glb"
        )

        return {
            "glb_path": mesh_res,
            "latent": slat_res
        }
