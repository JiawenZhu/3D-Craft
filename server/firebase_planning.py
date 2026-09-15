"""Durable prompt suggestions with explicit spending consent and single submission."""
import hashlib
import json
import os
import random
import time
import uuid
from urllib.parse import quote as urlquote

from fastapi import HTTPException
from firebase_admin import firestore
from pydantic import BaseModel, Field, ConfigDict
from typing import Literal
from . import cloud_planner_provider as provider
from .firebase_billing import CloudBilling
from .firebase_projects import CloudProjects, MAX_BYTES
from .firebase_studio import BUCKET, uid_for
from .firebase_usage import reserve, settle
from .firebase_subscriptions import expire_allowance
from google.api_core.exceptions import Aborted, NotFound
from google.cloud.firestore_v1.base_query import FieldFilter
from PIL import UnidentifiedImageError


def transact(db, operation):
    wrapped = firestore.transactional(operation)
    for attempt in range(4):
        try: return wrapped(db.transaction())
        except (Aborted, ValueError) as exc:
            if not isinstance(exc, Aborted) and not isinstance(exc.__cause__, Aborted): raise
            if attempt == 3: raise HTTPException(503, "Planning is busy. Retry the same request.") from None
            time.sleep(random.uniform(.05,.15) * 2**attempt)

LEASE = 600
DEADLINE = 1800
TERMINAL = ('done','failed')


class PromptRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    idempotencyKey: str = Field(min_length=8,max_length=120)
    prompt: str = Field(default='',max_length=4000)
    plannerModel: Literal['gemini-3.8-flash'] = provider.MODEL
    plannerEffort: Literal['low','medium','high'] = 'low'
    maxTokens: int = Field(strict=True,ge=1,le=100)


class ChatRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    clientId: str = Field(min_length=8,max_length=120)
    text: str = Field(min_length=1,max_length=4000)
    plannerModel: Literal['gemini-3.8-flash'] = provider.MODEL
    plannerEffort: Literal['low','medium','high'] = 'low'
    conceptId: str | None = Field(default=None,max_length=150)
    style: str = Field(default='Stylized',max_length=100)
    maxTokens: int = Field(strict=True,ge=1,le=100)


def bounded_history(turns, text):
    history=[];brief=''
    for turn in turns:
        if turn.get('status')!='done': continue
        history.extend([{'role':'user','text':str(turn.get('text',''))[:4000]},
                        {'role':'assistant','text':str(turn.get('reply',''))[:4000]}])
        if turn.get('brief'): brief=str(turn['brief'])[:4000]
    history.append({'role':'user','text':text})
    # The latest brief carries earlier decisions; retain the recent dialogue
    # within the quoted input budget instead of growing every request forever.
    while len(history)>1 and (len(history)>21 or sum(len(t['text']) for t in history)>12000):
        history.pop(0)
    return history,brief


def image_path(uid, path):
    prefix=f'gs://{BUCKET}/users/{uid}/'
    if not isinstance(path,str): raise HTTPException(422,'Save this reference in your cloud library first.')
    relative=path.removeprefix(prefix).split('/')
    if (not path.startswith(prefix) or len(relative)!=2 or relative[0] not in ('images','files','previews')
            or relative[1] in ('','.','..') or relative[1].rsplit('.',1)[-1].lower() not in ('png','jpg','jpeg','webp')):
        raise HTTPException(422,'Save this reference in your cloud library first.')
    return path.removeprefix(f'gs://{BUCKET}/')


def enqueue(uid,jid):
    from google.cloud import tasks_v2
    client=tasks_v2.CloudTasksClient()
    base=os.environ['CRAFT_TASK_ORIGIN'].rstrip('/')
    client.create_task(parent=client.queue_path(provider.PROJECT,'us-central1','craft-planning-jobs'),task={
        'http_request':{'http_method':tasks_v2.HttpMethod.POST,
            'url':f'{base}/internal/planning/{urlquote(uid,safe="")}/{jid}',
            'headers':{'X-Craft-Queued-At':str(int(time.time()))},
            'oidc_token':{'service_account_email':os.environ['CRAFT_TASK_IDENTITY'],'audience':base}}},timeout=30,retry=None)


def visible(data):
    return {k:data[k] for k in ('id','status','prompt','model','maxTokens','charged','error','createdAt','completedAt','projectId','text','reply','brief','ready','suggestions') if k in data}


