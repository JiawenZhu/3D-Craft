import unittest
from typing import get_args
from unittest.mock import Mock, patch
from fastapi.testclient import TestClient

from server import api_keys
from server import firebase_api as api
from server import firebase_creations as creations
from server.firebase_animations import AnimationRequest
from server.firebase_model_jobs import ModelRequest
from server.openapi_v1 import ANIMATION_MODELS, MODEL_ENGINES
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

    def test_all_provider_models_are_exposed_in_public_api_contract(self):
        spec = self.client.get('/api/v1/openapi.json').json()
        schemas = spec['components']['schemas']
        self.assertEqual(set(MODEL_ENGINES), set(get_args(ModelRequest.model_fields['engine'].annotation)))
        self.assertEqual(set(ANIMATION_MODELS), set(get_args(AnimationRequest.model_fields['model'].annotation)))
        self.assertEqual(set(ANIMATION_MODELS), set(get_args(api.DirectAnimationRequest.model_fields['model'].annotation)))
        self.assertEqual(schemas['ModelRequest']['properties']['engine']['enum'], MODEL_ENGINES)
        self.assertEqual(schemas['DirectAnimationRequest']['properties']['model']['enum'], ANIMATION_MODELS)
        self.assertIn('patch', spec['paths']['/api/v1/assets/{asset_id}'])
        self.assertIn('get', spec['paths']['/api/v1/assets/{asset_id}'])
        self.assertIn('/api/v1/pricing', spec['paths'])
        self.assertIn('/api/v1/models', spec['paths'])

    def test_pricing_and_assets_identify_the_selected_models(self):
        headers = self.key(['assets:read'])
        catalog = self.client.get('/api/v1/pricing', headers=headers)
        self.assertEqual(catalog.status_code, 200)
        self.assertTrue(set(MODEL_ENGINES).issubset(catalog.json()['models']))
        self.assertTrue(set(ANIMATION_MODELS[:5]).issubset(catalog.json()['models']))
        self.studio.db.collection('users').document(UID).collection('mobileCreations').document('model:mj-1').update({'engine': 'tripo'})
        self.studio.db.collection('users').document(UID).collection('mobileCreations').document('animation:' + self.anim_id).update({'model': 'atlas-seedance-2.5'})
        assets = {entry['id']: entry for entry in self.client.get('/api/v1/assets', headers=headers).json()['owned']}
        self.assertEqual(assets['mj-1']['engine'], 'tripo')
        self.assertEqual(assets[self.anim_id]['model'], 'atlas-seedance-2.5')
        self.assertEqual(self.client.get(f'/api/v1/assets/{self.anim_id}', headers=headers).json()['model'], 'atlas-seedance-2.5')
        self.assertEqual(self.client.get('/api/v1/assets/foreign-id', headers=headers).status_code, 404)
        models = self.client.get('/api/v1/models', headers=headers)
        self.assertEqual(models.status_code, 200)
        self.assertEqual({row['id'] for row in models.json()['imageTo3D']}, set(MODEL_ENGINES))
        self.assertEqual({row['id'] for row in models.json()['video']}, set(ANIMATION_MODELS))
        h3 = next(row for row in models.json()['video'] if row['id'] == 'atlas-minimax-h3')
        self.assertEqual(h3['resolutions'], ['768p', '2K'])

    def test_atlas_animation_requires_its_provider_before_charge(self):
        headers = self.key(['animations:write'])
        body = {'idempotencyKey': 'atlas-video-001', 'conceptId': 'mc-1',
                'model': 'atlas-minimax-h3', 'resolution': '768p', 'maxTokens': 200}
        with patch.dict('os.environ', {'CRAFT_ANIMATION_JOBS_ENABLED': '1', 'FAL_KEY': 'test'}, clear=True), \
             patch.object(api.CloudAnimations, 'create') as create:
            response = self.client.post('/api/v1/animations', json=body, headers=headers)
        self.assertEqual(response.status_code, 503)
        create.assert_not_called()
        with patch.dict('os.environ', {'CRAFT_ANIMATION_JOBS_ENABLED': '1', 'ATLAS_API_KEY': 'test'}, clear=True), \
             patch.object(api.CloudAnimations, 'create', return_value={'id': 'an-new'}) as create:
            response = self.client.post('/api/v1/animations', json=body, headers=headers)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(create.call_args.args[2].model, 'atlas-minimax-h3')

    def test_atlas_3d_one_step_rejects_missing_provider_before_project_creation(self):
        headers = self.key(['models:write'])
        body = {'idempotencyKey': 'atlas-model-001', 'prompt': 'Blue dragon',
                'engine': 'tripo', 'maxTokens': 200}
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'FAL_KEY': 'test'}, clear=True), \
             patch.object(api, 'concepts_ready', return_value=True), \
             patch.object(api.CloudCreations, 'create') as create:
            response = self.client.post('/api/v1/creations', json=body, headers=headers)
        self.assertEqual(response.status_code, 503)
        create.assert_not_called()
        with patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'ATLAS_API_KEY': 'test'}, clear=True), \
             patch.object(api, 'concepts_ready', return_value=True), \
             patch.object(api.CloudCreations, 'create', return_value={'id': 'cj-new'}) as create:
            response = self.client.post('/api/v1/creations', json=body, headers=headers)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(create.call_args.args[1].engine, 'tripo')

    def test_asset_rename_and_delete_covers_video_and_concept(self):
        write = self.key(['models:write'])
        renamed = self.client.patch(f'/api/v1/assets/{self.anim_id}',
                                    json={'name': '  Dragon dance  '}, headers=write)
        self.assertEqual(renamed.status_code, 200, renamed.text)
        self.assertEqual(renamed.json()['name'], 'Dragon dance')
        self.assertEqual(self.studio.doc('mobileCreations', 'animation:' + self.anim_id)['name'], 'Dragon dance')
        read_only = self.key(['assets:read'])
        self.assertEqual(self.client.patch(f'/api/v1/assets/{self.anim_id}',
                                           json={'name': 'No'}, headers=read_only).status_code, 403)
        delete = self.key(['assets:delete'])
        self.assertEqual(self.client.delete(f'/api/v1/assets/{self.anim_id}', headers=delete).status_code, 200)
        self.assertIsNone(self.studio.doc('mobileCreations', 'animation:' + self.anim_id))
        self.assertNotIn(f'users/{UID}/animations/{self.anim_id}.mp4', self.studio.blobs)
        self.assertEqual(self.client.delete('/api/v1/assets/mc-1', headers=delete).status_code, 200)
        self.assertIsNone(self.studio.doc('studioConcepts', 'mc-1'))
        self.assertIsNone(self.studio.doc('mobileCreations', 'concept:mc-1'))
        self.assertIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)

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
