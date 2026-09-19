import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from google.api_core.exceptions import NotFound

from server import api_keys
from server import firebase_api as api
from server import firebase_creations as creations
from server.firebase_studio import BUCKET
from tests.test_api_keys import MockFirestore

UID = 'user_alice'
OWNER = 'firebase:' + UID


class Batch:
    def __init__(self): self.refs = []
    def delete(self, ref): self.refs.append(ref)
    def commit(self):
        for ref in self.refs: ref.delete()


class Studio:
    """FirebaseStudio's record API over the in-memory Firestore used by the API-key tests."""
    def __init__(self):
        self.db = MockFirestore()
        self.db.batch = Batch
        self.blobs = {}
        self.bucket = Mock()
        self.bucket.blob.side_effect = self.blob

    def blob(self, path):
        blob = Mock()
        def delete(timeout=None):
            if path not in self.blobs: raise NotFound(path)
            del self.blobs[path]
        def download(timeout=None):
            if path not in self.blobs: raise NotFound(path)
            return self.blobs[path]
        blob.delete.side_effect = delete
        blob.download_as_bytes.side_effect = download
        return blob

    def records(self, owner, collection):
        uid = owner.removeprefix('firebase:')
        return [{**doc.to_dict(), 'id': doc.id}
                for doc in self.db.collection('users').document(uid).collection(collection).stream()]

    def put(self, collection, ident, **data):
        self.db.collection('users').document(UID).collection(collection).document(ident).set({'ownerId': UID, **data})

    def doc(self, collection, ident):
        return self.db.collection('users').document(UID).collection(collection).document(ident).get().to_dict()


def image(cid): return f'gs://{BUCKET}/users/{UID}/images/{cid}.jpg'


class ProjectFixture:
    """A finished app-style project: prompt, one concept job, one 3D job, one chat turn."""
    def build(self, studio, pid='mp-1', cid='mc-1', mj='mj-1', job_status='done'):
        studio.put('studioProjects', pid, name='Dragon', prompt='a dragon', createdAt=1)
        studio.put('studioConcepts', cid, projectId=pid, imageUrl=image(cid), createdAt=2)
        studio.put('studioJobs', 'cj-' + cid[3:], projectId=pid, kind='concepts', status='done', createdAt=2,
                   concepts=[{'id': cid, 'imageUrl': image(cid)}])
        studio.put('studioJobs', mj, projectId=pid, kind='model', status=job_status, createdAt=3)
        studio.put('studioConversations', 'turn-1', projectId=pid, text='make it red', createdAt=2)
        studio.put('mobileCreations', 'concept:' + cid, projectId=pid, kind='Concept image',
                   previewStoragePath=f'users/{UID}/images/{cid}.jpg', createdAt=2)
        studio.put('mobileCreations', 'model:' + mj, projectId=pid, kind='3D object', conceptIds=[cid],
                   previewStoragePath=f'users/{UID}/images/{cid}.jpg',
                   modelStoragePath=f'users/{UID}/models/{mj}.glb', createdAt=3)
        studio.blobs[f'users/{UID}/images/{cid}.jpg'] = b'jpg'
        studio.blobs[f'users/{UID}/models/{mj}.glb'] = b'glb'


class DeleteTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        ProjectFixture().build(self.studio, pid='mp-2', cid='mc-2', mj='mj-2')
        self.service = creations.CloudCreations(self.studio)

    def test_delete_project_removes_every_record_and_file_of_that_project_only(self):
        result = self.service.delete_project(OWNER, 'mp-1')
        self.assertEqual(result, dict(deleted=True, id='mp-1', images=1, models=1, animations=0, jobs=2))
        for collection in ('studioProjects', 'studioConcepts', 'studioJobs', 'studioConversations', 'mobileCreations'):
            left = [r for r in self.studio.records(OWNER, collection) if r.get('projectId') == 'mp-1' or r['id'] == 'mp-1']
            self.assertEqual(left, [], collection)
        self.assertEqual(sorted(self.studio.blobs), [f'users/{UID}/images/mc-2.jpg', f'users/{UID}/models/mj-2.glb'])
        self.assertIsNotNone(self.studio.doc('studioProjects', 'mp-2'))

    def test_delete_refuses_while_a_job_is_running(self):
        self.studio.put('studioJobs', 'mj-1', projectId='mp-1', kind='model', status='running')
        with self.assertRaises(HTTPException) as caught:
            self.service.delete_project(OWNER, 'mp-1')
        self.assertEqual(caught.exception.status_code, 409)
        self.assertIsNotNone(self.studio.doc('studioProjects', 'mp-1'))

    def test_delete_asset_removes_model_file_but_keeps_shared_concept_image(self):
        self.service.delete_asset(OWNER, 'mj-1')
        self.assertIsNone(self.studio.doc('mobileCreations', 'model:mj-1'))
        self.assertIsNone(self.studio.doc('studioJobs', 'mj-1'))
        self.assertNotIn(f'users/{UID}/models/mj-1.glb', self.studio.blobs)
        self.assertIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)
        self.assertIsNotNone(self.studio.doc('studioConcepts', 'mc-1'))

    def test_delete_concept_leaves_the_conversation_and_keeps_file_a_model_still_uses(self):
        self.service.delete_concept(OWNER, 'mc-1')
        self.assertIsNone(self.studio.doc('studioConcepts', 'mc-1'))
        self.assertIsNone(self.studio.doc('mobileCreations', 'concept:mc-1'))
        self.assertEqual(self.studio.doc('studioJobs', 'cj-1')['concepts'], [])
        self.assertEqual(len(self.studio.doc('studioJobs', 'cj-2')['concepts']), 1)
        self.assertIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)  # still the 3D preview

    def test_delete_concept_file_goes_when_no_model_uses_it(self):
        self.service.delete_asset(OWNER, 'mj-1')
        self.service.delete_concept(OWNER, 'mc-1')
        self.assertNotIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)

    def test_other_accounts_cannot_be_reached(self):
        with self.assertRaises(HTTPException) as caught:
            self.service.delete_project('firebase:user_bob', 'mp-1')
        self.assertEqual(caught.exception.status_code, 404)
        with self.assertRaises(HTTPException):
            self.service.concept_image('firebase:user_bob', 'mc-1')


class ReadAndUpdateTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        self.service = creations.CloudCreations(self.studio)

    def test_project_view_links_everything_through_the_api(self):
        project = self.service.project(OWNER, 'mp-1')
        self.assertEqual(project['concepts'][0]['imageUrl'], '/api/v1/concepts/mc-1/image')
        self.assertEqual(project['models'][0]['downloadUrl'], '/api/v1/assets/mj-1/download')
        self.assertEqual([j['id'] for j in project['jobs']], ['cj-1', 'mj-1'])
        self.assertEqual(project['conversation'][0]['text'], 'make it red')

    def test_rename_and_image_download(self):
        self.assertEqual(self.service.rename(OWNER, 'mp-1', '  Fire dragon ')['name'], 'Fire dragon')
        self.assertEqual(self.service.concept_image(OWNER, 'mc-1'), b'jpg')


class OneStepTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        self.service = creations.CloudCreations(self.studio)
        self.quote = dict(conceptTokens=33, modelTokens=46, maxTokens=79, expiresAt=0)

    def body(self, **kw):
        return creations.CreationRequest(**{'idempotencyKey': 'agent-request-1', 'prompt': 'a fire dragon', 'maxTokens': 79, **kw})

    def test_cap_below_quote_is_rejected_before_anything_is_created(self):
        with patch.object(creations, 'quote', return_value=self.quote):
            with self.assertRaises(HTTPException) as caught:
                self.service.create(OWNER, self.body(maxTokens=50))
        self.assertEqual(caught.exception.status_code, 409)
        self.assertIn('at least 79', caught.exception.detail)
        self.assertEqual(self.studio.records(OWNER, 'studioProjects'), [])

    def test_wallet_must_cover_the_whole_creation(self):
        with patch.object(creations, 'quote', return_value=self.quote), \
             patch.object(creations.CloudBilling, 'wallet', return_value={'available': 60}):
            with self.assertRaises(HTTPException) as caught:
                self.service.create(OWNER, self.body())
        self.assertEqual(caught.exception.status_code, 402)

    def test_create_makes_project_and_concept_job_carrying_the_3d_request(self):
        with patch.object(creations, 'quote', return_value=self.quote), \
             patch.object(creations.CloudBilling, 'wallet', return_value={'available': 500}), \
             patch.object(creations.CloudProjects, 'create', return_value={'id': 'mp-9'}) as make_project, \
             patch.object(creations.CloudConcepts, 'create', return_value={'id': 'cj-9'}) as make_concepts, \
             patch.object(creations.CloudCreations, 'status', return_value={'id': 'cj-9'}):
            self.service.create(OWNER, self.body(engine='trellis-2'), environment='PRODUCTION')
        self.assertEqual(make_project.call_args.kwargs['client_id'], 'creation:agent-request-1')
        args, kwargs = make_concepts.call_args
        self.assertEqual(args[1], 'mp-9')
        self.assertEqual(args[2].maxTokens, 33)
        self.assertEqual(kwargs['auto_model'], dict(engine='trellis-2', quality='default', effort='high', environment='PRODUCTION'))

    def test_reprompt_reuses_the_project(self):
        with patch.object(creations, 'quote', return_value=self.quote), \
             patch.object(creations.CloudBilling, 'wallet', return_value={'available': 500}), \
             patch.object(creations.CloudProjects, 'create') as make_project, \
             patch.object(creations.CloudConcepts, 'create', return_value={'id': 'cj-9'}) as make_concepts, \
             patch.object(creations.CloudCreations, 'status', return_value={'id': 'cj-9'}):
            self.service.create(OWNER, self.body(projectId='mp-1', prompt='now make it blue'))
        make_project.assert_not_called()
        self.assertEqual(make_concepts.call_args.args[1], 'mp-1')


class ContinueToModelTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        self.concepts = creations.CloudConcepts(self.studio)
        self.public, self.private = self.concepts.refs(UID, 'cj-1')
        self.private.set({'autoModel': dict(engine='rodin', quality='default', effort='high', environment=None)})
        self.env = patch.dict('os.environ', {'CRAFT_MODEL_JOBS_ENABLED': '1', 'FAL_KEY': 'x'})
        self.env.start()

    def tearDown(self):
        self.env.stop()

    def job(self, status):
        self.public.set({'ownerId': UID, 'projectId': 'mp-1', 'status': status, 'concepts': [{'id': 'mc-1'}]})

    def test_waits_until_the_concept_job_settles(self):
        self.job('running')
        with patch.object(creations.CloudModelJobs, 'create') as make_model:
            creations.continue_to_model(self.studio, UID, 'cj-1')
        make_model.assert_not_called()

    def test_starts_3d_on_the_first_image_with_a_repeat_safe_key(self):
        self.job('done')
        with patch.object(creations.CloudModelJobs, 'create', return_value={'id': 'mj-x'}) as make_model:
            creations.continue_to_model(self.studio, UID, 'cj-1')
            creations.continue_to_model(self.studio, UID, 'cj-1')
        owner, concept_id, body = make_model.call_args.args
        self.assertEqual((owner, concept_id, body.idempotencyKey), (OWNER, 'mc-1', 'auto:cj-1'))
        self.assertEqual({c.args[2].idempotencyKey for c in make_model.call_args_list}, {'auto:cj-1'})
        self.assertEqual(self.public.get().to_dict()['modelJobId'], 'mj-x')

    def test_not_enough_tokens_is_recorded_not_retried(self):
        self.job('done')
        with patch.object(creations.CloudModelJobs, 'create', side_effect=HTTPException(402, 'Not enough Tokens.')):
            creations.continue_to_model(self.studio, UID, 'cj-1')
        self.assertEqual(self.public.get().to_dict()['autoModelError'], 'Not enough Tokens.')
        status = creations.CloudCreations(self.studio).status(OWNER, 'cj-1')
        self.assertEqual((status['stage'], status['error']), ('failed', 'Not enough Tokens.'))

    def test_ordinary_app_concept_jobs_are_left_alone(self):
        self.private.set({})
        self.job('done')
        with patch.object(creations.CloudModelJobs, 'create') as make_model:
            creations.continue_to_model(self.studio, UID, 'cj-1')
        make_model.assert_not_called()


class StatusTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        self.service = creations.CloudCreations(self.studio)
        self.mj = creations.model_job_id(UID, 'cj-1')

    def concept(self, **kw):
        self.studio.put('studioJobs', 'cj-1', **{'projectId': 'mp-1', 'status': 'done', 'charged': 17,
                                                  'concepts': [{'id': 'mc-1', 'label': 'Concept 1'}], **kw})

    def test_progress_moves_from_image_to_3d_to_done(self):
        self.concept(status='running', progress=50, charged=0, reserved=33, concepts=[])
        self.assertEqual(self.service.status(OWNER, 'cj-1')['stage'], 'concepts')
        self.concept()
        self.assertEqual(self.service.status(OWNER, 'cj-1')['stage'], 'model')
        self.studio.put('studioJobs', self.mj, status='running', progress=50, reserved=46)
        running = self.service.status(OWNER, 'cj-1')
        self.assertEqual((running['stage'], running['progress'], running['tokens']), ('model', 70, 63))
        self.studio.put('studioJobs', self.mj, status='done', progress=100, charged=46)
        done = self.service.status(OWNER, 'cj-1')
        self.assertEqual(done['stage'], 'done')
        self.assertEqual(done['asset']['downloadUrl'], f'/api/v1/assets/{self.mj}/download')
        self.assertEqual(done['concepts'][0]['imageUrl'], '/api/v1/concepts/mc-1/image')

    def test_unknown_or_foreign_ids_are_not_found(self):
        with self.assertRaises(HTTPException):
            self.service.status(OWNER, 'cj-missing')
        with self.assertRaises(HTTPException):
            self.service.status(OWNER, 'mp-1')


class RouteScopeTests(unittest.TestCase):
    """Full access must never imply permanent deletion."""
    def setUp(self):
        self.client = TestClient(api.app)
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        self.patches = [patch('server.api_keys.firestore.transactional', side_effect=lambda fn: fn),
                        patch.object(api, 'studio', return_value=self.studio),
                        patch.object(api_keys, 'request_ref'),
                        patch('firebase_admin.auth.get_user', return_value=Mock(disabled=False))]
        for p in self.patches:
            started = p.start()
            if p.attribute == 'request_ref': started.return_value.get.return_value.exists = False

    def tearDown(self):
        for p in self.patches: p.stop()

    def key(self, scopes):
        return {'Authorization': 'Bearer ' + api_keys.create_api_key(self.studio.db, UID, 'k', scopes=scopes)['key']}

    def test_full_access_key_cannot_delete(self):
        res = self.client.delete('/api/v1/projects/mp-1', headers=self.key(['*']))
        self.assertEqual(res.status_code, 403, res.text)
        self.assertIsNotNone(self.studio.doc('studioProjects', 'mp-1'))

    def test_delete_scope_deletes(self):
        res = self.client.delete('/api/v1/projects/mp-1', headers=self.key(['*', 'assets:delete']))
        self.assertEqual(res.status_code, 200, res.text)
        self.assertIsNone(self.studio.doc('studioProjects', 'mp-1'))

    def test_full_access_reads_renames_and_downloads_images(self):
        headers = self.key(['*'])
        self.assertEqual(self.client.get('/api/v1/projects/mp-1', headers=headers).json()['name'], 'Dragon')
        self.assertEqual(self.client.patch('/api/v1/projects/mp-1', json={'name': 'Red'}, headers=headers).json()['name'], 'Red')
        image = self.client.get('/api/v1/concepts/mc-1/image', headers=headers)
        self.assertEqual((image.status_code, image.content, image.headers['content-type']), (200, b'jpg', 'image/jpeg'))

    def test_read_only_key_cannot_rename(self):
        res = self.client.patch('/api/v1/projects/mp-1', json={'name': 'x'}, headers=self.key(['assets:read']))
        self.assertEqual(res.status_code, 403)

    def test_assets_newest_first_with_legacy_millisecond_timestamps(self):
        self.studio.put('mobileCreations', 'model:mj-new', projectId='mp-1', kind='3D object', createdAt=1_789_777_000,
                        modelStoragePath=f'users/{UID}/models/mj-new.glb')
        self.studio.put('mobileCreations', 'model:a-legacy', projectId='mp-1', kind='3D object', createdAt=1_789_405_222_017,
                        modelStoragePath=f'users/{UID}/models/a-legacy.glb')  # older record, stored in milliseconds
        owned = self.client.get('/api/v1/assets', headers=self.key(['*'])).json()['owned']
        self.assertEqual([a['id'] for a in owned], ['mj-new', 'a-legacy', 'mj-1'])
        self.assertEqual(owned[1]['createdAt'], 1_789_405_222.017)
        self.assertEqual(owned[0]['projectId'], 'mp-1')

if __name__ == '__main__':
    unittest.main()
