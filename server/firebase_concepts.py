"""Recoverable concept-image jobs, private outputs and atomic Token settlement."""
import hashlib
import json
import logging
import os
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import quote as urlquote
from typing import Literal
from fastapi import HTTPException
from firebase_admin import firestore
from pydantic import BaseModel, ConfigDict, Field
from google.api_core.exceptions import NotFound, PreconditionFailed
from . import cloud_concept_provider as provider
from .firebase_planning import transact, image_path, LEASE, DEADLINE
from .firebase_projects import CloudProjects, enqueue_cleanup, MAX_BYTES
from .firebase_billing import CloudBilling
from .firebase_studio import uid_for, BUCKET
from .firebase_usage import reserve, settle
from .firebase_subscriptions import expire_allowance
from .account_deletion import ensure_active

TERMINAL=('done','failed','partial')


def model_of(data):
    """The renderer the user was quoted for; jobs created before model choice used Pro."""
    return data['estimate'].get('model',provider.MODEL)
# Keep working through stages inside one Cloud Tasks delivery rather than
# returning 503 after each one and waiting for redelivery backoff. A new stage
# is only started while the delivery is young enough that even a slow provider
# call (bounded at 180 s) finishes inside Cloud Run's request timeout.
STAGE_BUDGET=100
CONTINUE=object()


class ConceptRequest(BaseModel):
    model_config=ConfigDict(extra='forbid')
    idempotencyKey:str=Field(min_length=8,max_length=120)
    count:int=Field(default=1,strict=True,ge=1,le=4)
    prompt:str=Field(default='',max_length=4000)
    imageModel:Literal['gemini-3-pro-image','gemini-3.1-flash-image']=provider.MODEL
    plannerModel:Literal['gemini-3.5-flash-lite', 'gemini-3.8-flash']=provider.planner.MODEL
    plannerEffort:Literal['low']='low'
    preserveReference:bool=False
    referenceId:str|None=Field(default=None,max_length=150)
    style:str|None=Field(default=None,max_length=100)
    maxTokens:int=Field(strict=True,ge=1,le=200)


def enqueue(uid,jid):
    from google.cloud import tasks_v2
    from google.protobuf.duration_pb2 import Duration
    client=tasks_v2.CloudTasksClient();base=os.environ['CRAFT_TASK_ORIGIN'].rstrip('/')
    client.create_task(parent=client.queue_path(provider.planner.PROJECT,'us-central1','craft-planning-jobs'),task={
        'http_request':{'http_method':tasks_v2.HttpMethod.POST,'url':f'{base}/internal/concepts/{urlquote(uid,safe="")}/{jid}',
            'headers':{'X-Craft-Queued-At':str(int(time.time()))},
            'oidc_token':{'service_account_email':os.environ['CRAFT_TASK_IDENTITY'],'audience':base}},
        'dispatch_deadline':Duration(seconds=600)},timeout=30,retry=None)


