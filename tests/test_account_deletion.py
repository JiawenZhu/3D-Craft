import os
import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
from server import account_deletion as deletion, firebase_api as api
from server.identity import require_claims

class DeletionTests(unittest.TestCase):
    def test_recent_owner_sign_in_is_required(self):
        for stamp in (None, True, 0, 1001, '999'):
            with self.assertRaises(HTTPException): deletion.recent_sign_in({'auth_time': stamp}, now=1000)
        deletion.recent_sign_in({'auth_time': 701}, now=1000)
        with self.assertRaises(HTTPException): deletion.request_ref(Mock(), '../other')

    def test_owner_comes_from_verified_claims_not_body(self):
        client = TestClient(api.app)
        self.assertEqual(client.post('/api/mobile/account/delete', json={'confirm': True}).status_code,401)
        api.app.dependency_overrides[require_claims] = lambda: {'uid': 'alice', 'auth_time': 1000}
        try:
            with patch.object(api, 'studio'), patch.object(api, 'request_deletion', return_value={'status':'pending'}) as request:
                self.assertEqual(client.post('/api/mobile/account/delete',json={'confirm':False}).status_code,422)
                result=client.post('/api/mobile/account/delete',json={'confirm':True,'uid':'bob'})
                self.assertEqual(result.status_code,202)
                self.assertEqual(request.call_args.args[1]['uid'],'alice')
        finally: api.app.dependency_overrides.clear()

    def test_public_worker_requires_google_service_identity(self):
        self.assertEqual(TestClient(api.app).post('/internal/account-deletions/alice').status_code,401)
        with patch.dict(os.environ, {'CRAFT_TASK_IDENTITY':'worker@example.com','CRAFT_TASK_ORIGIN':'https://worker.example.com'}):
            with patch('google.oauth2.id_token.verify_oauth2_token',return_value={'email':'attacker@example.com','email_verified':True}):
                with self.assertRaises(HTTPException): deletion.verify_worker('Bearer signed-token')

    def test_existing_pending_request_is_requeued_without_new_identity_or_marker(self):
        db=Mock(); ref=db.collection.return_value.document.return_value
        ref.get.return_value.exists=True;ref.get.return_value.to_dict.return_value={'state':'pending'}
        with patch.object(deletion,'enqueue') as queue:
            self.assertEqual(deletion.request_deletion(db,{'uid':'alice'}),{'status':'pending'})
            queue.assert_called_once_with('alice');ref.create.assert_not_called()
        with self.assertRaises(HTTPException):deletion.ensure_active(db,'alice')

    def test_missing_configuration_does_not_lock_account(self):
        db=Mock();ref=db.collection.return_value.document.return_value;ref.get.return_value.exists=False
        with patch.dict(os.environ,{'CRAFT_TASK_ORIGIN':'','CRAFT_TASK_IDENTITY':''}),patch.object(deletion,'recent_sign_in'):
            with self.assertRaises(HTTPException):deletion.request_deletion(db,{'uid':'alice'})
        ref.create.assert_not_called()

    def test_unrequested_account_is_never_erased(self):
        cloud=Mock();ref=cloud.db.collection.return_value.document.return_value;ref.get.return_value.exists=False
        with patch.object(deletion.auth,'delete_user') as remove:
            with self.assertRaises(HTTPException):deletion.erase_account(cloud,'alice')
            remove.assert_not_called();cloud.bucket.list_blobs.assert_not_called()

    def test_queue_failure_does_not_lock_account(self):
        db=Mock();ref=db.collection.return_value.document.return_value;ref.get.return_value.exists=False
        with patch.dict(os.environ,{'CRAFT_TASK_ORIGIN':'https://worker.example.com','CRAFT_TASK_IDENTITY':'worker@example.com'}),patch.object(deletion,'recent_sign_in'),patch.object(deletion,'enqueue',side_effect=RuntimeError('Queue unavailable')):
            with self.assertRaises(RuntimeError):deletion.request_deletion(db,{'uid':'alice'})
        ref.create.assert_not_called()

    def test_completed_request_is_noop(self):
        cloud=Mock();ref=cloud.db.collection.return_value.document.return_value
        ref.get.return_value.exists=True;ref.get.return_value.to_dict.return_value={'state':'completed'}
        with patch.object(deletion,'delete_customer') as provider:
            self.assertEqual(deletion.erase_account(cloud,'alice'),{'status':'completed'})
            provider.assert_not_called();cloud.bucket.list_blobs.assert_not_called()

    def test_revenuecat_uses_scoped_customer_key_and_missing_customer_is_success(self):
        with patch.dict(os.environ,{'REVENUECAT_DELETION_API_KEY':'test-secret','REVENUECAT_PROJECT_ID':'projtest'}),patch.object(deletion.requests,'delete') as request:
            request.return_value.status_code=404
            deletion.delete_customer('alice')
            self.assertEqual(request.call_args.args[0],'https://api.revenuecat.com/v2/projects/projtest/customers/alice')
            self.assertEqual(request.call_args.kwargs['headers'],{'Authorization':'Bearer test-secret'})
            request.return_value.raise_for_status.assert_not_called()
            request.return_value.status_code=503
            request.return_value.raise_for_status.side_effect=RuntimeError('Provider unavailable')
            with self.assertRaises(RuntimeError):deletion.delete_customer('alice')

    def test_failure_keeps_identity_for_retry_and_retry_skips_completed_steps(self):
        cloud=Mock(); ref=Mock();ref.get.return_value.exists=True
        state={'state':'pending','requestedAt':1}
        ref.get.return_value.to_dict.side_effect=lambda:dict(state)
        ref.update.side_effect=lambda values:state.update(values)
        ref.set.side_effect=lambda values:state.update(values)
        cloud.bucket.list_blobs.return_value=[]
        cloud.db.collection.return_value.where.return_value.stream.return_value=[]
        cloud.db.collection.return_value.list_documents.return_value=[]
        with patch.object(deletion,'request_ref',return_value=ref),patch.object(deletion,'firebase_app'),patch.object(deletion.auth,'update_user'),patch.object(deletion.auth,'revoke_refresh_tokens'),patch.object(deletion.auth,'delete_user') as remove,patch.object(deletion,'delete_customer') as provider:
            cloud.db.recursive_delete.side_effect=RuntimeError('temporary database outage')
            with self.assertRaises(RuntimeError): deletion.erase_account(cloud,'alice')
            self.assertTrue(state['filesDeleted']);provider.assert_not_called()
            self.assertNotIn('privateDataDeleted',state);remove.assert_not_called()
            cloud.db.recursive_delete.side_effect=None
            self.assertEqual(deletion.erase_account(cloud,'alice'),{'status':'completed'})
            provider.assert_called_once_with('alice');remove.assert_called_once()
            cloud.bucket.list_blobs.assert_called_once_with(prefix='users/alice/')

if __name__=='__main__':unittest.main()
