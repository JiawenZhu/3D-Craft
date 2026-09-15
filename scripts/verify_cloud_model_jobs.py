"""Opt-in transaction/crash acceptance against disposable Firebase records.

Run from the repository root with a Firebase-capable gcloud account:
    CRAFT_RUN_FIRESTORE_INTEGRATION=1 python scripts/verify_cloud_model_jobs.py

The fal submission/download calls are mocked; this test incurs no model fee.
Only records and objects under a freshly generated fixture user are modified.
"""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_RUN_FIRESTORE_INTEGRATION') != '1':
    raise SystemExit('Set CRAFT_RUN_FIRESTORE_INTEGRATION=1 to run disposable cloud-data checks.')
import io,uuid,subprocess,json,struct,time,requests
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch
import firebase_admin
from firebase_admin import credentials,firestore,storage
from google.oauth2.credentials import Credentials
from fastapi import HTTPException
from PIL import Image
from server.firebase_studio import FirebaseStudio,BUCKET
from server.firebase_projects import CloudProjects
from server.firebase_model_jobs import CloudModelJobs,ModelRequest
from server import cloud_model_provider as provider
class CLIIdentity(credentials.Base):
 def get_credential(self):return Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id='forma-studio-2026')
app=firebase_admin.initialize_app(CLIIdentity(),{'projectId':'forma-studio-2026','storageBucket':BUCKET})
db=firestore.client(app=app);bucket=storage.bucket(BUCKET,app=app)
uid='craft-model-fixture-'+uuid.uuid4().hex;owner='firebase:'+uid
studio=FirebaseStudio(db,bucket);service=CloudModelJobs(studio)
def mesh(result,target):
 doc={'asset':{'version':'2.0'},'meshes':[{'primitives':[]}]};data=json.dumps(doc).encode();data+=b' '*((-len(data))%4)
 target.write_bytes(struct.pack('<4sIIII',b'glTF',2,len(data)+20,len(data),0x4E4F534A)+data)
try:
 raw=io.BytesIO();Image.new('RGB',(64,64),'teal').save(raw,format='PNG')
 with patch('server.firebase_projects.enqueue_cleanup'):
  project=CloudProjects(studio).create(owner,prompt='fixture',raw=raw.getvalue(),client_id='model-input-fixture')
 cid=project['concepts'][0]['id'];wallet=service.billing.private(uid,'wallet');wallet.set({'available':200,'reserved':0})
 body=ModelRequest(idempotencyKey='durable-model-fixture',engine='rodin')
 with patch('server.firebase_model_jobs.enqueue'),patch.object(provider,'headers',return_value={}):
  with ThreadPoolExecutor(2) as pool: rows=list(pool.map(lambda _:service.create(owner,cid,body),range(2)))
  assert rows[0]==rows[1];jid=rows[0]['id'];assert wallet.get().to_dict()['reserved']==46
  assert wallet.get().to_dict()['available']==154
  try:service.create(owner,cid,ModelRequest(idempotencyKey=body.idempotencyKey,engine='trellis-2'))
  except HTTPException as e:assert e.status_code==409
  else:raise AssertionError('Conflicting retry accepted')
  public,private=service.refs(uid,jid)
  # Start at prepared to exercise an uncertain paid POST, not a fake fal upload.
  private.update({'phase':'prepared','arguments':{'input_image_urls':['provider-upload']}})
  with patch.object(provider,'submit',side_effect=requests.Timeout) as submit:
   try:service.run(uid,jid)
   except requests.Timeout:pass
   else:raise AssertionError('Timeout not propagated')
   try:service.run(uid,jid)
   except HTTPException as e:assert e.status_code==503
   else:raise AssertionError('Ambiguous request did not wait')
   assert submit.call_count==1
  data=private.get().to_dict();assert data['phase']=='submitting' and data['leaseUntil']==0
  try:service.request_received(uid,jid,'provider-request',callback_token='wrong')
  except HTTPException as e:assert e.status_code==401
  else:raise AssertionError('Bad callback token accepted')
  service.request_received(uid,jid,'provider-request',callback_token=data['callbackToken'])
  assert private.get().to_dict()['phase']=='submitted'
  # Simulate crash after file upload but before wallet/library commit.
  with patch.object(provider,'status',return_value={}),patch.object(provider,'download_mesh',side_effect=mesh):
   with patch.object(service,'finish',side_effect=OSError('simulated crash')):
    try:service.run(uid,jid)
    except OSError:pass
   assert bucket.blob(f'users/{uid}/models/{jid}.glb').exists()
   assert wallet.get().to_dict()['reserved']==46
   assert service.run(uid,jid)['status']=='done'
   assert service.run(uid,jid)['status']=='done'
  assert wallet.get().to_dict()['available']==154 and wallet.get().to_dict()['reserved']==0
  assert len(list(wallet.collection('entries').stream()))==2
  assert public.get().to_dict()['charged']==46
  assert service.cleanup(uid,jid)['status']=='retained'
  # A second job fails; reserved packs return exactly once.
  second=service.create(owner,cid,ModelRequest(idempotencyKey='failed-model-fixture',engine='rodin'))
  token,data=service.claim(uid,second['id'])
  try:service.claim(uid,second['id'])
  except HTTPException as e:assert e.status_code==503
  else:raise AssertionError('Concurrent lease granted')
  assert service.finish(uid,second['id'],token,error='fixture failure')=='failed'
  assert service.finish(uid,second['id'],token,error='fixture failure')=='failed'
  assert wallet.get().to_dict()['available']==154 and wallet.get().to_dict()['reserved']==0
  # Erasure barrier prevents late publication; independent cleanup removes files.
  db.collection('accountDeletions').document(uid).set({'state':'deleting'})
  assert service.cleanup(uid,jid)['status']=='removed'
  assert service.run(uid,jid)['status']=='account-deleted'
  try:service.create(owner,cid,ModelRequest(idempotencyKey='deleted-model-fixture'))
  except HTTPException as e:assert e.status_code==403
  else:raise AssertionError('Deleted account created a job')
 print(json.dumps({'concurrentRetry':'single reservation','conflict':'409','uncertainPaidPost':'submitted once','callbackRecovery':'passed','crashAfterUpload':'recovered','successSettlement':'once','failureRefund':'once','concurrentLease':'rejected','deletionBarrier':'passed','privateOutputCleanup':'passed'}),flush=True)
finally:
 for blob in bucket.list_blobs(prefix=f'users/{uid}/'):blob.delete(if_generation_match=blob.generation)
 db.recursive_delete(db.collection('users').document(uid));db.collection('accountDeletions').document(uid).delete()
 print('Fixture files and records removed.',flush=True)
