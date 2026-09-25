"""Focused unit tests for AtlasCloud image-to-3D provider integration.

Tests cover:
- Atlas engine recognition and result detection
- Argument building for all 10 Atlas models
- Authentication headers and error states
- Media upload with size limits and error handling
- Non-retryable paid submission
- Polling status transitions (in-progress, done, failed)
- Safe CDN URL verification and GLB validation
- Token pricing consistency for all 10 models
- Model readiness and engine catalog bootstrap
- CloudModelJobs execution lifecycle with Atlas provider
"""
import base64
import json
import os
import struct
import tempfile
import time
import unittest
import zipfile
import io
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
from fastapi import HTTPException
from fastapi.testclient import TestClient

from server import atlas_model_provider as atlas
from server import cloud_model_provider as provider
from server import firebase_api as api
from server import pricing
from server.firebase_model_jobs import CloudModelJobs, ModelRequest
from tests.fixtures import Studio, UID, OWNER, image


def create_valid_glb_bytes() -> bytes:
    """Helper creating minimal valid self-contained binary glTF (GLB) bytes."""
    doc = {
        'asset': {'version': '2.0'},
        'meshes': [{'primitives': []}],
        'buffers': []
    }
    json_bytes = json.dumps(doc).encode('utf-8')
    pad = (-len(json_bytes)) % 4
    json_bytes += b' ' * pad
    chunk_len = len(json_bytes)
    total_len = 20 + chunk_len  # 12-byte header + 8-byte chunk header + chunk data
    header = struct.pack('<4sIIII', b'glTF', 2, total_len, chunk_len, 0x4E4F534A)
    return header + json_bytes


