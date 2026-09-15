import base64
import hashlib
import json
import struct
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch, Mock
from fastapi import HTTPException
from fastapi.testclient import TestClient
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from server.firebase_usage import reserve, settle
from server.firebase_model_jobs import select_views, ModelRequest, CloudModelJobs
from server import cloud_model_provider as provider, firebase_api as api
from server.identity import require_claims


class ReservationTests(unittest.TestCase):
    def wallet(self):
        return dict(available=200,subscriptionAvailable=50,subscriptionTransaction='SANDBOX:one',
                    subscriptionExpiresAt=2000,reserved=0,environment='SANDBOX')

    def test_success_spends_allowance_before_packs_and_conserves_balance(self):
        before=self.wallet(); held,allocation=reserve(before,70,1000)
        self.assertEqual((held['available'],held['subscriptionAvailable'],held['reserved']),(180,0,70))
        final=settle(held,allocation,70,1001)
        self.assertEqual((final['available'],final['subscriptionAvailable'],final['reserved']),(180,0,0))
        self.assertEqual(before['available'],200)

    def test_failure_restores_only_unexpired_unrefunded_original_period(self):
        for changed,now,refunded,expected in [({},1001,False,50),({},2000,False,0),
            ({'subscriptionTransaction':'SANDBOX:two','subscriptionAvailable':850,'subscriptionExpiresAt':3000},1001,False,850),
            ({},1001,True,0)]:
            held,allocation=reserve(self.wallet(),70,1000)
            final=settle({**held,**changed},allocation,0,now,refunded)
            self.assertEqual(final['available'],200);self.assertEqual(final['subscriptionAvailable'],expected)
            self.assertEqual(final['reserved'],0)

    def test_partial_charge_and_independent_concurrent_reservations(self):
        first,a=reserve(self.wallet(),70,1000);second,b=reserve(first,100,1000)
        one=settle(second,a,30,1001);two=settle(one,b,100,1002)
        self.assertEqual((two['available'],two['subscriptionAvailable'],two['reserved']),(100,20,0))
        with self.assertRaises(ValueError):settle(two,b,100,1003)

    def test_insufficient_or_expired_credit_never_reserves(self):
        with self.assertRaises(HTTPException) as e: reserve(self.wallet(),230,2000)
        self.assertEqual(e.exception.status_code,402)
        for bad in (0,-1,True,2.5):
            with self.assertRaises(ValueError):reserve(self.wallet(),bad,1000)
        held,a=reserve(self.wallet(),70,1000)
        for charge in (-1,71,True):
            with self.assertRaises(ValueError):settle(held,a,charge,1001)