class CloudPlanning:
    def __init__(self,studio,clock=None):
        self.studio,self.db=studio,studio.db
        self.now=clock or time.time
        self.billing=CloudBilling(self.db,self.now)
        self.projects=CloudProjects(studio)

    def ref(self,uid,jid):
        uid_for('firebase:'+uid)
        if len(jid)!=67 or not jid.startswith('pj-') or any(c not in '0123456789abcdef' for c in jid[3:]):
            raise HTTPException(422,'Invalid planning identifier.')
        return self.billing.private(uid,'planningJobs').collection('items').document(jid)

    def active(self,uid,tx):
        if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
            raise HTTPException(403,'This account is being deleted.')

    def get(self,owner,jid):
        uid=uid_for(owner)
        data=self.ref(uid,jid).get().to_dict()
        if not data: raise HTTPException(404,'Suggestion not found in this account.')
        return visible(data)

    def create(self,owner,cid,body):
        uid=uid_for(owner);started=self.now()
        jid='pj-'+hashlib.sha256((uid+':'+body.idempotencyKey).encode()).hexdigest()
        ref=self.ref(uid,jid)
        options=body.model_dump(exclude={'idempotencyKey'})
        signature=hashlib.sha256(json.dumps([cid,options],sort_keys=True).encode()).hexdigest()
        enqueue(uid,jid)
        def create(tx):
            self.active(uid,tx)
            prior=ref.get(transaction=tx).to_dict()
            if prior:
                if prior['signature']!=signature: raise HTTPException(409,'This request already belongs to a different suggestion.')
                return visible(prior)
            concept=self.projects.ref(uid,'studioConcepts',cid).get(transaction=tx).to_dict()
            if not concept or concept.get('ownerId')!=uid: raise HTTPException(404,'Image not found in this account.')
            path=image_path(uid,concept.get('imageUrl'))
            estimate=provider.quote(self.now());cost=estimate['maxTokens']
            if body.maxTokens < cost: raise HTTPException(409,'The planning price changed. Refresh the price before continuing.')
            context=self.billing.private(uid,'billingContext').get(transaction=tx).to_dict() or {}
            sandbox=context.get('environment')=='SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX')=='1'
            wallet_name='sandboxWallet' if sandbox else 'wallet'
            wallet_ref=self.billing.private(uid,wallet_name)
            before=wallet_ref.get(transaction=tx).to_dict() or {}
            after,allocation=reserve({**before,'environment':'SANDBOX' if sandbox else 'PRODUCTION'},cost,self.now())
            if self.now()-started>120: raise HTTPException(503,'Please retry this request.')
            data=dict(id=jid,signature=signature,options=options,image=path,
                status='queued',phase='queued',model=provider.MODEL,maxTokens=cost,charged=0,
                estimate=estimate,allocation=allocation,walletName=wallet_name,createdAt=self.now(),
                deadline=self.now()+DEADLINE,leaseUntil=0,error=None)
            tx.create(ref,data);tx.set(wallet_ref,after,merge=True)
            expired=max(0,int(before.get('subscriptionAvailable',0))-int(after.get('subscriptionAvailable',0))-allocation['subscription'])
            if expired: tx.create(wallet_ref.collection('entries').document(jid+':expiry'),dict(id=jid+':expiry',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':reserve'),dict(id=jid+':reserve',amount=-cost,kind='planning_reservation',createdAt=self.now(),jobId=jid))
            return visible(data)
        return transact(self.db,create)

    def create_chat(self,owner,project_id,body):
        uid=uid_for(owner);started=self.now()
        if not body.text.strip():raise HTTPException(422,'Write a message first.')
        jid='pj-'+hashlib.sha256((uid+':'+body.clientId).encode()).hexdigest()
        ref=self.ref(uid,jid);project_ref=self.projects.ref(uid,'studioProjects',project_id)
        turn_ref=self.projects.ref(uid,'studioConversations',jid)
        options=body.model_dump(exclude={'clientId'})
        signature=hashlib.sha256(json.dumps(['chat',project_id,options],sort_keys=True).encode()).hexdigest()
        enqueue(uid,jid)
        def create(tx):
            self.active(uid,tx)
            prior=ref.get(transaction=tx).to_dict()
            if prior:
                if prior['signature']!=signature:raise HTTPException(409,'This message ID already belongs to another request.')
                return visible(prior)
            project=project_ref.get(transaction=tx).to_dict()
            if not project or project.get('ownerId')!=uid:raise HTTPException(404,'Project not found in this account.')
            if project.get('activeChatJobId'):
                active=self.ref(uid,project['activeChatJobId']).get(transaction=tx).to_dict() or {}
                if active and active.get('phase') not in TERMINAL:raise HTTPException(409,'Wait for the current reply before sending another message.')
            source=project.get('imageUrl')
            if body.conceptId:
                concept=self.projects.ref(uid,'studioConcepts',body.conceptId).get(transaction=tx).to_dict()
                if not concept or concept.get('ownerId')!=uid or concept.get('projectId')!=project_id:
                    raise HTTPException(404,'Choose a reference from this conversation.')
                source=concept.get('imageUrl')
            source=image_path(uid,source) if source else None
            query=self.db.collection('users').document(uid).collection('studioConversations').where(
                filter=FieldFilter('projectId','==',project_id)).order_by('createdAt',direction=firestore.Query.DESCENDING).limit(20)
            previous=[snap.to_dict() for snap in query.get(transaction=tx)]
            history,brief=bounded_history(list(reversed(previous)),body.text.strip())
            estimate=provider.quote(self.now(),'chat');cost=estimate['maxTokens']
            if body.maxTokens<cost:raise HTTPException(409,'The chat price changed. Refresh the price before sending.')
            context=self.billing.private(uid,'billingContext').get(transaction=tx).to_dict() or {}
            sandbox=context.get('environment')=='SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX')=='1'
            wallet_name='sandboxWallet' if sandbox else 'wallet';wallet_ref=self.billing.private(uid,wallet_name)
            before=wallet_ref.get(transaction=tx).to_dict() or {}
            after,allocation=reserve({**before,'environment':'SANDBOX' if sandbox else 'PRODUCTION'},cost,self.now())
            if self.now()-started>120:raise HTTPException(503,'Please retry this message.')
            data=dict(id=jid,kind='chat',signature=signature,options=options,image=source,history=history,
                previousBrief=str(project.get('creativeBrief') or brief or project.get('prompt',''))[:4000],projectId=project_id,text=body.text.strip(),
                status='working',phase='queued',model=provider.MODEL,maxTokens=cost,charged=0,
                estimate=estimate,allocation=allocation,walletName=wallet_name,createdAt=self.now(),
                deadline=self.now()+DEADLINE,leaseUntil=0,error=None)
            tx.create(ref,data)
            tx.create(turn_ref,{**visible(data),'ownerId':uid,'storageVersion':2})
            tx.update(project_ref,{'activeChatJobId':jid})
            tx.set(wallet_ref,after,merge=True)
            expired=max(0,int(before.get('subscriptionAvailable',0))-int(after.get('subscriptionAvailable',0))-allocation['subscription'])
            if expired:tx.create(wallet_ref.collection('entries').document(jid+':expiry'),dict(id=jid+':expiry',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':reserve'),dict(id=jid+':reserve',amount=-cost,kind='chat_reservation',createdAt=self.now(),jobId=jid))
            return visible(data)
        return transact(self.db,create)

    def claim(self,uid,jid):
        ref=self.ref(uid,jid);token=uuid.uuid4().hex
        def claim(tx):
            self.active(uid,tx)
            data=ref.get(transaction=tx).to_dict()
            if not data: raise HTTPException(503,'Waiting for the suggestion record.')
            if data['phase'] in TERMINAL: return None,data
            if data.get('leaseUntil',0)>self.now(): raise HTTPException(503,'Suggestion is still running.')
            tx.update(ref,dict(leaseToken=token,leaseUntil=self.now()+LEASE))
            return token,data
        return transact(self.db,claim)

    def advance(self,uid,jid,token,phase,updates):
        ref=self.ref(uid,jid)
        def advance(tx):
            self.active(uid,tx);data=ref.get(transaction=tx).to_dict() or {}
            if data.get('leaseToken')!=token or data.get('phase')!=phase or data.get('leaseUntil',0)<=self.now():
                raise HTTPException(503,'Suggestion will be checked again.')
            tx.update(ref,updates)
        transact(self.db,advance)

    def finish(self,uid,jid,token,error=None):
        ref=self.ref(uid,jid)
        def finish(tx):
            self.active(uid,tx);data=ref.get(transaction=tx).to_dict() or {}
            if data.get('phase') in TERMINAL: return visible(data)
            if data.get('leaseToken')!=token or data.get('leaseUntil',0)<=self.now(): raise HTTPException(503,'Suggestion will be checked again.')
            answer=data.get('answer') if data.get('phase')=='answered' else None
            project_ref=self.projects.ref(uid,'studioProjects',data['projectId']) if data.get('kind')=='chat' else None
            project=project_ref.get(transaction=tx).to_dict() if project_ref else None
            if project_ref and not project:answer=None
            charge=min(data['maxTokens'],answer['tokens']) if answer else 0
            wallet_ref=self.billing.private(uid,data['walletName']);wallet=wallet_ref.get(transaction=tx).to_dict() or {}
            allocation=data['allocation'];refunded=False
            if allocation.get('subscriptionTransaction'):
                key=hashlib.sha256(('APP_STORE:'+allocation['subscriptionTransaction']).encode()).hexdigest()
                receipt=self.db.collection('billingReceipts').document(key).get(transaction=tx).to_dict()
                refunded=not receipt or receipt.get('refunded',False)
            after=settle(wallet,allocation,charge,self.now(),refunded)
            current=expire_allowance(wallet,self.now())
            returned=after.get('available',0)+after.get('subscriptionAvailable',0)-current.get('available',0)-current.get('subscriptionAvailable',0)
            expired=max(0,int(wallet.get('subscriptionAvailable',0))-int(current.get('subscriptionAvailable',0)))
            tx.set(wallet_ref,after,merge=True)
            if expired:tx.create(wallet_ref.collection('entries').document(jid+':expiry-settle'),dict(id=jid+':expiry-settle',amount=-expired,kind='subscription_expiry',createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid+':settled'),dict(id=jid+':settled',amount=max(0,returned),charged=charge,kind=('chat_complete' if answer else 'chat_refund') if data.get('kind')=='chat' else ('planning_complete' if answer else 'planning_refund'),createdAt=self.now(),jobId=jid))
            updates=dict(status='done' if answer else 'failed',phase='done' if answer else 'failed',charged=charge,
                         leaseUntil=0,completedAt=self.now(),error=None if answer else error or 'The suggestion could not be confirmed. Reserved Tokens were released.')
            if answer:
                if data.get('kind')=='chat':updates.update({k:answer[k] for k in ('reply','brief','ready','suggestions')})
                else:updates['prompt']=answer['prompt']
            tx.update(ref,updates)
            if project_ref and project:
                tx.update(self.projects.ref(uid,'studioConversations',jid),visible({**data,**updates}))
                if project.get('activeChatJobId')==jid:
                    project_update={'activeChatJobId':None}
                    if answer:project_update['creativeBrief']=answer['brief']
                    tx.update(project_ref,project_update)
            return visible({**data,**updates})
        return transact(self.db,finish)

    def run(self,uid,jid,queued_at=None):
        if not self.ref(uid,jid).get().exists and queued_at and self.now()-queued_at>300: return {'status':'absent'}
        try: token,data=self.claim(uid,jid)
        except HTTPException as exc:
            if exc.status_code==403:return {'status':'deleted'}
            raise
        if not token:return visible(data)
        # A synchronous provider has no durable result lookup. Never issue it
        # twice after a crash or an uncertain response; release the reservation.
        if data['phase']=='answered':return self.finish(uid,jid,token)
        if data['phase']=='calling' or self.now()>=min(data['deadline'],data['estimate']['expiresAt']):
            return self.finish(uid,jid,token)
        try:
            image=None
            if data.get('image'):
                blob=self.studio.bucket.blob(data['image']);blob.reload(timeout=30)
                if not blob.size or blob.size>MAX_BYTES:return self.finish(uid,jid,token,'This saved image is too large to plan from.')
                image=blob.download_as_bytes(if_generation_match=blob.generation,timeout=30)
            if data.get('kind')=='chat':
                payload=provider.chat_body(data['history'],data['previousBrief'],data['options']['style'],image,data['options']['plannerEffort'])
            else:payload=provider.body(data['options']['prompt'],image,data['options']['plannerEffort'])
            provider.preflight(payload,data['estimate'].get('maxInput',provider.MAX_INPUT))
        except NotFound:return self.finish(uid,jid,token,'The saved reference is no longer available.')
        except provider.PlannerError as exc:return self.finish(uid,jid,token,str(exc))
        except (UnidentifiedImageError, OSError):return self.finish(uid,jid,token,'The saved reference could not be read. Try uploading it again.')
        # Check the quote again after potentially slow, uncharged preparation.
        if self.now()>=min(data['deadline'],data['estimate']['expiresAt']):return self.finish(uid,jid,token)
        self.advance(uid,jid,token,'queued',{'phase':'calling','status':'working'})
        try:answer=provider.generate(payload,data['estimate']['rates'],data.get('kind','prompt'))
        except provider.PlannerError as exc:return self.finish(uid,jid,token,str(exc))
        self.advance(uid,jid,token,'calling',{'phase':'answered','answer':answer})
        return self.finish(uid,jid,token)
