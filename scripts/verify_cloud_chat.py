"""Disposable Firestore chat acceptance, optionally through the real deployed API.

CRAFT_RUN_FIRESTORE_INTEGRATION=1 [CRAFT_CHECK_DEPLOYED_CHAT=1] python scripts/verify_cloud_chat.py
The deployed option makes three small paid Vertex calls on fixture wallets only.
"""
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_RUN_FIRESTORE_INTEGRATION')!='1':raise SystemExit('Set CRAFT_RUN_FIRESTORE_INTEGRATION=1')
import requests
import firebase_admin
from firebase_admin import credentials, firestore, storage, auth
from fastapi import HTTPException
from google.oauth2.credentials import Credentials
from server.firebase_planning import CloudPlanning, ChatRequest, LEASE
from server.firebase_studio import FirebaseStudio, BUCKET
from server import cloud_planner_provider as provider

class CLIIdentity(credentials.Base):
    def __init__(self):
        self.value = Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id=provider.PROJECT)
    def get_credential(self): return self.value

app=firebase_admin.initialize_app(CLIIdentity(),{'projectId':provider.PROJECT,'storageBucket':BUCKET})
db=firestore.client(app=app);bucket=storage.bucket(app=app)
uid='craft-chat-fixture-'+uuid.uuid4().hex;owner='firebase:'+uid
clock=[time.time()];service=CloudPlanning(FirebaseStudio(db,bucket),clock=lambda:clock[0])
user=db.collection('users').document(uid);wallet=service.billing.private(uid,'wallet')
project=service.projects.ref(uid,'studioProjects','project')
answer={'reply':'Ready to make a concept.','brief':'A swing with a red frame and green canopy.',
        'ready':True,'suggestions':[],'model':provider.MODEL,'tokens':1,'providerUsd':'.001','usage':{'input':100,'output':100}}


def deny(fn,code):
    try:fn()
    except HTTPException as exc:assert exc.status_code==code,(exc.status_code,code)
    else:raise AssertionError('Expected rejection')

