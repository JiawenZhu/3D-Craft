"""Offline image catalog checks; no paid generation."""
import base64
import unittest
from unittest.mock import patch
from server import gemini, image_models

class ImageModelTests(unittest.TestCase):
    def test_gemini_is_default_without_chatgpt(self):
        with patch.object(gemini, "GEMINI_API_KEY", "test-secret"):
            catalog = image_models.catalog()
        self.assertEqual(catalog["defaultModel"], "gemini-3-pro-image")
        self.assertEqual([m["id"] for m in catalog["models"]], ["gemini-3-pro-image", "codex-gpt-image-2"])
        self.assertEqual([m["available"] for m in catalog["models"]], [True, False])
        self.assertNotIn("test-secret", str(catalog))

    def test_account_image_requires_connection_and_capability(self):
        for connected, capability in [(False, True), (True, False), (False, False)]:
            with self.assertRaises(RuntimeError):
                image_models.require_available(image_models.CODEX_MODEL, {"connected": connected, "imageGenerationSupported": capability})
        model = image_models.require_available(image_models.CODEX_MODEL, {"connected": True, "imageGenerationSupported": True})
        self.assertEqual(model["provider"], "chatgpt")
        with self.assertRaises(ValueError):
            image_models.require_available("gpt-image-2.5-sunburst")

    def test_selected_gemini_model_overrides_legacy_environment_default(self):
        response={"candidates":[{"content":{"parts":[{"inlineData":{"data":base64.b64encode(b"image").decode(),"mimeType":"image/png"}}]}}]}
        with patch.object(gemini,"GEMINI_IMAGE_MODEL","legacy-model"), patch.object(gemini,"_call",return_value=response) as call:
            result=gemini.make_image("cat",model="gemini-3-pro-image",image_size="2K")
            self.assertEqual(call.call_args.args[0], "gemini-3-pro-image")
            self.assertEqual(result["model"],"gemini-3-pro-image")
            self.assertEqual(call.call_args.args[1]["generationConfig"]["imageConfig"]["imageSize"],"2K")


if __name__ == "__main__": unittest.main()
