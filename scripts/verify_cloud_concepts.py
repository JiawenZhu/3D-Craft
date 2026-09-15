"""Disposable real Firestore acceptance; optional paid canonical concept generation.

CRAFT_RUN_FIRESTORE_INTEGRATION=1 [CRAFT_CHECK_DEPLOYED_CONCEPTS=1] python scripts/verify_cloud_concepts.py
"""
import io,json,os,subprocess,sys,time,uuid,secrets
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_RUN_FIRESTORE_INTEGRATION')!='1':raise SystemExit('Explicit integration flag required')
import requests,firebase_admin
from firebase_admin import credentials,firestore,storage,auth
from google.oauth2.credentials import Credentials
from fastapi import HTTPException
from PIL import Image
from server.firebase_concepts import CloudConcepts,ConceptRequest,LEASE
from server.firebase_studio import FirebaseStudio,BUCKET
from server import cloud_concept_provider as provider
class CLIIdentity(credentials.Base):
    def __init__(self):self.value=Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id=provider.planner.PROJECT)
    def get_credential(self):return self.value
app=firebase_admin.initialize_app(CLIIdentity(),{'projectId':provider.planner.PROJECT,'storageBucket':BUCKET})
db=firestore.client(app=app);bucket=storage.bucket(app=app)
uid='craft-concept-fixture-'+uuid.uuid4().hex;owner='firebase:'+uid;user=db.collection('users').document(uid)
clock=[time.time()];service=CloudConcepts(FirebaseStudio(db,bucket),clock=lambda:clock[0]);wallet=service.billing.private(uid,'wallet')
project=service.projects.ref(uid,'studioProjects','project')
image=io.BytesIO();Image.new('RGB',(2048,2048),'green').save(image,format='JPEG')
made=dict(bytes=image.getvalue(),width=2048,height=2048,model=provider.MODEL,tokens=16,providerUsd='.137',usage={'input':100,'imageOutput':1120,'textOutput':100})
plan={'prompt':'A swing with a red frame, green canopy and wooden bench.','tokens':1,'providerUsd':'.001'}

def denied(fn,code):
    try:fn()
    except HTTPException as exc:assert exc.status_code==code,(exc.status_code,code)
    else:raise AssertionError('Expected rejection')

def step(jid):
    try:return service.run(uid,jid)
    except HTTPException as exc:
        assert exc.status_code==503,exc.detail
        return None

def finish(jid):
    for _ in range(15):
        result=step(jid)
        if result:return result
    raise AssertionError('Job did not settle')

