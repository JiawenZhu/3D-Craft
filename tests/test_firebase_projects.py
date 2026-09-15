import io
import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from server.firebase_projects import CloudProjects, normalized_image, MAX_BYTES
from server.firebase_studio import BUCKET
from server import firebase_api as api
from server.identity import require_claims


def photo():
    out = io.BytesIO()
    image = Image.new('RGB', (24, 16), 'green')
    exif = Image.Exif(); exif[315] = 'private author'
    image.save(out, format='JPEG', exif=exif)
    return out.getvalue()


class CloudProjectTests(unittest.TestCase):
    def test_image_validation_strips_metadata_and_rejects_bad_inputs(self):
        data, width, height = normalized_image(photo())
        self.assertEqual((width, height), (24, 16))
        self.assertEqual(dict(Image.open(io.BytesIO(data)).getexif()), {})
        for data, code in [(b'not a picture', 422), (b'x' * (MAX_BYTES + 1), 413)]:
            with self.assertRaises(HTTPException) as error: normalized_image(data)
            self.assertEqual(error.exception.status_code, code)
        large = Mock(); large.__enter__ = lambda _: large; large.__exit__ = Mock(return_value=False)
        large.format = 'PNG'; large.width = large.height = 10000
        with patch('server.firebase_projects.Image.open', return_value=large):
            with self.assertRaises(HTTPException): normalized_image(b'image')
        large.load.assert_not_called()

    def test_deleted_account_cannot_start_upload(self):
        studio = Mock()
        studio.db.collection.return_value.document.return_value.get.return_value.exists = True
        with self.assertRaises(HTTPException): CloudProjects(studio).create('firebase:alice', raw=photo())
        studio.bucket.blob.assert_not_called()

    def test_cleanup_retains_only_published_owned_image(self):
        studio = Mock(); service = CloudProjects(studio)
        marker = studio.db.collection.return_value.document.return_value.get.return_value
        marker.exists = False
        concept = Mock(); concept.exists = True
        cid = 'mc-' + 'a' * 32
        concept.to_dict.return_value = {'imageUrl': f'gs://{BUCKET}/users/alice/images/{cid}.jpg'}
        with patch.object(service, 'ref') as ref:
            ref.return_value.get.return_value = concept
            self.assertEqual(service.cleanup('alice', cid), {'status': 'retained'})
            studio.bucket.blob.assert_not_called()
            marker.exists = True
            self.assertEqual(service.cleanup('alice', cid), {'status': 'removed'})
            blob = studio.bucket.blob.return_value
            blob.delete.assert_called_once_with(if_generation_match=blob.generation, timeout=30)

    def test_cleanup_never_accepts_arbitrary_object_paths(self):
        studio = Mock()
        for uid, cid in [('alice', '../private'), ('alice', 'mc-no'), ('../bob', 'mc-'+'a'*32)]:
            with self.assertRaises((HTTPException, ValueError)): CloudProjects(studio).cleanup(uid, cid)
        studio.bucket.blob.assert_not_called()


class CloudProjectAPITests(unittest.TestCase):
    def setUp(self): self.client = TestClient(api.app)
    def tearDown(self): api.app.dependency_overrides.clear()

    def test_upload_requires_firebase_identity_and_worker_requires_oidc(self):
        self.assertEqual(self.client.post('/api/mobile/projects', data={'prompt':'Cat'}).status_code, 401)
        with patch.object(api, 'verify_worker', side_effect=HTTPException(401, 'Required')):
            self.assertEqual(self.client.post('/internal/uploads/alice/mc-'+'a'*32).status_code, 401)

    def test_verified_identity_wins_over_client_owner_and_private_media_is_resolved(self):
        api.app.dependency_overrides[require_claims] = lambda: {'uid': 'alice'}
        with patch.object(api, 'studio'), patch.object(api, 'ensure_active'), patch.object(api, 'CloudProjects') as service:
            service.return_value.create.return_value = {'id': 'one', 'imageUrl': f'gs://{BUCKET}/users/alice/images/one.jpg'}
            response = self.client.post('/api/mobile/projects', data={'prompt':'Cat','owner':'bob','clientId':'stable-request'},
                                        files={'image':('image.jpg',photo(),'image/jpeg')})
            self.assertEqual(response.status_code, 200)
            args, kwargs = service.return_value.create.call_args
            self.assertEqual(args, ('firebase:alice',))
            self.assertEqual(kwargs['client_id'], 'stable-request')
            self.assertIn('firebasestorage.googleapis.com', response.json()['imageUrl'])
            self.assertNotIn('bob', response.text)


if __name__ == '__main__': unittest.main()