class ProviderTests(unittest.TestCase):
    def test_white_and_textured_provider_inputs_are_distinct(self):
        for engine,textured in [('hunyuan3d-2-white',False),('hunyuan3d-2.1',True)]:
            endpoint,args=provider.arguments(engine,['a','b','c'],['front','back','left'],'high','default','description')
            self.assertTrue(endpoint.endswith('/multi-view'));self.assertEqual(args['textured_mesh'],textured)
            self.assertEqual(args['left_image_url'],'c');self.assertNotIn('prompt',args)
        with self.assertRaises(ValueError):provider.arguments('hunyuan3d-2.1',['a','b'],['front','back'],'high','default','')
        _,args=provider.arguments('rodin',['a'],'front','high','default','exact user description')
        self.assertEqual(args['prompt'],'exact user description')
        self.assertFalse(args['use_hyper'])

    def test_paid_post_has_no_client_retry(self):
        with patch.object(provider.requests,'post',side_effect=TimeoutError),patch.object(provider,'headers',return_value={}):
            with self.assertRaises(TimeoutError):provider.submit('fal-ai/test',{},'https://example.com/hook')
            provider.requests.post.assert_called_once()

    def test_valid_signature_binds_request_user_timestamp_and_body(self):
        key=Ed25519PrivateKey.generate();public=key.public_key().public_bytes(Encoding.Raw,PublicFormat.Raw)
        raw=b'{"status":"OK"}';stamp=str(int(time.time()))
        fields=['req-1','user-1',stamp,hashlib.sha256(raw).hexdigest()]
        signature=key.sign('\n'.join(fields).encode()).hex()
        headers=dict(zip(('x-fal-webhook-request-id','x-fal-webhook-user-id','x-fal-webhook-timestamp','x-fal-webhook-signature'),fields[:3]+[signature]))
        with patch.object(provider,'_keys',(time.time(),[{'x':base64.urlsafe_b64encode(public).decode()}])):
            self.assertEqual(provider.verify_callback(headers,raw),'req-1')
            with self.assertRaises(HTTPException):provider.verify_callback(headers,raw+b' ')
            for name,value in [('x-fal-webhook-request-id','req-2'),('x-fal-webhook-user-id','user-2'),('x-fal-webhook-timestamp','1')]:
                with self.assertRaises(HTTPException):provider.verify_callback({**headers,name:value},raw)

    def test_only_standalone_glb_and_provider_cdn_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'model.glb'
            for external in (False,True):
                doc={'asset':{'version':'2.0'},'meshes':[{'primitives':[]}],'buffers':[{'uri':'https://evil.example/data'}] if external else []}
                data=json.dumps(doc).encode();data+=b' '*((-len(data))%4)
                path.write_bytes(struct.pack('<4sIIII',b'glTF',2,len(data)+20,len(data),0x4E4F534A)+data)
                if external:
                    with self.assertRaises(ValueError):provider.validate_glb(path)
                else:provider.validate_glb(path)
            for url in ('http://fal.media/model.glb','https://evilfal.media/model.glb','https://fal.media.evil.test/model.glb','https://user@fal.media/model.glb','https://fal.media:444/model.glb'):
                with patch.object(provider.requests,'get') as get:
                    with self.assertRaises(ValueError):provider.download_mesh({'model_glb':{'url':url}},path)
                    get.assert_not_called()


class JobBoundaryTests(unittest.TestCase):
    def test_multiview_requires_verified_same_subject_siblings(self):
        concepts={i:dict(id=i,viewSetId='set',direction=d) for i,d in zip('abc',['front','back','left'])}
        source=dict(status='done',validation={'usable':True})
        self.assertEqual(len(select_views('a',['a','b','c'],concepts,source)),3)
        for ids,job in [(['a','a'],source),(['b'],source),(['a','b'],None)]:
            with self.assertRaises(HTTPException):select_views('a',ids,concepts,job)
        concepts['b']['viewSetId']='other'
        with self.assertRaises(HTTPException):select_views('a',['a','b'],concepts,source)

    def test_paths_and_ids_cannot_escape_owner(self):
        service=CloudModelJobs(Mock())
        for path in ('gs://another/users/alice/a.jpg','https://example.com/a.jpg','gs://'+api.BUCKET+'/users/bob/a.jpg'):
            with self.assertRaises(HTTPException):service.image_path('alice',path)
        with self.assertRaises(HTTPException):service.refs('alice','../anything')

    def test_routes_require_identity_and_do_not_trust_callback_body_alone(self):
        client=TestClient(api.app)
        self.assertEqual(client.post('/api/mobile/concepts/example/model',json={'idempotencyKey':'request-1'}).status_code,401)
        with patch.object(api,'verify_worker',side_effect=HTTPException(401,'Required')):
            self.assertEqual(client.post('/internal/model-jobs/alice/mj-'+'a'*64).status_code,401)
        with patch.object(provider,'verify_callback',side_effect=HTTPException(401,'Invalid')):
            self.assertEqual(client.post('/api/models/callback/alice/job/token',json={'request_id':'fake','status':'OK'}).status_code,401)
        with patch.object(provider,'verify_callback',return_value='signed-id'):
            self.assertEqual(client.post('/api/models/callback/alice/job/token',json={'request_id':'different-id','status':'OK'}).status_code,422)


if __name__=='__main__':unittest.main()
