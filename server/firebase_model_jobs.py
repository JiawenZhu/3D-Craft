"""Durable image-to-3D jobs. Paid submissions never retry after ambiguity.

Public progress, private provider state, and wallet settlement have separate
records. Tasks retry observations; only a transaction can authorize submission.
"""
import hashlib
import hmac
import json
import os
import secrets
import tempfile
import time
import uuid
from pathlib import Path
from urllib.parse import quote

from fastapi import HTTPException
from firebase_admin import firestore
from google.api_core.exceptions import NotFound, PreconditionFailed
from pydantic import BaseModel, Field
from typing import Literal
from . import cloud_model_provider as provider
from .firebase_studio import BUCKET, uid_for
from .firebase_projects import CloudProjects
from .firebase_billing import CloudBilling
from .firebase_usage import reserve, settle
from .firebase_subscriptions import expire_allowance
from .pricing import model_quote

LIFETIME = 3600
LEASE = 900
TERMINAL = ('done', 'failed')


class ModelRequest(BaseModel):
    idempotencyKey: str = Field(min_length=8, max_length=120)
    engine: Literal['rodin','trellis-2','hunyuan3d-2.1','hunyuan3d-2-white'] = 'rodin'
    quality: Literal['default','speedy'] = 'default'
    effort: Literal['extreme-low','low','medium','high','extreme-high'] = 'high'
    modelPrompt: str | None = Field(default=None, max_length=800)
    conceptIds: list[str] | None = Field(default=None, min_length=1, max_length=4)


def enqueue(uid, jid, cleanup=False):
    from google.cloud import tasks_v2
    from google.protobuf.timestamp_pb2 import Timestamp
    base = os.environ['CRAFT_TASK_ORIGIN'].rstrip('/')
    identity = os.environ['CRAFT_TASK_IDENTITY']
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path('forma-studio-2026','us-central1',
                               'craft-upload-cleanup' if cleanup else 'craft-model-jobs')
    route = 'model-outputs' if cleanup else 'model-jobs'
    task = {'http_request': {'http_method': tasks_v2.HttpMethod.POST,
        'url': f'{base}/internal/{route}/{quote(uid,safe="")}/{jid}',
        'headers': {'X-Craft-Queued-At': str(int(time.time()))},
        'oidc_token': {'service_account_email':identity, 'audience':base}}}
    if cleanup: task['schedule_time'] = Timestamp(seconds=int(time.time()) + LIFETIME + LEASE + 120)
    client.create_task(parent=parent, task=task, timeout=30, retry=None)


def select_views(concept_id, ids, concepts, source_job=None):
    selected = ids or [concept_id]
    if concept_id not in selected or len(set(selected)) != len(selected):
        raise HTTPException(422,'Include the main image once, with no duplicate views.')
    views = [concepts[concept_id]] + [concepts[cid] for cid in selected if cid != concept_id]
    if len(views)>1:
        view_set = views[0].get('viewSetId')
        if not view_set or any(v.get('isOriginal') or v.get('viewSetId')!=view_set for v in views):
            raise HTTPException(422,'Choose generated views from the same validated concept set.')
        if not source_job or source_job.get('status') not in ('done','partial') or source_job.get('validation',{}).get('usable') is not True:
            raise HTTPException(422,'This set has not passed view-consistency checks. Choose one image.')
        directions = [v.get('direction') for v in views]
        if len(set(directions))!=len(directions) or any(d not in ('front','back','left','right') for d in directions):
            raise HTTPException(422,'Choose distinct, verified camera directions.')
    return views


