"""Opt-in paid text -> concept -> 3D acceptance through the canonical Firebase API.

CRAFT_CHECK_DEPLOYED_RELEASE=1 python scripts/verify_cloud_release_flow.py
Uses a disposable account; never changes a customer's wallet or purchases.
"""
import os,sys,time,uuid,secrets,subprocess,json,struct
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_CHECK_DEPLOYED_RELEASE')!='1':raise SystemExit('Explicit paid release-flow flag required')
import requests,firebase_admin
from firebase_admin import credentials,firestore,storage,auth
from google.oauth2.credentials import Credentials
from server.firebase_studio import BUCKET
PROJECT='forma-studio-2026';ORIGIN='https://3d-craft.web.app';BASE=ORIGIN+'/api/mobile'
class CLIIdentity(credentials.Base):
    def get_credential(self):return Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id=PROJECT)
app=firebase_admin.initialize_app(CLIIdentity(),{'projectId':PROJECT,'storageBucket':BUCKET})
db=firestore.client(app=app);bucket=storage.bucket(app=app)
uid='craft-release-fixture-'+uuid.uuid4().hex;user=db.collection('users').document(uid)
wallet=user.collection('private').document('wallet')
def post(path,body=None,form=None):
    r=requests.post(BASE+path,headers=headers,json=body,data=form,timeout=45);r.raise_for_status();return r.json()
def wait_job(jid):
    until=time.monotonic()+1500;last=None
    while time.monotonic()<until:
        r=requests.get(BASE+'/jobs',headers=headers,timeout=45);r.raise_for_status()
        job=next(j for j in r.json() if j['id']==jid)
        state=(job['status'],job.get('stage'),job.get('progress'))
        if state!=last:print('Job',jid,*state,flush=True);last=state
        if job['status'] in ('done','partial','failed'):
            assert job['status']=='done',(job['status'],job.get('error'));return job
        time.sleep(5)
    raise AssertionError('Job remains unfinished; inspect this ID before starting another paid request: '+jid)
try:
    password=secrets.token_urlsafe(30);auth.create_user(uid=uid,email=uid+'@example.com',password=password,app=app)
    user.set({'fixture':True});wallet.set({'available':200,'reserved':0})
    config=requests.get(ORIGIN+'/__/firebase/init.json',timeout=30).json()
    r=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',params={'key':config['apiKey']},json={'email':uid+'@example.com','password':password,'returnSecureToken':True},timeout=30);r.raise_for_status()
    headers={'Authorization':'Bearer '+r.json()['idToken']}
    catalog=requests.get(BASE+'/image-models',headers=headers,timeout=30).json()
    assert catalog['models'][0]['id']=='gemini-3-pro-image' and catalog['models'][0]['available']
    project=post('/projects',form={'prompt':'A small original stylized garden frog wearing a plain teal raincoat. Full body, no text or logos.','name':'Cloud release acceptance','clientId':'release-concept-project'})
    request={'idempotencyKey':'release-concept-request','count':1,'maxTokens':catalog['maxTokensByCount']['1']}
    created=post('/projects/'+project['id']+'/concepts',request);concept_job=wait_job(created['id'])
    assert post('/projects/'+project['id']+'/concepts',request)['id']==created['id']
    concept=concept_job['concepts'][0]
    request={'idempotencyKey':'release-model-request','engine':'hunyuan3d-2-white'}
    created=post('/concepts/'+concept['id']+'/model',request);model_job=wait_job(created['id'])
    assert post('/concepts/'+concept['id']+'/model',request)['id']==created['id']
    asset=model_job['assets'][0]
    r=requests.get(asset['modelUrl'],headers=headers,timeout=120);r.raise_for_status();data=r.content
    magic,version,length=struct.unpack_from('<4sII',data);assert (magic,version,length)==(b'glTF',2,len(data))
    size,kind=struct.unpack_from('<II',data,12);assert kind==0x4E4F534A
    gltf=json.loads(data[20:20+size]);assert any(m.get('primitives') for m in gltf['meshes'])
    assert requests.get(asset['modelUrl'],timeout=30).status_code in (401,403)
    final=wallet.get().to_dict();charged=concept_job['charged']+model_job['charged']
    assert final['available']==200-charged and final['reserved']==0
    library=list(user.collection('mobileCreations').stream());assert len(library)==2
    folder=Path('/tmp/craft-cloud-release-flow');folder.mkdir(exist_ok=True)
    (folder/'model.glb').write_bytes(data)
    r=requests.get(concept['imageUrl'],headers=headers,timeout=45);r.raise_for_status();(folder/'concept.jpg').write_bytes(r.content)
    print(json.dumps({'result':'PASS','origin':ORIGIN,'conceptTokens':concept_job['charged'],'modelTokens':model_job['charged'],'available':final['available'],'reserved':final['reserved'],'libraryItems':len(library),'glbBytes':len(data),'meshes':len(gltf['meshes']),'anonymousDownload':'rejected'}),flush=True)
finally:
    db.collection('accountDeletions').document(uid).set({'state':'deleting'})
    for blob in bucket.list_blobs(prefix=f'users/{uid}/'):blob.delete()
    db.recursive_delete(user)
    try:auth.delete_user(uid,app=app)
    except auth.UserNotFoundError:pass
    # Keep a deletion tombstone if a provider request is still running.
    print('Disposable account and cloud files removed; deletion barrier retained.',flush=True)