try:
    user.set({'fixture':True});wallet.set({'available':500,'reserved':0})
    project.set({'id':'project','ownerId':uid,'name':'Swing','prompt':'A garden swing','style':'Stylized'})
    with patch('server.firebase_concepts.enqueue'),patch('server.firebase_concepts.enqueue_cleanup'),patch.object(provider,'preflight',return_value=100),patch.object(provider.planner,'preflight',return_value=100):
        body=ConceptRequest(idempotencyKey='four-view-fixture',count=4,maxTokens=provider.quote(clock[0],4)['maxTokens'])
        with ThreadPoolExecutor(4) as pool:jobs=list(pool.map(lambda _:service.create(owner,'project',body),range(4)))
        jid=jobs[0]['id'];assert all(j['id']==jid for j in jobs)
        assert wallet.get().to_dict()['reserved']==body.maxTokens
        denied(lambda:service.create(owner,'project',body.model_copy(update={'prompt':'Changed'})),409)
        denied(lambda:service.create('firebase:other-fixture','project',body),404)
        denied(lambda:service.create(owner,'project',body.model_copy(update={'idempotencyKey':'price-low','maxTokens':1})),409)
        with patch.object(provider.planner,'generate',side_effect=[plan,{'prompt':'PASS','tokens':1}]),patch.object(provider,'generate',side_effect=lambda *a:dict(made)) as render:
            result=finish(jid);assert result['status']=='done' and result['charged']==66
            assert [c['direction'] for c in result['concepts']]==['front','back','left','right']
            assert result['validation']['usable'] is True and render.call_count==4
            finish(jid);assert render.call_count==4
        assert wallet.get().to_dict()['available']==434 and wallet.get().to_dict()['reserved']==0
        assert len(list(user.collection('mobileCreations').stream()))==4
        # A later uncertain image cannot destroy the previously published image.
        second=service.create(owner,'project',body.model_copy(update={'idempotencyKey':'partial-fixture','count':2}))
        jid=second['id'];public,private=service.refs(uid,jid)
        with patch.object(provider.planner,'generate',return_value=plan),patch.object(provider,'generate',side_effect=lambda *a:dict(made)):
            step(jid);step(jid)
        token,data=service.claim(uid,jid);service.advance(uid,jid,token,'render_ready',{'phase':'render_calling'})
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as render:
            result=finish(jid);render.assert_not_called()
        assert result['status']=='partial' and result['charged']==17 and len(result['concepts'])==1
        assert wallet.get().to_dict()['available']==417 and wallet.get().to_dict()['reserved']==0
        # Output bytes + usage survive a crash before Firestore publication.
        third=service.create(owner,'project',body.model_copy(update={'idempotencyKey':'saved-output-fixture','count':1}))
        jid=third['id'];public,private=service.refs(uid,jid)
        with patch.object(provider.planner,'generate',return_value=plan):step(jid)
        token,data=service.claim(uid,jid);service.advance(uid,jid,token,'render_ready',{'phase':'render_calling'})
        cid=data['ids'][0];blob=bucket.blob(f'users/{uid}/images/{cid}.jpg');meta={k:v for k,v in made.items() if k!='bytes'}
        blob.metadata={'jobId':jid,'index':'0','result':json.dumps(meta)};blob.upload_from_string(made['bytes'],content_type='image/jpeg')
        clock[0]+=LEASE+1
        with patch.object(provider,'generate') as render:
            result=finish(jid);render.assert_not_called()
        assert result['status']=='done' and result['charged']==17
        assert wallet.get().to_dict()['available']==400 and wallet.get().to_dict()['reserved']==0
        # An image staged before expiry must not publish a dangling reference
        # after its scheduled orphan cleanup window.
        expired=service.create(owner,'project',body.model_copy(update={'idempotencyKey':'expired-output-fixture','count':1}))
        jid=expired['id'];public,private=service.refs(uid,jid)
        with patch.object(provider.planner,'generate',return_value=plan):step(jid)
        token,data=service.claim(uid,jid);cid=data['ids'][0]
        service.advance(uid,jid,token,'render_ready',{'phase':'image_saved','saved':{'id':cid,'path':f'users/{uid}/images/{cid}.jpg',**{k:v for k,v in made.items() if k!='bytes'}}})
        clock[0]=data['deadline']+1
        assert finish(jid)['status']=='failed'
        assert not service.projects.ref(uid,'studioConcepts',cid).get().exists
        assert wallet.get().to_dict()['available']==400 and wallet.get().to_dict()['reserved']==0
    print('PASS: one reservation, 4 anchored views, replay, partial recovery, saved output recovery, private library and exact settlement',flush=True)

    if os.getenv('CRAFT_CHECK_DEPLOYED_CONCEPTS')=='1':
        password=secrets.token_urlsafe(30);auth.create_user(uid=uid,email=uid+'@example.com',password=password,app=app)
        config=requests.get('https://3d-craft.web.app/__/firebase/init.json',timeout=30).json()
        login=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',params={'key':config['apiKey']},json={'email':uid+'@example.com','password':password,'returnSecureToken':True},timeout=30)
        login.raise_for_status();headers={'Authorization':'Bearer '+login.json()['idToken']};base='https://3d-craft.web.app/api/mobile'
        catalog=requests.get(base+'/image-models',headers=headers,timeout=30);catalog.raise_for_status();catalog=catalog.json()
        assert catalog['models'][0]['available'] and [m['id'] for m in catalog['models']]==[provider.MODEL]
        def live(path,body):
            before=wallet.get().to_dict()['available']
            def post():
                r=requests.post(base+path,headers=headers,json=body,timeout=45);assert r.status_code==200,r.text[:300];return r.json()
            with ThreadPoolExecutor(2) as pool:results=list(pool.map(lambda _:post(),range(2)))
            jid=results[0]['id'];assert results[1]['id']==jid
            end=time.monotonic()+900;job=results[0]
            while time.monotonic()<end and job['status'] not in ('done','partial','failed'):
                time.sleep(3)
                r=requests.get(base+'/jobs',headers=headers,timeout=30);r.raise_for_status();job=next(j for j in r.json() if j['id']==jid)
            assert job['status']=='done',job
            assert post()['charged']==job['charged'] and wallet.get().to_dict()['available']==before-job['charged']
            assert wallet.get().to_dict()['reserved']==0
            for concept in job['concepts']:
                response=requests.get(concept['imageUrl'],headers=headers,timeout=45);response.raise_for_status()
                with Image.open(io.BytesIO(response.content)) as im:assert im.size==(2048,2048)
                assert requests.get(concept['imageUrl'],timeout=30).status_code in (401,403)
                Path('/tmp/'+jid+'-'+concept['direction']+'.jpg' if concept['direction'] else '/tmp/'+jid+'.jpg').write_bytes(response.content)
            assert requests.get(base+'/jobs',timeout=30).status_code==401
            print('PASS: canonical',path,{'id':jid,'charged':job['charged'],'images':len(job['concepts']),'validation':job.get('validation')},flush=True)
            return job
        r=requests.post(base+'/projects',headers=headers,data={'prompt':'A stylized garden swing with a red metal frame, a green canopy and a wooden two-person seat.','name':'Cloud swing acceptance','clientId':'cloud-swing-project'},timeout=40);r.raise_for_status();live_project=r.json()
        job=live('/projects/'+live_project['id']+'/concepts',{'idempotencyKey':'cloud-concept-views','count':4,'maxTokens':catalog['maxTokensByCount']['4']})
        first=job['concepts'][0]
        edited=live('/concepts/'+first['id']+'/refine',{'idempotencyKey':'cloud-refine-image','count':1,'prompt':'Change only the canopy to bright yellow. Keep the red frame and wooden bench.','maxTokens':catalog['maxTokensByCount']['1']})
        assert edited['concepts'][0]['parentId']==first['id']
    db.collection('accountDeletions').document(uid).set({'state':'queued'})
    denied(lambda:service.create(owner,'project',body),403)
    print('PASS: deletion barrier',flush=True)
finally:
    for blob in bucket.list_blobs(prefix=f'users/{uid}/'):blob.delete()
    db.recursive_delete(user);db.collection('accountDeletions').document(uid).delete()
    try:auth.delete_user(uid,app=app)
    except auth.UserNotFoundError:pass
    print('Disposable fixtures removed.',flush=True)
