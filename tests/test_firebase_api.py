import unittest
from unittest.mock import Mock, patch
from fastapi.testclient import TestClient
from server import firebase_api as api
from server.identity import require_claims

class FirebaseAPITests(unittest.TestCase):
    def setUp(self):
        self.client=TestClient(api.app)
    def tearDown(self):
        api.app.dependency_overrides.clear()
    def test_private_routes_require_identity(self):
        for route in ('projects','assets','jobs','wallet'):
            self.assertEqual(self.client.get('/api/mobile/'+route).status_code,401)
    def test_read_uses_only_verified_owner_and_cloud_media(self):
        api.app.dependency_overrides[require_claims]=lambda:{'uid':'alice'}
        cloud=Mock()
        cloud.records.return_value=[{'id':'model:one','name':'Cat','kind':'3D object','modelStoragePath':'users/alice/models/abc.glb'}]
        with patch.object(api,'studio',return_value=cloud), patch.object(api,'ensure_active'):
            result=self.client.get('/api/mobile/assets')
        self.assertEqual(result.status_code,200)
        cloud.records.assert_called_once_with('firebase:alice','mobileCreations')
        self.assertIn('firebasestorage.googleapis.com',result.json()['owned'][0]['modelUrl'])
        self.assertNotIn('localhost',result.text)
    def test_foreign_storage_reference_fails_closed(self):
        with self.assertRaises(Exception):
            api.public_shape('gs://'+api.BUCKET+'/users/bob/models/private.glb','firebase:alice')
    def test_no_generation_or_payment_readiness_is_faked(self):
        api.app.dependency_overrides[require_claims]=lambda:{'uid':'alice'}
        with patch.dict('os.environ', {}, clear=True):
            self.assertFalse(self.client.get('/api/health').json()['generationReady'])
        with patch.object(api,'ensure_active'), patch.object(api,'studio'):
            self.assertEqual(self.client.post('/api/mobile/development/purchase').status_code,503)

    def test_readiness_requires_each_cloud_generation_dependency(self):
        enabled={'CRAFT_MODEL_JOBS_ENABLED':'1', 'FAL_KEY':'fixture-only',
                 'CRAFT_PLANNING_ENABLED':'1', 'CRAFT_CONCEPT_JOBS_ENABLED':'1'}
        with patch.dict('os.environ', enabled, clear=True):
            self.assertTrue(self.client.get('/api/health').json()['generationReady'])
        for key in enabled:
            with self.subTest(missing=key), patch.dict('os.environ', {k:v for k,v in enabled.items() if k!=key}, clear=True):
                self.assertFalse(self.client.get('/api/health').json()['generationReady'])

if __name__=='__main__':unittest.main()
