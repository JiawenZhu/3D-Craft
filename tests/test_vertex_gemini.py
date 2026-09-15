import os
import unittest
from unittest.mock import MagicMock, patch

from server import config, gemini, mobile
from fastapi import HTTPException
from starlette.requests import Request


class TestVertexGeminiSecurity(unittest.TestCase):
    def test_secret_scrubbing(self):
        with patch.object(gemini, "GEMINI_API_KEY", "secret-gemini-key-123"), \
             patch.object(gemini, "VERTEX_API_KEY", "secret-vertex-key-456"):
            raw = "Error with secret-gemini-key-123 and secret-vertex-key-456 and Bearer ya29.a0AfH6_xyz123 and AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI"
            scrubbed = gemini._scrub(raw)
            self.assertNotIn("secret-gemini-key-123", scrubbed)
            self.assertNotIn("secret-vertex-key-456", scrubbed)
            self.assertNotIn("ya29.a0AfH6_xyz123", scrubbed)
            self.assertNotIn("AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI", scrubbed)
            self.assertIn("***", scrubbed)

    def test_vertex_available_check(self):
        with patch.object(gemini, "USE_VERTEX_API", True), \
             patch.object(gemini, "VERTEX_PROJECT_ID", "forma-studio-2026"), \
             patch.object(gemini, "VERTEX_LOCATION", "us-central1"), \
             patch.object(gemini, "VERTEX_API_KEY", "test-key"), \
             patch.dict(os.environ, {}, clear=True):
            ok, desc = gemini.available()
            self.assertTrue(ok)
            self.assertIn("Vertex AI", desc)
            self.assertIn("forma-studio-2026", desc)

    def test_vertex_call_headers(self):
        with patch.object(gemini, "USE_VERTEX_API", True), \
             patch.object(gemini, "VERTEX_PROJECT_ID", "forma-studio-2026"), \
             patch.object(gemini, "VERTEX_LOCATION", "us-central1"), \
             patch.object(gemini, "VERTEX_API_KEY", "test-vertex-key"), \
             patch.object(gemini.httpx, "post") as mock_post:
            mock_resp = MagicMock()
            mock_resp.is_success = True
            mock_resp.json.return_value = {"candidates": [{"content": {"parts": [{"text": "success"}]}}]}
            mock_post.return_value = mock_resp

            res = gemini._call("gemini-3.8-flash", {"test": "data"})
            self.assertEqual(res, mock_resp.json.return_value)
            self.assertTrue(mock_post.called)
            called_args, called_kwargs = mock_post.call_args
            called_url = called_args[0]
            self.assertIn("aiplatform.googleapis.com", called_url)
            self.assertIn("forma-studio-2026", called_url)
            self.assertIn("us-central1", called_url)
            self.assertIn("publishers/google/models/gemini-3.8-flash:generateContent", called_url)
            self.assertEqual(called_kwargs["headers"].get("x-goog-api-key"), "test-vertex-key")

    def test_production_https_requirement(self):
        with patch.object(mobile, "IS_PRODUCTION", True):
            # Remote HTTP request must be rejected
            scope = {
                "type": "http",
                "method": "GET",
                "path": "/api/mobile/bootstrap",
                "headers": [(b"host", b"api.example.com")],
                "client": ("192.168.1.50", 12345),
                "scheme": "http",
            }
            req = Request(scope)
            with self.assertRaises(HTTPException) as ctx:
                mobile.development(req)
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertIn("HTTPS is required", ctx.exception.detail)

            # Remote HTTPS request is allowed
            scope_https = {
                "type": "http",
                "method": "GET",
                "path": "/api/mobile/bootstrap",
                "headers": [(b"host", b"api.example.com"), (b"x-forwarded-proto", b"https")],
                "client": ("192.168.1.50", 12345),
                "scheme": "https",
            }
            req_https = Request(scope_https)
            # Should not raise
            mobile.development(req_https)

    def test_production_disables_dev_credits(self):
        with patch.object(mobile, "IS_PRODUCTION", True):
            with self.assertRaises(HTTPException) as ctx:
                mobile.review_credits(owner="test_user")
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertIn("disabled in production", ctx.exception.detail)


if __name__ == "__main__":
    unittest.main()