class CloudConcepts:
    def __init__(self,studio,clock=time.time):
        self.studio=studio;self.db=studio.db;self.projects=CloudProjects(studio);self.billing=CloudBilling(self.db);self.now=clock

    def refs(self,uid,jid):
        return self.projects.ref(uid,'studioJobs',jid),self.db.collection('users').document(uid).collection('private').document('conceptJobs').collection('items').document(jid)

    def active(self,uid,tx=None):
        uid_for('firebase:'+uid)
        if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:raise HTTPException(403,'Account deletion is in progress.')

    def create(self,owner,project_id,body,concept_id=None,environment=None,auto_model=None,auto_animation=None):
        uid=uid_for(owner);self.active(uid);started=self.now()
        jid='cj-'+hashlib.sha256((uid+':'+body.idempotencyKey).encode()).hexdigest()
        public,private=self.refs(uid,jid);project_ref=self.projects.ref(uid,'studioProjects',project_id)
        options=body.model_dump(exclude={'idempotencyKey'})
        signature=hashlib.sha256(json.dumps([project_id,concept_id,options],sort_keys=True).encode()).hexdigest()
        ids=['mc-'+hashlib.sha256((jid+':'+str(i)).encode()).hexdigest() for i in range(body.count)]
        enqueue(uid,jid)
        for cid in ids:enqueue_cleanup(uid,cid)
        def create(tx):
            self.active(uid,tx);prior=private.get(transaction=tx).to_dict()
            if prior:
                if prior['signature']!=signature:raise HTTPException(409,'This request ID belongs to different content.')
                return public.get(transaction=tx).to_dict()
            project=project_ref.get(transaction=tx).to_dict()
            if not project or project.get('ownerId')!=uid:raise HTTPException(404,'Project not found.')
            source=project.get('imageUrl');selected=body.referenceId or concept_id
            if concept_id and body.referenceId and body.referenceId!=concept_id:raise HTTPException(422,'Choose the image being refined.')
            if concept_id and body.count!=1:raise HTTPException(422,'Refinement produces one image.')
            if selected:
                concept=self.projects.ref(uid,'studioConcepts',selected).get(transaction=tx).to_dict()
                if not concept or concept.get('ownerId')!=uid or concept.get('projectId')!=project_id:raise HTTPException(404,'Reference not found in this project.')
                source=concept.get('imageUrl')
            source=image_path(uid,source) if source else None
            if (concept_id or body.preserveReference) and not source:raise HTTPException(422,'Choose a reference image first.')
            words=body.prompt.strip() or project.get('creativeBrief') or project.get('prompt','')
            if not words and not source:raise HTTPException(422,'Describe your idea or choose a reference.')
            mode='refine' if concept_id else 'reference' if (body.preserveReference or body.referenceId) else 'angles'
            estimate=provider.quote(self.now(),body.count,body.imageModel);cost=estimate['maxTokens']
            if body.maxTokens<cost:raise HTTPException(409,'Refresh the concept price and confirm again.')
            if environment is not None:
                sandbox = (environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') == '1')
            else:
                context = self.billing.private(uid, 'billingContext').get(transaction=tx).to_dict() or {}
                sandbox = context.get('environment') == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') == '1'
            wallet_name='sandboxWallet' if sandbox else 'wallet';wallet_ref=self.billing.private(uid,wallet_name)
            before=wallet_ref.get(transaction=tx).to_dict() or {}
            before=self.billing.ensure_welcome(uid,before,wallet_ref,tx)
            after,allocation=reserve({**before,'environment':'SANDBOX' if sandbox else 'PRODUCTION'},cost,self.now())
            if self.now()-started>120:raise HTTPException(503,'Retry this request.')
            data=dict(id=jid,ownerId=uid,projectId=project_id,kind='refine' if concept_id else 'concepts',
                status='queued',stage='analyzing_reference',progress=0,message='Preparing your concept',concepts=[],assets=[],
                reserved=cost,charged=0,createdAt=self.now(),error=None,imageModel=body.imageModel,imageProvider='google',
                sourcePrompt=words,selectedImageUrl=('gs://'+BUCKET+'/'+source) if source else None)
            if auto_model:data['autoModel']={'engine':auto_model['engine']}
            if auto_animation:data['autoAnimation']={'model':auto_animation.get('model','seedance-2.5')}
            tx.create(public,data)
            tx.create(private,dict(signature=signature,phase='plan_ready',options=options,estimate=estimate,
                allocation=allocation,walletName=wallet_name,projectId=project_id,source=source,selected=selected,mode=mode,
                words=words,style=body.style or project.get('style','Stylized'),name=project.get('name','Concept'),
                ids=ids,index=0,outputs=[],createdAt=self.now(),deadline=self.now()+DEADLINE,leaseUntil=0,
                autoModel=auto_model,autoAnimation=auto_animation))
            tx.set(wallet_ref,after,merge=True)
            expired=max(0,int(before.get('subscriptionAvailable',0))-int(after.get('subscriptionAvailable',0))-allocation['subscription'])
            if expired:tx.create(wallet_ref.collection('entries').document(jid+':expiry'),dict(id=jid+':expiry',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':reserve'),dict(id=jid+':reserve',amount=-cost,kind='generation_reservation',createdAt=self.now(),jobId=jid))
            return data
        return transact(self.db,create)

    def claim(self,uid,jid):
        public,private=self.refs(uid,jid);token=uuid.uuid4().hex
        def claim(tx):
            self.active(uid,tx);data=private.get(transaction=tx).to_dict()
            if not data:raise HTTPException(503,'Waiting for the concept job.')
            if data['phase'] in TERMINAL:return None,data
            if data.get('leaseUntil',0)>self.now():raise HTTPException(503,'Concept work is already running.')
            tx.update(private,{'leaseToken':token,'leaseUntil':self.now()+LEASE})
            phase=data['phase']
            if phase.startswith('plan'):
                stage,message='analyzing_reference','Preparing your concept prompt'
            elif phase.startswith('audit'):
                stage,message='validating_views','Checking the generated views'
            else:
                stage,message='rendering_views','Creating your concept image'
            # Publish work as soon as the durable worker claims it, rather than
            # leaving the app queued until the first image has already finished.
            tx.update(public,{'status':'running','stage':stage,'message':message})
            return token,data
        return transact(self.db,claim)

    def advance(self,uid,jid,token,phase,updates):
        _,private=self.refs(uid,jid)
        def update(tx):
            self.active(uid,tx);data=private.get(transaction=tx).to_dict() or {}
            if data.get('leaseToken')!=token or data.get('phase')!=phase or data.get('leaseUntil',0)<=self.now():raise HTTPException(503,'Concept work will resume.')
            tx.update(private,updates)
        transact(self.db,update)

    def read_image(self,path):
        if not path:return None
        blob=self.studio.bucket.blob(path);blob.reload(timeout=30)
        if not blob.size or blob.size>MAX_BYTES:raise provider.planner.PlannerError('This reference is too large.')
        return blob.download_as_bytes(if_generation_match=blob.generation,timeout=30)

    def saved_output(self,uid,jid,data):
        index=data['index'];cid=data['ids'][index];name=f'users/{uid}/images/{cid}.jpg'
        blob=self.studio.bucket.blob(name)
        try:blob.reload(timeout=30)
        except NotFound:return None
        meta=blob.metadata or {}
        if meta.get('jobId')!=jid or meta.get('index')!=str(index):raise HTTPException(409,'Image output conflict.')
        saved=json.loads(meta['result'])
        return {**saved,'path':name,'id':cid,'index':index}

    def publish_image(self,uid,jid,token):
        public,private=self.refs(uid,jid)
        def publish(tx):
            self.active(uid,tx);data=private.get(transaction=tx).to_dict()
            if data.get('phase')!='image_saved' or data.get('leaseToken')!=token or data.get('leaseUntil',0)<=self.now():raise HTTPException(503,'Image publication will resume.')
            project=self.projects.ref(uid,'studioProjects',data['projectId']).get(transaction=tx).to_dict()
            if not project:raise HTTPException(404,'Project no longer exists.')
            saved=data['saved'];index=data['index'];cid=saved['id'];outputs=data['outputs']+[saved]
            direction=provider.VIEWS[index][1] if data['mode']=='angles' else None
            label=provider.VIEWS[index][0] if direction else 'Refined concept' if data['mode']=='refine' else f'Concept {index+1}'
            concept=dict(id=cid,ownerId=uid,projectId=data['projectId'],parentId=data['selected'],name=data['name'],label=label,
                prompt=data.get('brief',data['words']),imageUrl='gs://'+BUCKET+'/'+saved['path'],width=saved['width'],height=saved['height'],
                direction=direction,isOriginal=False,viewSetId=jid,imageModel=model_of(data),imageProvider='google',createdAt=self.now(),storageVersion=2)
            job=public.get(transaction=tx).to_dict()
            tx.create(self.projects.ref(uid,'studioConcepts',cid),concept)
            tx.create(self.projects.ref(uid,'mobileCreations','concept:'+cid),dict(ownerId=uid,source='ios',storageVersion=2,
                name=data['name'],kind='Concept image',projectId=data['projectId'],conceptIds=[cid],prompt=concept['prompt'],previewStoragePath=saved['path'],createdAt=self.now()))
            done=index+1==len(data['ids'])
            phase='audit_ready' if done and len(outputs)>1 and data['mode']=='angles' else 'finish_ready' if done else 'render_ready'
            tx.update(private,dict(outputs=outputs,index=index+1,phase=phase,leaseUntil=0))
            tx.update(public,dict(status='running',stage='validating_views' if phase=='audit_ready' else 'rendering_views',progress=int(85*len(outputs)/len(data['ids'])),concepts=job['concepts']+[concept],message=f"Saved {len(outputs)} of {len(data['ids'])} concepts"))
        transact(self.db,publish)

    def finish(self,uid,jid,token,error=None):
        public,private=self.refs(uid,jid)
        def finish(tx):
            self.active(uid,tx);data=private.get(transaction=tx).to_dict()
            if data['phase'] in TERMINAL:return public.get(transaction=tx).to_dict()
            if data.get('leaseToken')!=token or data.get('leaseUntil',0)<=self.now():raise HTTPException(503,'Settlement will resume.')
            outputs=data['outputs'];cost=data['allocation']['cost']
            charge=min(cost,sum(o['tokens'] for o in outputs)+data.get('planning',{}).get('tokens',0)+data.get('audit',{}).get('tokens',0)) if outputs else 0
            wallet_ref=self.billing.private(uid,data['walletName']);wallet=wallet_ref.get(transaction=tx).to_dict() or {}
            allocation=data['allocation'];refunded=False
            if allocation.get('subscriptionTransaction'):
                key=hashlib.sha256(('APP_STORE:'+allocation['subscriptionTransaction']).encode()).hexdigest()
                receipt=self.db.collection('billingReceipts').document(key).get(transaction=tx).to_dict()
                refunded=not receipt or receipt.get('refunded',False)
            current=expire_allowance(wallet,self.now());after=settle(wallet,allocation,charge,self.now(),refunded)
            returned=after.get('available',0)+after.get('subscriptionAvailable',0)-current.get('available',0)-current.get('subscriptionAvailable',0)
            expired=max(0,int(wallet.get('subscriptionAvailable',0))-int(current.get('subscriptionAvailable',0)))
            job=public.get(transaction=tx).to_dict()
            status='done' if len(outputs)==len(data['ids']) else 'partial' if outputs else 'failed'
            validation=data.get('validation') or {'usable':False,'issues':['Review these candidate images before choosing inputs.']}
            update=dict(status=status,stage='ready' if outputs else 'failed',progress=100,charged=charge,reserved=0,
                completedAt=self.now(),message='Concepts are ready' if outputs else 'Concept generation did not complete',
                error=error if error else None if status=='done' else 'Some images could not be confirmed. Unused Tokens were released.',
                validation=validation,warnings=validation['issues'])
            tx.set(wallet_ref,after,merge=True)
            if expired:tx.create(wallet_ref.collection('entries').document(jid+':expiry-settle'),dict(id=jid+':expiry-settle',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':settled'),dict(id=jid+':settled',amount=max(0,returned),charged=charge,kind='generation_complete' if outputs else 'generation_refund',createdAt=self.now(),jobId=jid))
            tx.update(private,dict(phase=status,leaseUntil=0,charged=charge));tx.update(public,update)
            return {**job,**update}
        result = transact(self.db,finish)
        from . import live_activity
        live_activity.notify(self.db, uid, {**result, 'id': jid})
        return result

    def save_render(self,uid,jid,index,cid,made):
        raw=made.pop('bytes');blob=self.studio.bucket.blob(f'users/{uid}/images/{cid}.jpg')
        blob.cache_control='private, max-age=3600';blob.metadata={'ownerId':uid,'jobId':jid,'index':str(index),'result':json.dumps(made)}
        try:blob.upload_from_string(raw,content_type='image/jpeg',if_generation_match=0,timeout=120,retry=None)
        except PreconditionFailed:pass

    def render_batch(self,uid,jid,token,data):
        """Render every remaining turnaround view at once. They all derive from the
        already-published front view, so none of them depends on another."""
        indices=list(range(data['index'],len(data['ids'])))
        reference=self.read_image(data['outputs'][0]['path']);brief=data.get('brief',data['words'])
        model=model_of(data)
        payloads={i:provider.body(provider.view_prompt(brief,i,data['mode'],data['style']),reference,model) for i in indices}
        for payload in payloads.values():provider.preflight(payload,model)
        self.advance(uid,jid,token,'render_ready',dict(phase='batch_calling',batch=indices))
        def one(i):
            # Any failure leaves this view unsaved; it is skipped and never charged.
            # Catching broadly keeps one bad call from stranding the others' results.
            try:self.save_render(uid,jid,i,data['ids'][i],provider.generate(payloads[i],data['estimate']['rates'],model))
            except Exception:logging.getLogger(__name__).warning('Concept view %s did not render',i)
        with ThreadPoolExecutor(max_workers=len(indices)) as pool:list(pool.map(one,indices))
        self.advance(uid,jid,token,'batch_calling',dict(phase='render_ready',leaseUntil=0))

    def skip_view(self,uid,jid,token,data):
        index=data['index']
        last=index+1==len(data['ids'])
        phase=('audit_ready' if len(data['outputs'])>1 and data['mode']=='angles' else 'finish_ready') if last else 'render_ready'
        self.advance(uid,jid,token,'render_ready',dict(index=index+1,phase=phase,leaseUntil=0))

    def run(self,uid,jid,queued_at=None):
        started=self.now()
        while True:
            outcome=self.step(uid,jid,queued_at)
            if outcome is not CONTINUE:return outcome
            # Durable redelivery resumes from the persisted phase; never a process thread.
            if self.now()-started>STAGE_BUDGET:raise HTTPException(503,'Concept work continues in the cloud.')

    def step(self,uid,jid,queued_at=None):
        public,private=self.refs(uid,jid)
        if not private.get().exists and queued_at and self.now()-queued_at>300:return {'status':'absent'}
        try:token,data=self.claim(uid,jid)
        except HTTPException as exc:
            if exc.status_code==403:return {'status':'deleted'}
            raise
        if not token:return public.get().to_dict()
        phase=data['phase']
        # Publication must finish before the pre-enqueued orphan cleanup can run.
        if self.now()>=min(data['deadline'],data['estimate']['expiresAt']):return self.finish(uid,jid,token,'This request expired. Completed images are kept; unused Tokens were released.')
        if phase=='image_saved':
            if not self.saved_output(uid,jid,data):return self.finish(uid,jid,token,'The generated image is no longer available. Unused Tokens were released.')
            self.publish_image(uid,jid,token)
        elif phase=='render_calling':
            saved=self.saved_output(uid,jid,data)
            if not saved:return self.finish(uid,jid,token,'This image response could not be recovered. Unused Tokens were released.')
            self.advance(uid,jid,token,phase,dict(phase='image_saved',saved=saved))
            self.publish_image(uid,jid,token)
        elif phase=='batch_calling':
            # The worker stopped while batch calls were in flight. Publish whatever
            # images were saved; the rest are skipped rather than paid for twice.
            self.advance(uid,jid,token,phase,dict(phase='render_ready',leaseUntil=0))
        elif phase in ('plan_calling','audit_calling','finish_ready'):return self.finish(uid,jid,token)
        else:
            try:
                if phase=='plan_ready':
                    if data['mode'] in ('reference','refine'):
                        self.advance(uid,jid,token,phase,dict(phase='render_ready',brief=data['words'],leaseUntil=0))
                    else:
                        payload=provider.plan_body(data['words'],self.read_image(data['source']),data['style'])
                        provider.planner.preflight(payload)
                        self.advance(uid,jid,token,phase,dict(phase='plan_calling'))
                        answer=provider.planner.generate(payload,data['estimate']['planning']['rates'])
                        self.advance(uid,jid,token,'plan_calling',dict(phase='render_ready',brief=answer['prompt'],planning=answer,leaseUntil=0))
                elif phase=='render_ready':
                    index=data['index'];source=data['source']
                    saved=self.saved_output(uid,jid,data) if data.get('batch') else None
                    if saved:
                        # Already rendered by a parallel batch: publish it without another paid call.
                        self.advance(uid,jid,token,phase,dict(phase='image_saved',saved=saved))
                        self.publish_image(uid,jid,token);return CONTINUE
                    if index in data.get('batch',[]):
                        # Its batch call did not produce an image. Never re-issue a paid call.
                        self.skip_view(uid,jid,token,data);return CONTINUE
                    if data['mode']=='angles' and index>0 and len(data['ids'])-index>1:
                        self.render_batch(uid,jid,token,data);return CONTINUE
                    if index>0 and data['mode']=='angles':source=data['outputs'][0]['path']
                    model=model_of(data)
                    payload=provider.body(provider.view_prompt(data.get('brief',data['words']),index,data['mode'],data['style']),self.read_image(source),model)
                    provider.preflight(payload,model)
                    self.advance(uid,jid,token,phase,dict(phase='render_calling'))
                    self.save_render(uid,jid,index,data['ids'][index],provider.generate(payload,data['estimate']['rates'],model))
                    saved=self.saved_output(uid,jid,data)
                    self.advance(uid,jid,token,'render_calling',dict(phase='image_saved',saved=saved))
                    self.publish_image(uid,jid,token)
                elif phase=='audit_ready':
                    payload=provider.audit_body([self.read_image(o['path']) for o in data['outputs']],[provider.VIEWS[o.get('index',i)][1] for i,o in enumerate(data['outputs'])])
                    provider.planner.preflight(payload)
                    self.advance(uid,jid,token,phase,dict(phase='audit_calling'))
                    answer=provider.planner.generate(payload,data['estimate']['planning']['rates'])
                    passed=answer['prompt']=='PASS'
                    self.advance(uid,jid,token,'audit_calling',dict(phase='finish_ready',audit=answer,validation={'usable':passed,'issues':[] if passed else [answer['prompt']]},leaseUntil=0))
                else:raise HTTPException(503,'Unexpected concept state.')
            except (provider.planner.PlannerError,NotFound) as exc:
                return self.finish(uid,jid,token,str(exc) if isinstance(exc,provider.planner.PlannerError) else 'The saved reference is no longer available.')
        return CONTINUE
