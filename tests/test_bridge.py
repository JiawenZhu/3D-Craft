"""No provider calls: verify uploads, boundaries, polling and exported bytes."""
import json
import tempfile
import unittest
from pathlib import Path

import httpx

from forma_bridge.client import StudioClient


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.calls = []

    def client(self, handler):
        def record(request):
            self.calls.append(request)
            return handler(request)
        c = StudioClient(workspace=self.root, transport=httpx.MockTransport(record))
        self.addCleanup(c.close)
        return c

    def test_prompt_concept_is_single_submission(self):
        c = self.client(lambda r: httpx.Response(200, json={"run_id": "run-abc"}))
        self.assertEqual(c.generate(prompt="tiny bridge")["id"], "run-abc")
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.calls[0].url.path, "/api/pipelines")
        self.assertIn(b"tiny+bridge", self.calls[0].content)

    def test_uploads_preserve_directions_and_bytes(self):
        for name in ("back", "front", "left"):
            (self.root / f"{name}.png").write_bytes(name.encode())
        c = self.client(lambda r: httpx.Response(200, json={"job_id": "job-abc"}))
        c.generate(images=[f"{x}.png" for x in ("back", "front", "left")], directions=["back", "front", "left"], workflow="direct", engine="hunyuan3d-2.1")
        body = self.calls[0].content
        self.assertEqual(body.count(b'name="images"'), 3)
        self.assertEqual(body.count(b'name="directions"'), 3)
        for name in ("back", "front", "left"):
            self.assertIn(f'filename="{name}.png"'.encode(), body)

    def test_invalid_inputs_do_not_reach_server(self):
        c = self.client(lambda r: self.fail("must not send"))
        for args in [{}, {"images": ["../outside.png"]}, {"images": ["x.png", "y.png"], "workflow": "direct"}, {"prompt": "test", "workflow": "direct"}, {"prompt": "test", "engine": "fake"}]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                c.generate(**args)
        self.assertEqual(self.calls, [])

    def test_symlink_and_traversal_are_rejected(self):
        c = self.client(lambda r: self.fail("must not send"))
        (self.root / "escape").symlink_to(self.root.parent, target_is_directory=True)
        for path in ("../outside.glb", "escape/outside.glb", "/tmp/outside.glb"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                c.download("a-test", path)

    def test_remote_api_is_not_accidentally_exposed(self):
        with self.assertRaises(ValueError):
            StudioClient(workspace=self.root, base_url="https://example.com")

    def test_download_is_atomic_and_preserves_existing_file(self):
        payload = b"glTF" + b"real test payload"
        c = self.client(lambda r: httpx.Response(200, content=payload))
        result = c.download("a-test", "models/test.glb")
        self.assertEqual(Path(result["path"]).read_bytes(), payload)
        self.assertEqual(result["bytes"], len(payload))
        self.assertEqual(len(result["sha256"]), 64)
        with self.assertRaises(FileExistsError):
            c.download("a-test", "models/test.glb")
        self.assertEqual(len(self.calls), 1)

    def test_html_failure_leaves_no_partial_asset(self):
        c = self.client(lambda r: httpx.Response(200, content=b"<html>error</html>"))
        with self.assertRaises(ValueError):
            c.download("a-test", "models/bad.glb")
        self.assertEqual(list((self.root / "models").iterdir()), [])

    def test_obj_is_a_bundle_and_errors_are_not_files(self):
        c = self.client(lambda r: httpx.Response(404, text="missing"))
        with self.assertRaises(ValueError):
            c.download("a-test", "model.obj", "obj")
        with self.assertRaises(httpx.HTTPStatusError):
            c.download("a-test", "model.zip", "obj")
        self.assertFalse((self.root / "model.zip").exists())

    def test_polling_returns_ids_for_both_workflows(self):
        c = self.client(lambda r: httpx.Response(200, json={"status": "done", "assetId": "a-one"} if "/pipelines/" in r.url.path else {"stage": "done", "assetIds": ["a-two"]}))
        self.assertEqual(c.wait("run-abc")["assetIds"], ["a-one"])
        self.assertEqual(c.wait("job-abc")["assetIds"], ["a-two"])
        with self.assertRaises(ValueError):
            c.status("run-../secrets")

    def test_network_failure_does_not_retry_billable_request(self):
        def fail(request):
            raise httpx.ReadTimeout("timeout", request=request)
        c = self.client(fail)
        with self.assertRaisesRegex(RuntimeError, "may still be running"):
            c.generate(prompt="bridge")
        self.assertEqual(len(self.calls), 1)

    def test_real_fastapi_multipart_contract_without_paid_workers(self):
        from fastapi.testclient import TestClient
        from unittest.mock import patch
        from server.app import app
        import shutil
        with TestClient(app) as api:
            c = self.client(lambda r: api.request(r.method, r.url.path, content=r.content, headers=dict(r.headers)))
            with patch('server.app.gemini.available', return_value=(True, 'test')), patch('server.app.pipelines.create', return_value='run-abc') as create:
                self.assertEqual(c.generate(prompt='watchtower')['id'], 'run-abc')
                self.assertEqual(create.call_args.kwargs['user_prompt'], 'watchtower')
            for name in ('front', 'back', 'left'):
                (self.root / f'{name}.png').write_bytes(name.encode())
            def submit(engine, req, name):
                self.assertEqual(req.directions, ['front', 'back', 'left'])
                self.assertEqual([p.read_bytes() for p in req.images], [b'front', b'back', b'left'])
                shutil.rmtree(req.images[0].parent)
                return 'job-abc'
            with patch('server.app.jobs.submit', side_effect=submit):
                self.assertEqual(c.generate(images=['front.png', 'back.png', 'left.png'], directions=['front', 'back', 'left'], workflow='direct', engine='hunyuan3d-2.1')['id'], 'job-abc')


if __name__ == "__main__":
    unittest.main()
