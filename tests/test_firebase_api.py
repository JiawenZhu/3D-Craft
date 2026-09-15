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
        with patch.object(api,'studio',return_value=cloud):
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
        self.assertFalse(self.client.get('/api/health').json()['generationReady'])
        self.assertEqual(self.client.post('/api/mobile/development/purchase').status_code,503)

if __name__=='__main__':unittest.main()