try:
    user.set({'fixture':True});wallet.set({'available':200,'reserved':0})
    project.set({'id':'project','ownerId':uid,'prompt':'A swing for a game.','name':'Chat acceptance','imageUrl':None})
    service.projects.ref(uid,'studioConversations','legacy').set({'id':'legacy','ownerId':uid,'projectId':'project',
        'text':'Use a red frame.','reply':'What color canopy?','brief':'A garden swing with a red frame.',
        'status':'done','createdAt':clock[0]-10})
    body=ChatRequest(clientId='stable-chat-request',text='Use a green canopy. Generate now.',maxTokens=4)
    with patch('server.firebase_planning.enqueue'):
        with ThreadPoolExecutor(4) as pool:created=list(pool.map(lambda _:service.create_chat(owner,'project',body),range(4)))
        jid=created[0]['id'];assert all(item['id']==jid for item in created)
        assert wallet.get().to_dict()['reserved']==4
        assert project.get().to_dict()['activeChatJobId']==jid
        deny(lambda:service.create_chat(owner,'project',body.model_copy(update={'clientId':'another-active-request'})),409)
        deny(lambda:service.create_chat(owner,'project',body.model_copy(update={'text':'Different'})),409)
        deny(lambda:service.create_chat('firebase:another-fixture','project',body),404)
        private=service.ref(uid,jid).get().to_dict()
        assert private['previousBrief']=='A garden swing with a red frame.'
        assert private['history'][-1]['text']==body.text
        assert any(t['text']=='Use a red frame.' for t in private['history'])
        with patch.object(provider,'preflight',return_value=100),patch.object(provider,'generate',return_value=answer) as generate:
            result=service.run(uid,jid);assert result['status']=='done'
            assert service.run(uid,jid)['brief']==answer['brief'];generate.assert_called_once()
        assert wallet.get().to_dict()['available']==199 and wallet.get().to_dict()['reserved']==0
        assert project.get().to_dict()['activeChatJobId'] is None
        public=service.projects.ref(uid,'studioConversations',jid).get().to_dict()
        assert public['status']=='done' and public['brief']==answer['brief'] and public['charged']==1
        assert 'history' not in public and 'answer' not in public and 'estimate' not in public
        assert service.create_chat(owner,'project',body)['status']=='done'
        assert project.get().to_dict()['creativeBrief']==answer['brief']
        clock[0]+=1
        second=service.create_chat(owner,'project',body.model_copy(update={'clientId':'second-chat-request','text':'Make the seat larger.'}))
        data=service.ref(uid,second['id']).get().to_dict()
        assert data['previousBrief']==answer['brief'] and data['history'][-1]['text']=='Make the seat larger.'
        # A worker crash after the paid-call authorization must not call again.
        token,_=service.claim(uid,second['id']);service.advance(uid,second['id'],token,'queued',{'phase':'calling'})
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as generate:
            assert service.run(uid,second['id'])['status']=='failed';generate.assert_not_called()
        assert wallet.get().to_dict()['available']==199 and wallet.get().to_dict()['reserved']==0
        assert project.get().to_dict()['activeChatJobId'] is None
        failed=service.projects.ref(uid,'studioConversations',second['id']).get().to_dict()
        assert failed['status']=='failed' and failed['text']=='Make the seat larger.'
        deny(lambda:service.create_chat(owner,'project',body.model_copy(update={'clientId':'too-low-price','maxTokens':1})),409)
        # Both failed messages and projects other than this one are excluded.
        service.projects.ref(uid,'studioConversations','other-project').set({'projectId':'other','text':'Unrelated','reply':'Ignore','brief':'Wrong brief','status':'done','createdAt':clock[0]})
        service.projects.ref(uid,'studioConcepts','wrong-project-image').set({'ownerId':uid,'projectId':'other','imageUrl':'gs://'+BUCKET+'/users/'+uid+'/images/no.png'})
        deny(lambda:service.create_chat(owner,'project',body.model_copy(update={'clientId':'wrong-reference','conceptId':'wrong-project-image'})),404)
        # The durable brief survives enough failures to push all successful
        # replies outside the bounded recent-history query.
        batch=db.batch()
        for index in range(25):
            batch.set(service.projects.ref(uid,'studioConversations','failed-'+str(index)),{'projectId':'project','text':'Failed retry','status':'failed','createdAt':clock[0]+index})
        batch.commit()
        recover=service.create_chat(owner,'project',body.model_copy(update={'clientId':'recover-saved-reply'}))
        assert service.ref(uid,recover['id']).get().to_dict()['previousBrief']==answer['brief']
        token,_=service.claim(uid,recover['id']);service.advance(uid,recover['id'],token,'queued',{'phase':'answered','answer':answer})
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as generate:
            assert service.run(uid,recover['id'])['status']=='done';generate.assert_not_called()
        assert wallet.get().to_dict()['available']==198 and wallet.get().to_dict()['reserved']==0
    print('PASS: serialized conversation, concurrent retries, legacy brief, scoped history, reference ownership, saved reply and crash refund',flush=True)

    if os.getenv('CRAFT_CHECK_DEPLOYED_CHAT')=='1':
        password=secrets.token_urlsafe(30)
        auth.create_user(uid=uid,email=uid+'@example.com',password=password,app=app)
        config=requests.get('https://3d-craft.web.app/__/firebase/init.json',timeout=30).json()
        login=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',params={'key':config['apiKey']},json={'email':uid+'@example.com','password':password,'returnSecureToken':True},timeout=30)
        login.raise_for_status();headers={'Authorization':'Bearer '+login.json()['idToken']}
        base='https://3d-craft.web.app/api/mobile'
        price=requests.get(base+'/planning/quote?kind=chat',headers=headers,timeout=30)
        price.raise_for_status();maximum=price.json()['maxTokens'];assert price.json()['kind']=='chat'
        def request_chat(project_id,text,ident,concept_id=None,repeat=False):
            body={'clientId':ident,'text':text,'plannerModel':provider.MODEL,'plannerEffort':'low','maxTokens':maximum,'conceptId':concept_id,'style':'Stylized'}
            before=wallet.get().to_dict()['available']
            def submit(_):
                response=requests.post(base+'/projects/'+project_id+'/chat',headers=headers,json=body,timeout=45)
                assert response.status_code==200,response.text[:300]
                return response.json()
            with ThreadPoolExecutor(2) as pool:results=list(pool.map(submit,range(2 if repeat else 1)))
            jid=results[0]['id'];assert all(r['id']==jid for r in results)
            end=time.monotonic()+180;result=results[0]
            while time.monotonic()<end and result['status'] not in ('done','failed'):
                time.sleep(2)
                response=requests.get(base+'/planning/'+jid,headers=headers,timeout=30);response.raise_for_status();result=response.json()
            assert result['status']=='done',result
            assert 0<result['charged']<=maximum
            assert wallet.get().to_dict()['available']==before-result['charged'] and wallet.get().to_dict()['reserved']==0
            assert submit(0)['id']==jid and wallet.get().to_dict()['available']==before-result['charged']
            projects=requests.get(base+'/projects',headers=headers,timeout=30).json()
            saved=next(p for p in projects if p['id']==project_id)
            turn=next(t for t in saved['conversation'] if t['id']==jid)
            assert turn['brief']==result['brief'] and turn['status']=='done'
            private=f'https://firestore.googleapis.com/v1/projects/{provider.PROJECT}/databases/(default)/documents/users/{uid}/private/planningJobs/items/{jid}'
            assert requests.get(private,headers=headers,timeout=30).status_code==403
            assert requests.get(base+'/planning/'+jid,timeout=30).status_code==401
            print('PASS: deployed reply',{'charged':result['charged'],'ready':result['ready'],'reply':result['reply'],'brief':result['brief']},flush=True)
            return result
        response=requests.post(base+'/projects',headers=headers,data={'prompt':'A garden swing for a game, with a red metal frame.','name':'Cloud chat acceptance','clientId':'deployed-text-project'},timeout=40)
        response.raise_for_status();live=response.json()
        request_chat(live['id'],'I want a stylized garden swing for a game, with a red metal frame. Help me decide the remaining details.','deployed-first-chat',repeat=True)
        second=request_chat(live['id'],'Use a green canopy and a wooden bench seat for two characters. Keep the red frame. No more questions, make the concept now.','deployed-second-chat')
        assert second['ready'] is True and 'swing' in second['brief'].lower()
        assert 'red' in second['brief'].lower() and 'green' in second['brief'].lower()
        with open('public/images/showcase/lantern-cat.png','rb') as image:
            response=requests.post(base+'/projects',headers=headers,data={'prompt':'An adventure-game character from this image.','name':'Cloud image-chat acceptance','clientId':'deployed-image-project'},files={'image':('reference.png',image,'image/png')},timeout=90)
        response.raise_for_status();visual=response.json()
        result=request_chat(visual['id'],'Describe the character in this reference image for a 3D game concept. Keep its visible species, clothing and handheld accessory. Use your judgement and proceed without questions.','deployed-image-chat',visual['concepts'][0]['id'])
        assert 'cat' in result['brief'].lower() and 'lantern' in result['brief'].lower()
        assert not list(user.collection('studioJobs').stream())
        print('PASS: canonical text chat, follow-up intent, image understanding, persistent project replies and no automatic generation',flush=True)
    db.collection('accountDeletions').document(uid).set({'state':'queued'})
    with patch('server.firebase_planning.enqueue'):
        deny(lambda:service.create_chat(owner,'project',body.model_copy(update={'clientId':'deleted-chat-request'})),403)
    print('PASS: deletion barrier',flush=True)
finally:
    db.recursive_delete(user)
    for blob in bucket.list_blobs(prefix=f'users/{uid}/'):blob.delete()
    db.collection('accountDeletions').document(uid).delete()
    try:auth.delete_user(uid,app=app)
    except auth.UserNotFoundError:pass
    firebase_admin.delete_app(app)
    print('Disposable account, replies, wallet and references removed.',flush=True)
