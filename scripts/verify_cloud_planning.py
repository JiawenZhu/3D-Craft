"""Disposable Firestore acceptance; optional small real Vertex provider request.

CRAFT_RUN_FIRESTORE_INTEGRATION=1 [CRAFT_TEST_VERTEX=1] python scripts/verify_cloud_planning.py
Only fixture wallets are funded. No StoreKit purchases or other users' data.
"""
import io
import os
import secrets
import requests
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_RUN_FIRESTORE_INTEGRATION')!='1':raise SystemExit('Set CRAFT_RUN_FIRESTORE_INTEGRATION=1')
import firebase_admin
from firebase_admin import credentials, firestore, storage, auth
from google.oauth2.credentials import Credentials
from PIL import Image
from fastapi import HTTPException
from server.firebase_planning import CloudPlanning, PromptRequest, LEASE
from server.firebase_studio import FirebaseStudio, BUCKET
from server import cloud_planner_provider as provider

class CLIIdentity(credentials.Base):
    def get_credential(self):
        return Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id=provider.PROJECT)

identity=CLIIdentity()
app=firebase_admin.initialize_app(identity,{'projectId':provider.PROJECT,'storageBucket':BUCKET})
db=firestore.client(app=app);bucket=storage.bucket(app=app)
uid='craft-planning-fixture-'+uuid.uuid4().hex;owner='firebase:'+uid
clock=[time.time()];service=CloudPlanning(FirebaseStudio(db,bucket),clock=lambda:clock[0])
user=db.collection('users').document(uid)
wallet=service.billing.private(uid,'wallet')
image=io.BytesIO();Image.new('RGB',(40,40),'white').save(image,format='PNG')
category='files' if os.getenv('CRAFT_TEST_MIGRATED_IMAGE')=='1' else 'images'
path=f'users/{uid}/{category}/reference.png';blob=bucket.blob(path)
answer={'prompt':'Preserve the garden swing, its canopy, frame and seat.','model':provider.MODEL,'tokens':1,'providerUsd':'.001','usage':{'input':100,'output':100}}


def deny(fn,code):
    try:fn()
    except HTTPException as exc:assert exc.status_code==code,(exc.status_code,code)
    else:raise AssertionError('Expected denial')

