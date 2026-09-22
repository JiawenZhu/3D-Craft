import unittest
from unittest.mock import Mock, patch
from fastapi.testclient import TestClient

from server import api_keys
from server import firebase_api as api
from server import firebase_creations as creations
from tests.fixtures import OWNER, ProjectFixture, Studio, UID


class ExtendedApiV1Tests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(api.app)
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        self.service = creations.CloudCreations(self.studio)

        # Setup an animated character creation and file
        self.anim_id = 'an-test-video'
        self.studio.blobs[f'users/{UID}/animations/{self.anim_id}.mp4'] = b'mp4-video-bytes'
        self.studio.put(
            'mobileCreations',
            f'animation:{self.anim_id}',
            ownerId=UID,
            name='Dancing Robot',
            kind='Animated character',
            projectId='mp-1',
            conceptIds=['mc-1'],
            previewStoragePath=f'users/{UID}/images/mc-1.jpg',
            animationStoragePath=f'users/{UID}/animations/{self.anim_id}.mp4',
            createdAt=1789777100,
        )
        self.studio.put(
            'studioJobs',
            self.anim_id,
            ownerId=UID,
            status='done',
            stage='done',
            progress=100,
            message='Your animated character is ready',
            createdAt=1789777100,
        )

        self.patches = [
            patch('server.api_keys.firestore.transactional', side_effect=lambda fn: fn),
            patch.object(api, 'studio', return_value=self.studio),
            patch.object(api_keys, 'request_ref'),
            patch('firebase_admin.auth.get_user', return_value=Mock(disabled=False, display_name='Alice Tester', photo_url=None)),
            patch('firebase_admin.auth.update_user'),
        ]
        for p in self.patches:
            started = p.start()
            if p.attribute == 'request_ref':
                started.return_value.get.return_value.exists = False

    def tearDown(self):
        for p in self.patches:
            p.stop()

    def key(self, scopes):
        return {'Authorization': 'Bearer ' + api_keys.create_api_key(self.studio.db, UID, 'test_key', scopes=scopes)['key']}

    # -------------------------------------------------------------
    # 1. Download tests with kind auto-detection and query variants
    # -------------------------------------------------------------

    def test_download_animation_video_with_auto_kind(self):
        headers = self.key(['*'])
        res = self.client.get(f'/api/v1/assets/{self.anim_id}/download', headers=headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.content, b'mp4-video-bytes')
        self.assertEqual(res.headers['content-type'], 'video/mp4')
        self.assertIn(f'{self.anim_id}.mp4', res.headers['content-disposition'])

    def test_download_animation_video_with_explicit_kind_params(self):
        headers = self.key(['*'])
        # kind=animation (which previously returned 422)
        res_anim = self.client.get(f'/api/v1/assets/{self.anim_id}/download?kind=animation', headers=headers)
        self.assertEqual(res_anim.status_code, 200)
        self.assertEqual(res_anim.content, b'mp4-video-bytes')
        self.assertEqual(res_anim.headers['content-type'], 'video/mp4')

        # kind=video
        res_vid = self.client.get(f'/api/v1/assets/{self.anim_id}/download?kind=video', headers=headers)
        self.assertEqual(res_vid.status_code, 200)
        self.assertEqual(res_vid.content, b'mp4-video-bytes')
        self.assertEqual(res_vid.headers['content-type'], 'video/mp4')

    def test_download_3d_model_with_auto_and_explicit_kind(self):
        headers = self.key(['*'])
        # mj-1 is 3D object from ProjectFixture
        res_auto = self.client.get('/api/v1/assets/mj-1/download', headers=headers)
        self.assertEqual(res_auto.status_code, 200)
        self.assertEqual(res_auto.content, b'glb')
        self.assertEqual(res_auto.headers['content-type'], 'model/gltf-binary')

        res_model = self.client.get('/api/v1/assets/mj-1/download?kind=model', headers=headers)
        self.assertEqual(res_model.status_code, 200)
        self.assertEqual(res_model.content, b'glb')

    def test_download_concept_image_with_auto_kind(self):
        headers = self.key(['*'])
        # mc-1 is a concept image
        res_auto = self.client.get('/api/v1/assets/mc-1/download', headers=headers)
        self.assertEqual(res_auto.status_code, 200)
        self.assertEqual(res_auto.content, b'jpg')
        self.assertEqual(res_auto.headers['content-type'], 'image/jpeg')

    # -------------------------------------------------------------
    # 2. Animation Status and Direct Download Route
    # -------------------------------------------------------------

    def test_animation_status_and_dedicated_download_route(self):
        headers = self.key(['*'])
        res = self.client.get(f'/api/v1/animations/{self.anim_id}', headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data['id'], self.anim_id)
        self.assertEqual(data['status'], 'done')
        self.assertEqual(data['progress'], 100)
        self.assertIsNotNone(data['asset'])
        self.assertEqual(data['asset']['downloadUrl'], f'/api/v1/animations/{self.anim_id}/download')

        # Dedicated animation download endpoint
        dl_res = self.client.get(f'/api/v1/animations/{self.anim_id}/download', headers=headers)
        self.assertEqual(dl_res.status_code, 200)
        self.assertEqual(dl_res.content, b'mp4-video-bytes')
        self.assertEqual(dl_res.headers['content-type'], 'video/mp4')

    # -------------------------------------------------------------
    # 3. User Profile API
    # -------------------------------------------------------------

    def test_get_and_patch_user_profile(self):
        headers = self.key(['*'])
        # Initial read
        res = self.client.get('/api/v1/profile', headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data['uid'], UID)
        self.assertIn('stats', data)
        self.assertIn('wallet', data)
        self.assertGreaterEqual(data['stats']['totalCreations'], 1)

        # Update profile
        patch_res = self.client.patch(
            '/api/v1/profile',
            json={
                'displayName': 'Master 3D Crafter',
                'bio': 'Specializing in mechanical and creature concepts.',
                'appearance': {'theme': 'dark', 'accentColor': 'gold'},
            },
            headers=headers,
        )
        self.assertEqual(patch_res.status_code, 200)
        updated = patch_res.json()
        self.assertEqual(updated['displayName'], 'Master 3D Crafter')
        self.assertEqual(updated['bio'], 'Specializing in mechanical and creature concepts.')
        self.assertEqual(updated['appearance']['theme'], 'dark')

        # Verify persistence in Firestore
        user_doc = self.studio.doc('users', UID)
        # Note: in Studio fake, top level doc might be accessed via db
        doc = self.studio.db.collection('users').document(UID).get()
        self.assertTrue(doc.exists)
        self.assertEqual(doc.to_dict()['displayName'], 'Master 3D Crafter')

    # -------------------------------------------------------------
    # 4. Favorites Management API
    # -------------------------------------------------------------

    def test_favorites_workflow(self):
        headers = self.key(['*'])

        # Initially no favorites
        res_init = self.client.get('/api/v1/favorites', headers=headers)
        self.assertEqual(res_init.status_code, 200)
        self.assertEqual(res_init.json()['favorites'], [])

        # Favorite the animated character
        res_fav = self.client.post(f'/api/v1/assets/{self.anim_id}/favorite', headers=headers)
        self.assertEqual(res_fav.status_code, 200)
        self.assertTrue(res_fav.json()['favorite'])

        # Now listed in favorites
        res_list = self.client.get('/api/v1/favorites', headers=headers)
        self.assertEqual(res_list.status_code, 200)
        favs = res_list.json()['favorites']
        self.assertEqual(len(favs), 1)
        self.assertEqual(favs[0]['id'], self.anim_id)
        self.assertEqual(favs[0]['kind'], 'animation')
        self.assertTrue(favs[0]['isFavorite'])

        # Unfavorite
        res_unfav = self.client.delete(f'/api/v1/assets/{self.anim_id}/favorite', headers=headers)
        self.assertEqual(res_unfav.status_code, 200)
        self.assertFalse(res_unfav.json()['favorite'])

        # Gone from favorites
        res_after = self.client.get('/api/v1/favorites', headers=headers)
        self.assertEqual(res_after.status_code, 200)
        self.assertEqual(res_after.json()['favorites'], [])

    # -------------------------------------------------------------
    # 5. AI Prompt Architect / Enhancement API
    # -------------------------------------------------------------

    def test_prompt_enhancement(self):
        headers = self.key(['*'])
        res = self.client.post(
            '/api/v1/prompts/enhance',
            json={'prompt': 'cyberpunk samurai robot', 'target': '3d', 'style': 'Stylized'},
            headers=headers,
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data['originalPrompt'], 'cyberpunk samurai robot')
        self.assertIn('enhancedPrompt', data)
        self.assertIn('negativePrompt', data)
        self.assertIn('suggestedEngine', data)
        self.assertEqual(data['suggestedStyle'], 'Stylized')

    # -------------------------------------------------------------
    # 6. Community Games API
    # -------------------------------------------------------------

    def test_community_games(self):
        headers = self.key(['*'])
        res = self.client.get('/api/v1/community/games?category=fun', headers=headers)
        self.assertEqual(res.status_code, 200)
        self.assertIn('games', res.json())


if __name__ == '__main__':
    unittest.main()