class CloudModelJobs:
    def __init__(self, studio, clock=None):
        self.studio, self.db = studio, studio.db
        self.now = clock or time.time
        self.billing = CloudBilling(self.db, self.now)
        self.projects = CloudProjects(studio)

    def refs(self, uid, jid):
        uid_for('firebase:'+uid)
        if len(jid)!=67 or not jid.startswith('mj-') or any(c not in '0123456789abcdef' for c in jid[3:]):
            raise HTTPException(422,'Invalid job identifier.')
        public = self.projects.ref(uid,'studioJobs',jid)
        private = self.billing.private(uid,'generationJobs').collection('items').document(jid)
        return public, private

    def active(self, uid, tx):
        if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
            raise HTTPException(403,'This account is being deleted.')

    def create(self, owner, concept_id, body, environment=None):
        started = self.now()
        provider.headers()  # Fail before reserving if the service has no key.
        uid = uid_for(owner)
        jid = 'mj-'+hashlib.sha256((uid+':'+body.idempotencyKey).encode()).hexdigest()
        public, private = self.refs(uid,jid)
        payload = body.model_dump(exclude={'idempotencyKey'})
        signature = hashlib.sha256(json.dumps([concept_id,payload],sort_keys=True).encode()).hexdigest()
        # Queue first: an early delivery retries until the transaction exists.
        # A random task name also recovers a previously missing delivery.
        enqueue(uid,jid)
        @firestore.transactional
        def create(tx):
            self.active(uid,tx)
            prior = private.get(transaction=tx)
            if prior.exists:
                if prior.to_dict()['signature'] != signature:
                    raise HTTPException(409,'This request was already used for different work.')
                return public.get(transaction=tx).to_dict()
            concepts = {}
            for cid in set([concept_id]+(body.conceptIds or [])):
                snap = self.projects.ref(uid,'studioConcepts',cid).get(transaction=tx)
                if not snap.exists or snap.to_dict().get('ownerId')!=uid:
                    raise HTTPException(404,'Image not found in your account.')
                concepts[cid] = snap.to_dict()
            concept = concepts[concept_id]
            project = self.projects.ref(uid,'studioProjects',concept['projectId']).get(transaction=tx)
            if not project.exists or project.to_dict().get('ownerId')!=uid:
                raise HTTPException(404,'Project not found in your account.')
            project = project.to_dict()
            source = None
            if len(concepts)>1 and concept.get('viewSetId'):
                source = self.projects.ref(uid,'studioJobs',concept['viewSetId']).get(transaction=tx).to_dict()
            views = select_views(concept_id, body.conceptIds, concepts, source)
            if any(v.get('projectId')!=concept['projectId'] for v in views):
                raise HTTPException(422,'Choose images from the same project.')
            for view in views: self.image_path(uid,view['imageUrl'])
            prompt = ('Use the selected reference image(s) to create a 3D asset. '+body.modelPrompt.strip()) if body.modelPrompt is not None else (
                'Reconstruct the reference, preserving its geometry, colors and proportions. '+project.get('prompt','')[:800])
            try:
                endpoint, _ = provider.arguments(body.engine,['pending']*len(views),[v.get('direction') for v in views],body.effort,body.quality,prompt)
            except ValueError as exc: raise HTTPException(422,str(exc)) from None
            estimate = model_quote(body.engine,views=len(views),effort=body.effort)
            cost = estimate['usageWithServiceFee']['credits']
            if cost is None: raise HTTPException(422,'This model has no verified price.')
            if environment is not None:
                effective_env = environment
                if effective_env != 'SANDBOX' or os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1':
                    effective_env = 'PRODUCTION'
            else:
                context = self.billing.private(uid, 'billingContext').get(transaction=tx).to_dict() or {}
                effective_env = context.get('environment', 'PRODUCTION')
                if effective_env != 'SANDBOX' or os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1':
                    effective_env = 'PRODUCTION'
            wallet_name = 'sandboxWallet' if effective_env == 'SANDBOX' else 'wallet'
            wallet_ref = self.billing.private(uid, wallet_name)
            before = wallet_ref.get(transaction=tx).to_dict() or {}
            after, allocation = reserve({**before, 'environment': effective_env}, cost, self.now())
            if self.now()-started > 120:
                raise HTTPException(503,'The request took too long. Please retry.')
            data = dict(id=jid,ownerId=uid,projectId=concept['projectId'],kind='model',status='queued',
                stage='queued',progress=0,message='Preparing your reference',concepts=[],assets=[],cost=cost,
                reserved=cost,charged=0,createdAt=self.now(),error=None,selectedConceptId=concept_id,
                selectedConceptIds=[v['id'] for v in views],selectedImageUrl=concept['imageUrl'],providerEstimate=estimate,
                modelSettings=dict(engine=body.engine,quality=body.quality,effort=body.effort,
                    prompt=prompt if body.engine=='rodin' else '',promptApplied=body.engine=='rodin'))
            tx.create(public,data)
            tx.create(private,dict(signature=signature,phase='preparing',createdAt=self.now(),
                deadline=self.now()+LIFETIME,allocation=allocation,walletName=wallet_name,views=views,
                options=payload,prompt=prompt,endpoint=endpoint,name=project.get('name','Your creation'),
                callbackToken=secrets.token_urlsafe(32),leaseUntil=0))
            tx.set(wallet_ref,after,merge=True)
            expired=max(0,int(before.get('subscriptionAvailable',0))-int(after.get('subscriptionAvailable',0))-allocation['subscription'])
            if expired:
                tx.create(wallet_ref.collection('entries').document(jid+':expiry-reserve'),
                    dict(id=jid+':expiry-reserve',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':reserve'),
                dict(id=jid+':reserve',amount=-cost,kind='generation_reservation',createdAt=self.now(),jobId=jid))
            return data
        return create(self.db.transaction())

    def image_path(self, uid, url):
        prefix = f'gs://{BUCKET}/users/{uid}/'
        if not isinstance(url,str) or not url.startswith(prefix) or '..' in url.removeprefix(prefix).split('/'):
            raise HTTPException(422,'The reference must be saved in your private library.')
        return url.removeprefix(f'gs://{BUCKET}/')

    def claim(self, uid, jid):
        public, private = self.refs(uid,jid)
        token = uuid.uuid4().hex
        @firestore.transactional
        def claim(tx):
            self.active(uid,tx)
            snap = private.get(transaction=tx)
            if not snap.exists: raise HTTPException(503,'Waiting for the job record.')
            data = snap.to_dict()
            if data['phase'] in TERMINAL: return None, data
            if data.get('leaseUntil',0)>self.now(): raise HTTPException(503,'This job is already being checked.')
            tx.update(private,dict(leaseToken=token,leaseUntil=self.now()+LEASE))
            return token, data
        return claim(self.db.transaction())

    def advance(self, uid, jid, token, phase, updates, visible=None):
        public, private = self.refs(uid,jid)
        @firestore.transactional
        def advance(tx):
            self.active(uid,tx)
            data = private.get(transaction=tx).to_dict() or {}
            if data.get('leaseToken')!=token or (phase is not None and data.get('phase')!=phase) or data.get('leaseUntil',0)<=self.now():
                return False
            tx.update(private,updates)
            if visible: tx.update(public,visible)
            return True
        moved = advance(self.db.transaction())
        if moved and visible: self.notify_activity(uid, jid)
        return moved

    def notify_activity(self, uid, jid):
        """Mirror the job's public state onto its Live Activity. Never raises."""
        from . import live_activity
        try:
            job = self.projects.ref(uid, 'studioJobs', jid).get().to_dict()
        except Exception:
            return
        if job: live_activity.notify(self.db, uid, {**job, 'id': jid})

    def request_received(self, uid, jid, request_id, callback_token=None, failed=False):
        _, private = self.refs(uid,jid)
        if not isinstance(request_id,str) or not 1<=len(request_id)<=128 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in request_id):
            raise HTTPException(422,'Invalid provider request identifier.')
        @firestore.transactional
        def receive(tx):
            self.active(uid,tx)
            data = private.get(transaction=tx).to_dict()
            if not data: raise HTTPException(404,'Job not found.')
            if callback_token is not None and not hmac.compare_digest(data['callbackToken'],callback_token):
                raise HTTPException(401,'Invalid notification destination.')
            if data['phase'] in TERMINAL: return
            if data['phase'] not in ('submitting','submitted'):
                raise HTTPException(409,'Job has not been submitted.')
            if data.get('requestId') and data['requestId']!=request_id:
                raise HTTPException(409,'Conflicting provider request identifier.')
            update=dict(requestId=request_id,phase='submitted')
            if failed: update['providerFailed']=True
            tx.update(private,update)
        receive(self.db.transaction())

    def finish(self, uid, jid, token, *, asset=None, error=None):
        public, private = self.refs(uid,jid)
        @firestore.transactional
        def finish(tx):
            self.active(uid,tx)
            data = private.get(transaction=tx).to_dict() or {}
            if data.get('phase') in TERMINAL: return data['phase']
            if data.get('leaseToken')!=token or data.get('leaseUntil',0)<=self.now():
                raise HTTPException(503,'Job will be checked again.')
            wallet_ref = self.billing.private(uid,data['walletName'])
            wallet = wallet_ref.get(transaction=tx).to_dict() or {}
            allocation = data['allocation']
            refunded = False
            if allocation.get('subscriptionTransaction'):
                key=hashlib.sha256(('APP_STORE:'+allocation['subscriptionTransaction']).encode()).hexdigest()
                receipt=self.db.collection('billingReceipts').document(key).get(transaction=tx).to_dict()
                refunded=not receipt or receipt.get('refunded',False)
            charge = allocation['cost'] if asset else 0
            after = settle(wallet,allocation,charge,self.now(),refunded)
            state='done' if asset else 'failed'
            # Wallet and library publication commit together; a repeated worker
            # can neither charge twice nor publish a model after a refund.
            tx.set(wallet_ref,after,merge=True)
            returned = allocation['cost']-charge
            # An expired allowance is released, not re-issued as spendable credit.
            current=expire_allowance(wallet,self.now())
            actual_return = (after.get('available',0)+after.get('subscriptionAvailable',0)
                - current.get('subscriptionAvailable',0) - current.get('available',0))
            expired=max(0,int(wallet.get('subscriptionAvailable',0))-int(current.get('subscriptionAvailable',0)))
            if expired:
                tx.create(wallet_ref.collection('entries').document(jid+':expiry-settle'),
                    dict(id=jid+':expiry-settle',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':settled'),dict(id=jid+':settled',
                amount=max(0,actual_return),kind='generation_complete' if asset else 'generation_refund',
                charged=charge,released=returned,createdAt=self.now(),jobId=jid))
            tx.update(private,dict(phase=state,leaseUntil=0,finishedAt=self.now()))
            tx.update(public,dict(status=state,stage=state,progress=100 if asset else 0,
                message='Your 3D creation is ready' if asset else error,error=error,assets=[asset] if asset else [],
                reserved=0,charged=charge,completedAt=self.now()))
            if asset:
                preview=self.image_path(uid,data['views'][0]['imageUrl'])
                tx.create(self.projects.ref(uid,'mobileCreations','model:'+jid),dict(ownerId=uid,source='ios',
                    storageVersion=2,name=data['name'],kind='3D object',projectId=data['views'][0]['projectId'],
                    conceptIds=[v['id'] for v in data['views']],previewStoragePath=preview,
                    modelStoragePath=f'users/{uid}/models/{jid}.glb',createdAt=self.now()))
            return state
        state = finish(self.db.transaction())
        self.notify_activity(uid, jid)
        return state

    def run(self, uid, jid, queued_at=None):
        try: token,data = self.claim(uid,jid)
        except HTTPException as exc:
            if exc.status_code==403: return {'status':'account-deleted'}
            if exc.status_code==503 and queued_at and self.now()-queued_at>600:
                if not self.refs(uid,jid)[1].get().exists: return {'status':'unpublished-request'}
            raise
        if token is None: return {'status':data['phase']}
        phase=data['phase']
        try:
            if self.now()>data['deadline']:
                return {'status':self.finish(uid,jid,token,error='This generation could not be completed. Your reserved Tokens have been released.')}
            if phase=='preparing':
                import fal_client
                from fal_client.client import StorageSettings
                urls=[]
                with tempfile.TemporaryDirectory() as folder:
                    for index, view in enumerate(data['views']):
                        blob=self.studio.bucket.blob(self.image_path(uid,view['imageUrl']))
                        blob.reload(timeout=30)
                        if blob.size>20*1024*1024: raise ValueError('Reference exceeds image limit')
                        target=Path(folder)/f'{index}.jpg'
                        blob.download_to_filename(str(target),if_generation_match=blob.generation,timeout=120,retry=None)
                        urls.append(fal_client.upload_file(target,lifecycle=StorageSettings(expires_in=7200)))
                options=data['options']
                endpoint,arguments=provider.arguments(options['engine'],urls,[v.get('direction') for v in data['views']],
                    options['effort'],options['quality'],data['prompt'])
                if not self.advance(uid,jid,token,phase,dict(phase='prepared',arguments=arguments),
                    dict(status='running',stage='reconstructing',progress=10,message='Preparing 3D reconstruction')):
                    raise HTTPException(503,'Job state changed; retrying.')
                data['arguments']=arguments;phase='prepared'
            if phase=='prepared':
                if not self.advance(uid,jid,token,phase,dict(phase='submitting',submittedAt=self.now())):
                    raise HTTPException(503,'Job state changed; retrying.')
                phase='submitting'
                callback='https://3d-craft.web.app/api/models/callback/'+quote(uid,safe='')+'/'+jid+'/'+data['callbackToken']
                rid=provider.submit(data['endpoint'],data['arguments'],callback)
                self.request_received(uid,jid,rid)
                data['requestId']=rid;phase='submitted'
            if phase=='submitting':
                # The POST response was lost. Wait for the signed callback; do
                # not retry a billable submission even if this process crashed.
                raise HTTPException(503,'Waiting for provider confirmation.')
            if phase=='submitted':
                if data.get('providerFailed'):
                    return {'status':self.finish(uid,jid,token,error='The model service could not complete this creation. Your reserved Tokens have been released.')}
                result=provider.status(data['endpoint'],data['requestId'])
                if result is None: raise HTTPException(503,'3D reconstruction is in progress.')
                enqueue(uid,jid,cleanup=True)
                with tempfile.TemporaryDirectory() as folder:
                    target=Path(folder)/'model.glb'
                    provider.download_mesh(result,target)
                    blob=self.studio.bucket.blob(f'users/{uid}/models/{jid}.glb')
                    blob.cache_control='private, max-age=3600'
                    try: blob.upload_from_filename(str(target),content_type='model/gltf-binary',if_generation_match=0,timeout=180,retry=None)
                    except PreconditionFailed: pass  # The same completed job was uploaded before a crash.
                asset=dict(id=jid,name=data['name'],modelUrl=f'gs://{BUCKET}/users/{uid}/models/{jid}.glb',
                    thumbUrl=data['views'][0]['imageUrl'],isExample=False)
                return {'status':self.finish(uid,jid,token,asset=asset)}
        except (ValueError,NotFound):
            return {'status':self.finish(uid,jid,token,error='The model could not be saved. Your reserved Tokens have been released.')}
        finally:
            # Never mask a provider error with a cleanup error. Expired leases
            # are reclaimable even if releasing one fails during an outage.
            try: self.advance(uid,jid,token,None,dict(leaseUntil=0))
            except Exception: pass
        raise HTTPException(503,'Job will be checked again.')

    def cleanup(self, uid, jid):
        public, private=self.refs(uid,jid)
        marker=self.db.collection('accountDeletions').document(uid).get()
        published=public.get().to_dict() or {}
        if not marker.exists and published.get('status')=='done': return {'status':'retained'}
        blob=self.studio.bucket.blob(f'users/{uid}/models/{jid}.glb')
        try:
            blob.reload(timeout=30);blob.delete(if_generation_match=blob.generation,timeout=30)
        except NotFound: pass
        return {'status':'removed'}