try:
    user.set({'fixture':True});wallet.set({'available':200,'reserved':0})
    blob.upload_from_string(image.getvalue(),content_type='image/png',if_generation_match=0)
    service.projects.ref(uid,'studioConcepts','source').set({'id':'source','ownerId':uid,'imageUrl':'gs://'+BUCKET+'/'+path})
    request=PromptRequest(idempotencyKey='stable-request',prompt='Keep the swing canopy and frame',maxTokens=2)
    with patch('server.firebase_planning.enqueue'):
        with ThreadPoolExecutor(4) as pool:created=list(pool.map(lambda _: service.create(owner,'source',request),range(4)))
        jid=created[0]['id'];assert all(d==created[0] for d in created)
        assert wallet.get().to_dict()['reserved']==2
        deny(lambda:service.create(owner,'source',request.model_copy(update={'prompt':'Other words'})),409)
        deny(lambda:service.create(owner,'source',request.model_copy(update={'idempotencyKey':'new-price','maxTokens':1})),409)
        deny(lambda:service.get('firebase:another-fixture',jid),404)
        with patch.object(provider,'preflight',return_value=100),patch.object(provider,'generate',return_value=answer) as generate:
            result=service.run(uid,jid);assert result['status']=='done' and result['charged']==1
            for _ in range(3):assert service.run(uid,jid)['prompt']==answer['prompt']
            generate.assert_called_once()
        assert wallet.get().to_dict()['available']==199 and wallet.get().to_dict()['reserved']==0
        # Simulate a process crash after authorization to call: no second POST.
        crash=service.create(owner,'source',request.model_copy(update={'idempotencyKey':'crashed-request'}))
        token,_=service.claim(uid,crash['id']);service.advance(uid,crash['id'],token,'queued',{'phase':'calling'})
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as generate:
            assert service.run(uid,crash['id'])['status']=='failed';generate.assert_not_called()
        assert wallet.get().to_dict()['available']==199 and wallet.get().to_dict()['reserved']==0
        # A saved answer survives a crash before the wallet settlement.
        recovered=service.create(owner,'source',request.model_copy(update={'idempotencyKey':'answered-request'}))
        token,_=service.claim(uid,recovered['id']);service.advance(uid,recovered['id'],token,'queued',{'phase':'answered','answer':answer})
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as generate:
            assert service.run(uid,recovered['id'])['charged']==1;generate.assert_not_called()
        assert wallet.get().to_dict()['available']==198 and wallet.get().to_dict()['reserved']==0
        print('PASS: concurrent idempotency, price consent, ownership, single charge, crash refund, saved-answer recovery')
        if os.getenv('CRAFT_TEST_VERTEX')=='1':
            clock[0]=time.time()
            live=service.create(owner,'source',request.model_copy(update={'idempotencyKey':'real-vertex-request'}))
            with patch.object(provider.google.auth,'default',return_value=(identity.get_credential(),provider.PROJECT)):
                result=service.run(uid,live['id'])
            assert result['status']=='done',result
            assert 'swing' in result['prompt'].lower() and 'swim' not in result['prompt'].lower(),result
            print('PASS: real Vertex image + words, usage settlement',{'charged':result['charged'],'prompt':result['prompt']})
        if os.getenv('CRAFT_CHECK_DEPLOYED_PLANNING')=='1':
            password=secrets.token_urlsafe(30)
            auth.create_user(uid=uid,email=uid+'@example.com',password=password,app=app)
            config=requests.get('https://3d-craft.web.app/__/firebase/init.json',timeout=30).json()
            login=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',params={'key':config['apiKey']},json={'email':uid+'@example.com','password':password,'returnSecureToken':True},timeout=30)
            login.raise_for_status();headers={'Authorization':'Bearer '+login.json()['idToken']}
            base='https://3d-craft.web.app/api/mobile'
            quote=requests.get(base+'/planning/quote',headers=headers,timeout=30);quote.raise_for_status()
            body=request.model_copy(update={'idempotencyKey':'deployed-vertex-request','maxTokens':quote.json()['maxTokens']}).model_dump()
            before=wallet.get().to_dict()['available']
            def submit(_):
                response=requests.post(base+'/concepts/source/model-prompt',headers=headers,json=body,timeout=45)
                assert response.status_code==200,response.text[:300]
                return response.json()
            with ThreadPoolExecutor(2) as pool: results=list(pool.map(submit,range(2)))
            jid=results[0]['id'];assert results[1]['id']==jid
            end=time.monotonic()+150
            while time.monotonic()<end:
                response=requests.get(base+'/planning/'+jid,headers=headers,timeout=30)
                response.raise_for_status();result=response.json()
                if result['status'] in ('done','failed'):break
                time.sleep(2)
            assert result['status']=='done',result
            assert result['charged']<=quote.json()['maxTokens']
            assert wallet.get().to_dict()['available']==before-result['charged']
            assert wallet.get().to_dict()['reserved']==0
            assert submit(0)['id']==jid and wallet.get().to_dict()['available']==before-result['charged']
            private=f'https://firestore.googleapis.com/v1/projects/{provider.PROJECT}/databases/(default)/documents/users/{uid}/private/planningJobs/items/{jid}'
            assert requests.get(private,headers=headers,timeout=30).status_code==403
            assert requests.get(base+'/planning/'+jid,timeout=30).status_code==401
            print('PASS: canonical API, runtime service identity, Cloud Tasks, private results, final wallet and repeat POST',{'charged':result['charged']},flush=True)
        db.collection('accountDeletions').document(uid).set({'state':'queued'})
        deny(lambda:service.create(owner,'source',request.model_copy(update={'idempotencyKey':'deleted-request'})),403)
        assert wallet.get().to_dict()['reserved']==0
        print('PASS: account deletion barrier')
finally:
    db.recursive_delete(user)
    db.collection('accountDeletions').document(uid).delete()
    blob.delete()
    try: auth.delete_user(uid,app=app)
    except auth.UserNotFoundError: pass
    firebase_admin.delete_app(app)
    print('Fixture metadata and image removed.')