class AtlasProviderUnitTests(unittest.TestCase):
    def test_is_atlas_engine_identifies_all_ten_models(self):
        expected_models = [
            'tripo', 'seed3d', 'hunyuan-rapid', 'hunyuan-pro',
            'hi3d-fast', 'hi3d-pro', 'hi3d-quality', 'hi3d-master',
            'meshy-single', 'meshy-multi'
        ]
        for engine in expected_models:
            self.assertTrue(atlas.is_atlas_engine(engine), f"{engine} should be recognized as Atlas engine")
            self.assertIn(engine, provider.ENGINES)

        # Fal engines and invalid names must return False
        for non_atlas in ('rodin', 'trellis-2', 'hunyuan3d-2.1', 'hunyuan3d-2-white', 'unknown', ''):
            self.assertFalse(atlas.is_atlas_engine(non_atlas))

    def test_is_atlas_result_detects_atlas_shapes(self):
        self.assertTrue(atlas.is_atlas_result({'outputs': ['https://cdn.atlascloud.ai/out.glb']}))
        self.assertTrue(atlas.is_atlas_result({'files': [{'url': 'https://cdn.atlascloud.ai/out.glb'}]}))
        self.assertTrue(atlas.is_atlas_result({'data': {'outputs': ['https://cdn.atlascloud.ai/out.glb']}}))
        self.assertTrue(atlas.is_atlas_result({'status': 'completed', 'id': 'pred-123'}))
        self.assertFalse(atlas.is_atlas_result({'model_glb': {'url': 'https://fal.media/out.glb'}}))
        self.assertFalse(atlas.is_atlas_result({}))
        self.assertFalse(atlas.is_atlas_result(None))

    def test_headers_requires_atlas_api_key(self):
        with patch.dict('os.environ', {}, clear=True):
            with self.assertRaises(HTTPException) as ctx:
                atlas.headers()
            self.assertEqual(ctx.exception.status_code, 503)

        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas-secret'}, clear=True):
            h = atlas.headers()
            self.assertEqual(h['Authorization'], 'Bearer test-atlas-secret')
            self.assertEqual(h['Content-Type'], 'application/json')

    def test_arguments_for_all_ten_models(self):
        img = 'https://cdn.atlascloud.ai/input.jpg'
        multi_imgs = ['https://cdn.atlascloud.ai/img1.jpg', 'https://cdn.atlascloud.ai/img2.jpg']

        # 1. Tripo H3.1 (default model)
        endpoint, payload = atlas.arguments('tripo', [img])
        self.assertEqual(endpoint, 'tripo-h3.1/image-to-3d')
        self.assertEqual(payload['image_url'], img)
        self.assertTrue(payload['texture'])
        self.assertTrue(payload['pbr'])
        self.assertEqual(payload['texture_quality'], 'standard')
        self.assertEqual(payload['geometry_quality'], 'standard')

        # 2. Seed3D 2.0
        endpoint, payload = atlas.arguments('seed3d', [img])
        self.assertEqual(endpoint, 'bytedance/seed3d-v2.0/image-to-3d')
        self.assertEqual(payload['image'], img)
        self.assertEqual(payload['subdivision_level'], 'high')
        self.assertEqual(payload['file_format'], 'glb')

        # 3. Hunyuan Rapid
        endpoint, payload = atlas.arguments('hunyuan-rapid', [img])
        self.assertEqual(endpoint, 'tencent/hunyuan3d-rapid/image-to-3d')
        self.assertEqual(payload['image'], img)
        self.assertTrue(payload['enable_pbr'])
        self.assertEqual(payload['format'], 'GLB')

        # 4. Hunyuan Pro
        endpoint, payload = atlas.arguments('hunyuan-pro', [img])
        self.assertEqual(endpoint, 'tencent/hunyuan3d-pro/image-to-3d')
        self.assertEqual(payload['image'], img)
        self.assertEqual(payload['generate_type'], 'Normal')
        self.assertTrue(payload['enable_pbr'])

        # 5-8. HI3D models
        for hi3d_key, expected_model in [
            ('hi3d-fast', 'hi3d/v2.1-fast/image-to-3d'),
            ('hi3d-pro', 'hi3d/v2.1-pro/image-to-3d'),
            ('hi3d-quality', 'hi3d/v3.0-quality/image-to-3d'),
            ('hi3d-master', 'hi3d/v3.0-master/image-to-3d'),
        ]:
            endpoint, payload = atlas.arguments(hi3d_key, [img])
            self.assertEqual(endpoint, expected_model)
            self.assertEqual(payload['image'], img)
            self.assertTrue(payload['should_texture'])
            self.assertTrue(payload['enable_pbr'])
            self.assertEqual(payload['output_format'], 'glb')

        # 9. Meshy v7 single
        endpoint, payload = atlas.arguments('meshy-single', [img])
        self.assertEqual(endpoint, 'meshy-v7/image-to-3d')
        self.assertEqual(payload['image'], img)
        self.assertTrue(payload['should_texture'])
        self.assertTrue(payload['enable_pbr'])
        self.assertEqual(payload['texture_resolution'], '2k')
        self.assertEqual(payload['target_formats'], ['glb'])

        # 10. Meshy v7 multi-image
        endpoint, payload = atlas.arguments('meshy-multi', multi_imgs)
        self.assertEqual(endpoint, 'meshy-v7/multi-image-to-3d')
        self.assertEqual(payload['reference_images'], multi_imgs)
        self.assertTrue(payload['should_texture'])
        self.assertTrue(payload['enable_pbr'])

        # Error checks
        with self.assertRaises(ValueError):
            atlas.arguments('unknown-engine', [img])
        with self.assertRaises(ValueError):
            atlas.arguments('tripo', [])

    def test_upload_media_success_and_validation(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            sample_file = Path(tmpdir) / 'test.jpg'
            sample_file.write_bytes(b'\xff\xd8\xff\xe0fake-jpeg-bytes')

            # Missing API key
            with patch.dict('os.environ', {}, clear=True):
                with self.assertRaises(HTTPException):
                    atlas.upload_media(sample_file)

            # Successful upload with key
            mock_res = Mock()
            mock_res.json.return_value = {'code': 200, 'data': {'url': 'https://cdn.atlascloud.ai/media/uploaded.jpg'}}
            mock_res.raise_for_status = Mock()

            with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.post', return_value=mock_res) as mock_post:
                url = atlas.upload_media(sample_file)
                self.assertEqual(url, 'https://cdn.atlascloud.ai/media/uploaded.jpg')
                mock_post.assert_called_once()
                self.assertEqual(mock_post.call_args[0][0], atlas.UPLOAD_URL)

            # Oversized file (>20MB)
            with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch.object(Path, 'stat') as mock_stat:
                stat_obj = Mock()
                stat_obj.st_size = 25 * 1024 * 1024
                mock_stat.return_value = stat_obj
                with self.assertRaises(ValueError):
                    atlas.upload_media(sample_file)

    def test_submit_never_retries_paid_post(self):
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.post', side_effect=TimeoutError) as mock_post:
            with self.assertRaises(TimeoutError):
                atlas.submit('tripo-h3.1/image-to-3d', {'model': 'tripo'})
            mock_post.assert_called_once()

    def test_submit_success_returns_prediction_id(self):
        mock_res = Mock()
        mock_res.json.return_value = {'code': 200, 'data': {'id': 'pred-abc-123'}}
        mock_res.raise_for_status = Mock()

        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.post', return_value=mock_res):
            pred_id = atlas.submit('tripo-h3.1/image-to-3d', {'model': 'tripo'})
            self.assertEqual(pred_id, 'pred-abc-123')

    def test_status_polling_states(self):
        # 1. In progress -> returns None
        mock_proc = Mock()
        mock_proc.json.return_value = {'data': {'id': 'pred-1', 'status': 'processing'}}
        mock_proc.raise_for_status = Mock()
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.get', return_value=mock_proc):
            self.assertIsNone(atlas.status('pred-1'))

        # 2. Completed -> returns data
        mock_done = Mock()
        mock_done.json.return_value = {'data': {'id': 'pred-1', 'status': 'completed', 'outputs': ['https://cdn.atlascloud.ai/out.glb']}}
        mock_done.raise_for_status = Mock()
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.get', return_value=mock_done):
            res = atlas.status('pred-1')
            self.assertIsNotNone(res)
            self.assertEqual(res['status'], 'completed')

        # 3. Failed -> raises RuntimeError with provider message
        mock_fail = Mock()
        mock_fail.json.return_value = {'data': {'id': 'pred-1', 'status': 'failed', 'error': 'Out of VRAM'}}
        mock_fail.raise_for_status = Mock()
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-key'}), patch('requests.get', return_value=mock_fail):
            with self.assertRaises(RuntimeError) as ctx:
                atlas.status('pred-1')
            self.assertIn('Out of VRAM', str(ctx.exception))

    def test_is_safe_cdn_url(self):
        # Unsafe cases
        self.assertFalse(atlas.is_safe_cdn_url('http://cdn.atlascloud.ai/out.glb'))  # Non-HTTPS
        self.assertFalse(atlas.is_safe_cdn_url('https://user:pass@cdn.atlascloud.ai/out.glb'))  # Credentials
        self.assertFalse(atlas.is_safe_cdn_url('https://cdn.atlascloud.ai:8080/out.glb'))  # Custom port
        self.assertFalse(atlas.is_safe_cdn_url('https://localhost/out.glb'))  # Localhost
        self.assertFalse(atlas.is_safe_cdn_url('https://127.0.0.1/out.glb'))  # Loopback
        self.assertFalse(atlas.is_safe_cdn_url('https://10.0.0.1/out.glb'))  # Private 10/8
        self.assertFalse(atlas.is_safe_cdn_url('https://192.168.1.1/out.glb'))  # Private 192.168/16
        self.assertFalse(atlas.is_safe_cdn_url('https://172.20.0.1/out.glb'))  # Private 172.16-31/12
        self.assertFalse(atlas.is_safe_cdn_url('https://169.254.1.1/out.glb'))  # Link-local

        # Safe cases
        self.assertTrue(atlas.is_safe_cdn_url('https://cdn.atlascloud.ai/output/mesh.glb'))
        self.assertTrue(atlas.is_safe_cdn_url('https://storage.googleapis.com/test-bucket/mesh.glb'))

    def test_extract_model_url(self):
        # From files list
        res_files = {'files': [{'file_name': 'result.glb', 'url': 'https://cdn.atlascloud.ai/result.glb'}]}
        self.assertEqual(atlas.extract_model_url(res_files), 'https://cdn.atlascloud.ai/result.glb')

        # From outputs list
        res_outputs = {'outputs': ['https://cdn.atlascloud.ai/image.png', 'https://cdn.atlascloud.ai/mesh.glb']}
        self.assertEqual(atlas.extract_model_url(res_outputs), 'https://cdn.atlascloud.ai/mesh.glb')

        # Missing output raises ValueError
        with self.assertRaises(ValueError):
            atlas.extract_model_url({})

    def test_glb_validation_and_safe_download(self):
        glb_bytes = create_valid_glb_bytes()
        with tempfile.TemporaryDirectory() as tmpdir:
            valid_path = Path(tmpdir) / 'valid.glb'
            valid_path.write_bytes(glb_bytes)
            # Valid GLB must pass validation
            atlas.validate_glb(valid_path)

            # Invalid magic
            bad_magic_path = Path(tmpdir) / 'bad_magic.glb'
            bad_magic_path.write_bytes(b'ABCD' + glb_bytes[4:])
            with self.assertRaises(ValueError):
                atlas.validate_glb(bad_magic_path)

            # Truncated file
            truncated_path = Path(tmpdir) / 'truncated.glb'
            truncated_path.write_bytes(glb_bytes[:16])
            with self.assertRaises(ValueError):
                atlas.validate_glb(truncated_path)

            # External URI in buffer
            bad_doc = {'asset': {'version': '2.0'}, 'meshes': [{'primitives': []}], 'buffers': [{'uri': 'https://evil.com/data'}]}
            bad_doc_bytes = json.dumps(bad_doc).encode('utf-8')
            pad = (-len(bad_doc_bytes)) % 4
            bad_doc_bytes += b' ' * pad
            bad_ext_bytes = struct.pack('<4sIIII', b'glTF', 2, 20 + len(bad_doc_bytes), len(bad_doc_bytes), 0x4E4F534A) + bad_doc_bytes
            bad_ext_path = Path(tmpdir) / 'bad_ext.glb'
            bad_ext_path.write_bytes(bad_ext_bytes)
            with self.assertRaises(ValueError):
                atlas.validate_glb(bad_ext_path)

            # Test download_mesh with streaming mock response context manager
            dest_path = Path(tmpdir) / 'downloaded.glb'
            mock_resp = MagicMock()
            mock_resp.__enter__.return_value = mock_resp
            mock_resp.is_redirect = False
            mock_resp.raise_for_status = Mock()
            mock_resp.iter_content.return_value = [glb_bytes]

            with patch('requests.get', return_value=mock_resp):
                atlas.download_mesh({'outputs': ['https://cdn.atlascloud.ai/mesh.glb']}, dest_path)
                self.assertTrue(dest_path.exists())
                self.assertEqual(dest_path.read_bytes(), glb_bytes)

    def test_seed3d_zip_is_unpacked_to_valid_glb(self):
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as output:
            output.writestr('models/character.glb', create_valid_glb_bytes())
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'model.glb'
            mock_resp = MagicMock()
            mock_resp.__enter__.return_value = mock_resp
            mock_resp.is_redirect = False
            mock_resp.raise_for_status = Mock()
            mock_resp.iter_content.return_value = [archive.getvalue()]
            with patch('requests.get', return_value=mock_resp):
                atlas.download_mesh({'outputs': ['https://cdn.atlascloud.ai/result.zip']}, destination)
            self.assertEqual(destination.read_bytes(), create_valid_glb_bytes())


class AtlasPricingTests(unittest.TestCase):
    def test_all_ten_models_pricing_and_usage_quote_consistency(self):
        expected_pricing = {
            'tripo': (0.22, 26, 'Tripo H3.1'),
            'seed3d': (0.353, 41, 'Seed3D 2.0'),
            'hunyuan-rapid': (0.50, 58, 'Hunyuan Rapid'),
            'hunyuan-pro': (0.70, 81, 'Hunyuan Pro'),
            'hi3d-fast': (0.425, 49, 'HI3D v2.1 Fast'),
            'hi3d-pro': (0.765, 88, 'HI3D v2.1 Pro'),
            'hi3d-quality': (1.105, 128, 'HI3D v3.0 Quality'),
            'hi3d-master': (5.185, 597, 'HI3D v3.0 Master'),
            'meshy-single': (0.66, 76, 'Meshy v7'),
            'meshy-multi': (0.66, 76, 'Meshy v7 Multi'),
        }

        catalog = pricing.catalog()
        models = catalog['models']

        for engine, (usd, expected_tokens, name) in expected_pricing.items():
            self.assertIn(engine, models, f"{engine} should be present in pricing catalog")
            entry = models[engine]
            self.assertEqual(entry['texturedCredits'], expected_tokens, f"{engine} token mismatch in catalog")
            self.assertEqual(entry['unitUsd'], usd, f"{engine} USD mismatch")
            self.assertEqual(entry['name'], name, f"{engine} name mismatch")
            self.assertTrue(entry.get('noteZh'), f"{engine} missing Chinese translation")
            # Verify model_quote matches expected tokens
            quote = pricing.model_quote(engine)
            self.assertEqual(quote['usageWithServiceFee']['credits'], expected_tokens, f"{engine} quote tokens mismatch")

        # Existing baseline anchor: Rodin at 46 tokens
        self.assertEqual(pricing.model_quote('rodin')['usageWithServiceFee']['credits'], 46)


class AtlasApiAndBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(api.app)

    def tearDown(self):
        api.app.dependency_overrides.clear()

    def test_model_ready_accepts_either_atlas_or_fal(self):
        # 1. Neither key -> False
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1'}, clear=True):
            self.assertFalse(api.model_ready())

        # 2. Only ATLAS_API_KEY -> True
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'ATLAS_API_KEY': 'atlas-key'}, clear=True):
            self.assertTrue(api.model_ready())

        # 3. Only FAL_KEY -> True
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'FAL_KEY': 'fal-key'}, clear=True):
            self.assertTrue(api.model_ready())

        # 4. Feature flag disabled -> False
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '0', 'ATLAS_API_KEY': 'atlas-key'}, clear=True):
            self.assertFalse(api.model_ready())

    def test_bootstrap_reports_per_engine_readiness(self):
        api.app.dependency_overrides[api.owner] = lambda: 'firebase:alice'
        with patch.object(api, 'wallet', return_value={'available': 100, 'subscriptionAvailable': 0}):
            # Case A: ATLAS_API_KEY only
            with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'ATLAS_API_KEY': 'test-atlas'}, clear=True):
                res = self.client.get('/api/mobile/bootstrap').json()
                self.assertTrue(res['modelGenerationReady'])
                catalog = {e['id']: e for e in res['engineCatalog']}
                self.assertTrue(catalog['tripo']['ready'])
                self.assertTrue(catalog['seed3d']['ready'])
                self.assertFalse(catalog['rodin']['ready'])

            # Case B: FAL_KEY only
            with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'FAL_KEY': 'test-fal'}, clear=True):
                res = self.client.get('/api/mobile/bootstrap').json()
                self.assertTrue(res['modelGenerationReady'])
                catalog = {e['id']: e for e in res['engineCatalog']}
                self.assertFalse(catalog['tripo']['ready'])
                self.assertTrue(catalog['rodin']['ready'])


class AtlasModelJobsLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        self.clock = 1000.0
        self.studio.put('studioProjects', 'p1', name='Fox', prompt='a fox', createdAt=self.clock)
        self.studio.put('studioConcepts', 'c1', id='c1', projectId='p1', imageUrl=image('c1'), createdAt=self.clock)
        self.studio.wallet(available=300)
        self.wallet_ref = self.studio.db.collection('users').document(UID).collection('private').document('wallet')
        self.wallet_ref.set({'available': 300, 'subscriptionAvailable': 0, 'welcomeTokensGranted': True, 'environment': 'PRODUCTION'})

        self.mock_blob = Mock()
        self.mock_blob.size = 1024
        self.mock_blob.generation = 1
        self.mock_blob.reload = Mock()
        self.mock_blob.download_to_filename = lambda target, **kw: Path(target).write_bytes(b'fake-jpeg')
        self.mock_blob.upload_from_filename = Mock()
        self.studio.bucket.blob.side_effect = lambda path: self.mock_blob

        self.patcher = patch('server.firebase_model_jobs.firestore.transactional', side_effect=lambda fn: fn)
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    def set_private_job(self, jid, **fields):
        ref = self.studio.db.collection('users').document(UID).collection('private').document('generationJobs').collection('items').document(jid)
        ref.update(fields)

    def get_private_job(self, jid):
        ref = self.studio.db.collection('users').document(UID).collection('private').document('generationJobs').collection('items').document(jid)
        return ref.get().to_dict()

    def test_tripo_creation_reserves_exact_tokens(self):
        service = CloudModelJobs(self.studio, clock=lambda: self.clock)
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas'}), \
             patch('server.firebase_model_jobs.enqueue'):
            body = ModelRequest(idempotencyKey='req-tripo-1', engine='tripo')
            job = service.create(OWNER, 'c1', body)
            self.assertEqual(job['modelSettings']['engine'], 'tripo')
            self.assertEqual(job['status'], 'queued')
            # 26 tokens reserved for Tripo H3.1
            wallet = self.wallet_ref.get().to_dict()
            self.assertEqual(wallet['reserved'], 26)
            self.assertEqual(wallet['available'], 300 - 26)

    def test_run_lifecycle_preparing_to_submitted(self):
        service = CloudModelJobs(self.studio, clock=lambda: self.clock)
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas'}), \
             patch('server.firebase_model_jobs.enqueue'):
            body = ModelRequest(idempotencyKey='req-tripo-prep', engine='tripo')
            job = service.create(OWNER, 'c1', body)
            jid = job['id']

            with patch('server.atlas_model_provider.upload_media', return_value='https://cdn.atlascloud.ai/media.jpg') as mock_upload, \
                 patch('server.atlas_model_provider.submit', return_value='pred-submitted-123') as mock_submit, \
                 patch('server.atlas_model_provider.status', return_value=None):  # in progress
                with self.assertRaises(HTTPException) as ctx:
                    service.run(UID, jid)
                self.assertEqual(ctx.exception.status_code, 503)
                self.assertIn('in progress', ctx.exception.detail)
                mock_upload.assert_called_once()
                mock_submit.assert_called_once()

            priv = self.get_private_job(jid)
            self.assertEqual(priv['phase'], 'submitted')
            self.assertEqual(priv['requestId'], 'pred-submitted-123')

    def test_run_submitting_state_prevents_duplicate_paid_call(self):
        service = CloudModelJobs(self.studio, clock=lambda: self.clock)
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas'}), \
             patch('server.firebase_model_jobs.enqueue'):
            body = ModelRequest(idempotencyKey='req-tripo-sub', engine='tripo')
            job = service.create(OWNER, 'c1', body)
            jid = job['id']

            # Manually set phase to 'submitting' (simulating lost response / crash after POST)
            self.set_private_job(jid, phase='submitting')

            # Re-entering while submitting must raise 503 and NEVER call submit
            with patch('server.atlas_model_provider.submit') as mock_submit:
                with self.assertRaises(HTTPException) as ctx:
                    service.run(UID, jid)
                self.assertEqual(ctx.exception.status_code, 503)
                self.assertIn('Waiting for provider confirmation', ctx.exception.detail)
                mock_submit.assert_not_called()

    def test_run_lifecycle_submitted_to_done(self):
        service = CloudModelJobs(self.studio, clock=lambda: self.clock)
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas'}), \
             patch('server.firebase_model_jobs.enqueue'):
            body = ModelRequest(idempotencyKey='req-tripo-done', engine='tripo')
            job = service.create(OWNER, 'c1', body)
            jid = job['id']

            # Set private job to submitted phase with requestId
            self.set_private_job(jid, phase='submitted', requestId='pred-xyz-789')

            status_data = {'id': 'pred-xyz-789', 'status': 'completed', 'outputs': ['https://cdn.atlascloud.ai/fox.glb']}

            with patch('server.atlas_model_provider.status', return_value=status_data), \
                 patch('server.atlas_model_provider.download_mesh') as mock_dl:
                res = service.run(UID, jid)
                self.assertEqual(res['status'], 'done')
                mock_dl.assert_called_once()
                self.mock_blob.upload_from_filename.assert_called_once()

            # Verify public job is done and Tokens settled
            pub = self.studio.doc('studioJobs', jid)
            self.assertEqual(pub['status'], 'done')
            self.assertEqual(pub['reserved'], 0)
            self.assertEqual(pub['charged'], 26)

    def test_run_lifecycle_submitted_failure_refunds_tokens(self):
        service = CloudModelJobs(self.studio, clock=lambda: self.clock)
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test-atlas'}), \
             patch('server.firebase_model_jobs.enqueue'):
            body = ModelRequest(idempotencyKey='req-tripo-fail', engine='tripo')
            job = service.create(OWNER, 'c1', body)
            jid = job['id']

            # Set private job to submitted phase
            self.set_private_job(jid, phase='submitted', requestId='pred-fail-123')

            with patch('server.atlas_model_provider.status', side_effect=RuntimeError('Provider GPU timeout')):
                res = service.run(UID, jid)
                self.assertEqual(res['status'], 'failed')

            # Verify public job is failed and Tokens refunded
            pub = self.studio.doc('studioJobs', jid)
            self.assertEqual(pub['status'], 'failed')
            self.assertEqual(pub['reserved'], 0)
            self.assertEqual(pub['charged'], 0)
            wallet = self.wallet_ref.get().to_dict()
            self.assertEqual(wallet['reserved'], 0)
            self.assertEqual(wallet['available'], 300)


if __name__ == '__main__':
    unittest.main()
