"""Cloud-only studio API. No SQLite databases, laptop paths or local sessions.

Readiness reports whether the verified Gemini-to-3D cloud pipeline is enabled.
It is an operational signal, not an App Store review or device-QA status.
"""
from functools import lru_cache
import os
import json
from urllib.parse import quote
from fastapi import FastAPI, Depends, HTTPException, Header, Form, File, UploadFile, Request, Query
from starlette.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from .identity import require_claims
from .firebase_studio import FirebaseStudio, BUCKET
from .firebase_billing import CloudBilling
from .firebase_webhooks import reconcile_webhook
from .firebase_projects import CloudProjects, MAX_BYTES
from .firebase_model_jobs import CloudModelJobs, ModelRequest
from .firebase_planning import CloudPlanning, PromptRequest, ChatRequest
from . import cloud_planner_provider, cloud_concept_provider
from .firebase_concepts import CloudConcepts, ConceptRequest
import time
from .firebase_community import CloudCommunity, Submission, Vote, Report, GameLink, Category
from . import cloud_model_provider, pricing
from pydantic import BaseModel, Field
from typing import Literal
from .account_deletion import ensure_active, request_deletion, erase_account, verify_worker

app = FastAPI(title='3D Craft Cloud API')
app.add_middleware(CORSMiddleware, allow_origins=['https://3d-craft.web.app'], allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type'])

@lru_cache
def studio(): return FirebaseStudio()

def owner(claims=Depends(require_claims)):
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    return 'firebase:' + uid


def public_shape(data, account):
    uid = account.removeprefix('firebase:')
    if isinstance(data, dict): return {k: public_shape(v,account) for k,v in data.items()}
    if isinstance(data, list): return [public_shape(v,account) for v in data]
    prefix = f'gs://{BUCKET}/users/{uid}/'
    if isinstance(data,str) and data.startswith('gs://'):
        if not data.startswith(prefix): raise HTTPException(500,'A cloud file could not be resolved for this account.')
        path = data.removeprefix(f'gs://{BUCKET}/')
        return f'https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{quote(path,safe="")}?alt=media'
    return data


@app.get('/api/health')
def health():
    return {'status':'ok','storage':'firebase','apiOrigin':'https://3d-craft.web.app','generationReady':generation_ready(),
            'modelGenerationReady':model_ready()}


def model_ready():
    return os.getenv('CRAFT_MODEL_JOBS_ENABLED')=='1' and bool(os.getenv('FAL_KEY'))


@app.post('/api/mobile/concepts/{concept_id}/model')
def generate_model(concept_id: str, body: ModelRequest, account=Depends(owner)):
    if not model_ready(): raise HTTPException(503,'Cloud 3D generation is temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudModelJobs(studio()).create(account,concept_id,body),account)


def planning_ready():
    return os.getenv('CRAFT_PLANNING_ENABLED') == '1'


def concepts_ready():
    return planning_ready() and os.getenv('CRAFT_CONCEPT_JOBS_ENABLED') == '1'


def generation_ready():
    return concepts_ready() and model_ready()


@app.get('/api/mobile/image-models')
def image_models(account=Depends(owner)):
    now=time.time()
    return {'defaultModel':cloud_concept_provider.MODEL,'expiresAt':cloud_concept_provider.quote(now)['expiresAt'],
        'maxTokensByCount':{str(n):cloud_concept_provider.quote(now,n)['maxTokens'] for n in range(1,5)},
        'models':[dict(id=cloud_concept_provider.MODEL,name='Gemini 3 Pro Image · Nano Banana Pro',provider='google',
            quality='Pro',imageSize='2K',available=concepts_ready(),unavailableReason=None if concepts_ready() else 'Cloud concepts are temporarily unavailable.')]}


@app.post('/api/mobile/projects/{project_id}/concepts')
def generate_concepts(project_id:str,body:ConceptRequest,account=Depends(owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudConcepts(studio()).create(account,project_id,body),account)


@app.post('/api/mobile/concepts/{concept_id}/refine')
def refine_concept(concept_id:str,body:ConceptRequest,account=Depends(owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    uid=account.removeprefix('firebase:');service=CloudConcepts(studio())
    concept=service.projects.ref(uid,'studioConcepts',concept_id).get().to_dict()
    if not concept or concept.get('ownerId')!=uid:raise HTTPException(404,'Image not found in this account.')
    return public_shape(service.create(account,concept['projectId'],body,concept_id),account)


@app.post('/internal/concepts/{uid}/{job_id}')
def concept_worker(uid:str,job_id:str,authorization:str=Header(default=''),x_craft_queued_at:int|None=Header(default=None)):
    verify_worker(authorization)
    return CloudConcepts(studio()).run(uid,job_id,x_craft_queued_at)


@app.get('/api/mobile/planning/quote')
def planning_quote(kind: Literal['prompt','chat']='prompt', account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable.')
    return cloud_planner_provider.quote(time.time(),kind)


@app.post('/api/mobile/projects/{project_id}/chat')
def send_chat(project_id: str, body: ChatRequest, account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503,'Cloud creative chat is temporarily unavailable. No Tokens were charged.')
    return CloudPlanning(studio()).create_chat(account,project_id,body)


@app.post('/api/mobile/concepts/{concept_id}/model-prompt')
def improve_prompt(concept_id: str, body: PromptRequest, account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable. No Tokens were charged.')
    return CloudPlanning(studio()).create(account, concept_id, body)


@app.get('/api/mobile/planning/{job_id}')
def planning_result(job_id: str, account=Depends(owner)):
    return CloudPlanning(studio()).get(account, job_id)


@app.post('/internal/planning/{uid}/{job_id}')
def planning_worker(uid: str, job_id: str, authorization: str = Header(default=''),
                    x_craft_queued_at: int | None = Header(default=None)):
    verify_worker(authorization)
    return CloudPlanning(studio()).run(uid, job_id, x_craft_queued_at)


@app.get('/api/mobile/pricing')
def provider_pricing(account=Depends(owner)):
    return pricing.catalog()


@app.get('/api/mobile/projects')
def projects(account=Depends(owner)):
    records = studio().records(account,'studioProjects')
    concepts = studio().records(account,'studioConcepts')
    turns = studio().records(account,'studioConversations')
    for project in records:
        project['concepts'] = sorted([c for c in concepts if c.get('projectId') == project['id']],key=lambda c:c.get('createdAt',0))
        project['conversation'] = sorted([t for t in turns if t.get('projectId') == project['id']],key=lambda t:t.get('createdAt',0))
    return public_shape(sorted(records,key=lambda p:p.get('createdAt',0),reverse=True),account)


@app.post('/api/mobile/projects')
async def create_project(prompt: str = Form(default=''), name: str = Form(default='Untitled idea'),
        style: str = Form(default='Stylized'), image: UploadFile | None = File(default=None),
        clientId: str | None = Form(default=None), account=Depends(owner)):
    raw = await image.read(MAX_BYTES + 1) if image else None
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        prompt=prompt, name=name, style=style, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.post('/api/mobile/projects/{project_id}/references')
async def add_reference(project_id: str, image: UploadFile = File(...),
        clientId: str | None = Form(default=None), account=Depends(owner)):
    raw = await image.read(MAX_BYTES + 1)
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        project_id=project_id, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.get('/api/mobile/jobs')
def jobs(account=Depends(owner)):
    return public_shape(sorted(studio().records(account,'studioJobs'),key=lambda j:j.get('createdAt',0),reverse=True),account)


@app.get('/api/mobile/jobs/{ident}')
def job(ident: str, account=Depends(owner)):
    item = next((j for j in studio().records(account,'studioJobs') if j['id']==ident),None)
    if item is None: raise HTTPException(404,'Creation not found in your account.')
    return public_shape(item,account)


@app.get('/api/mobile/assets')
def assets(account=Depends(owner)):
    uid = account.removeprefix('firebase:')
    result = []
    for item in studio().records(account,'mobileCreations'):
        if item.get('kind') != '3D object': continue
        def media(field):
            path = item.get(field,'')
            return public_shape('gs://'+BUCKET+'/'+path,account) if path.startswith(f'users/{uid}/') else None
        result.append({'id':item['id'].removeprefix('model:'),'name':item.get('name','Untitled creation'),
                       'modelUrl':media('modelStoragePath'),'thumbUrl':media('previewStoragePath') or item.get('preview'),
                       'isExample':False})
    return {'owned':result,'examples':[]}


@app.post('/api/mobile/cloud-library/sync')
def sync(account=Depends(owner)):
    return {'synced':0,'storage':'firebase'}


@app.get('/api/mobile/wallet')
def wallet(account=Depends(owner)):
    return CloudBilling(studio().db).wallet(account.removeprefix('firebase:'))


class PurchaseClaim(BaseModel):
    productId: str = Field(min_length=1, max_length=150)
    transactionId: str = Field(min_length=1, max_length=150)


@app.post('/api/mobile/purchases/revenuecat')
def verify_purchase(body: PurchaseClaim, account=Depends(owner)):
    return CloudBilling(studio().db).sync(account.removeprefix('firebase:'), (body.productId, body.transactionId))


@app.post('/api/mobile/purchases/revenuecat/sync')
def sync_purchases(account=Depends(owner)):
    return CloudBilling(studio().db).sync(account.removeprefix('firebase:'))


@app.get('/api/mobile/bootstrap')
def bootstrap(account=Depends(owner)):
    engines=[dict(id=ident,label=label,available=model_ready(),ready=model_ready(),provider='api',
        multiView=True,multiViewDirections=['front','back','left'] if ident.startswith('hunyuan') else ['front','back','left','right'])
        for ident,label in cloud_model_provider.ENGINES.items()]
    return {'mode':'cloud','wallet':wallet(account),'products':[], 'engines':list(cloud_model_provider.ENGINES), 'engineCatalog':engines,
            'generationReady':generation_ready(),'modelGenerationReady':model_ready()}


class DeletionConfirmation(BaseModel):
    confirm: Literal[True]


@app.post('/api/mobile/account/delete', status_code=202)
def delete_account(body: DeletionConfirmation, claims=Depends(require_claims)):
    return request_deletion(studio().db, claims)


@app.post('/internal/account-deletions/{uid}')
def account_deletion_worker(uid: str, authorization: str = Header(default='')):
    verify_worker(authorization)
    return erase_account(studio(), uid)


@app.post('/internal/uploads/{uid}/{concept_id}')
def upload_cleanup_worker(uid: str, concept_id: str, authorization: str = Header(default='')):
    verify_worker(authorization)
    return CloudProjects(studio()).cleanup(uid, concept_id)


@app.post('/internal/model-jobs/{uid}/{job_id}')
def model_worker(uid: str, job_id: str, authorization: str = Header(default=''),
                 x_craft_queued_at: int | None = Header(default=None)):
    verify_worker(authorization)
    return CloudModelJobs(studio()).run(uid,job_id,x_craft_queued_at)


@app.post('/internal/model-outputs/{uid}/{job_id}')
def model_output_cleanup(uid: str, job_id: str, authorization: str = Header(default='')):
    verify_worker(authorization)
    return CloudModelJobs(studio()).cleanup(uid,job_id)


@app.post('/api/models/callback/{uid}/{job_id}/{token}')
async def model_callback(uid: str, job_id: str, token: str, request: Request):
    raw=bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw)>1024*1024: raise HTTPException(413,'Notification too large.')
    rid=await run_in_threadpool(cloud_model_provider.verify_callback,request.headers,bytes(raw))
    try: payload=json.loads(raw)
    except ValueError: raise HTTPException(422,'Invalid notification.') from None
    if not isinstance(payload,dict) or payload.get('request_id')!=rid or payload.get('status') not in ('OK','ERROR'):
        raise HTTPException(422,'Invalid notification.')
    try:
        await run_in_threadpool(CloudModelJobs(studio()).request_received,uid,job_id,rid,token,payload['status']=='ERROR')
    except HTTPException as exc:
        if exc.status_code!=403: raise
    return {'status':'received'}


@app.post('/api/billing/revenuecat/webhook')
def revenuecat_webhook(payload: dict, authorization: str = Header(default='')):
    return reconcile_webhook(studio().db, payload, authorization)


def community_viewer(authorization: str = Header(default='')):
    if not authorization: return None
    return owner(require_claims(authorization)).removeprefix('firebase:')


@app.get('/api/mobile/community/games')
def community_feed(category: Category = 'fun', offset: int = Query(default=0, ge=0, le=10000), uid=Depends(community_viewer)):
    return CloudCommunity(studio().db).feed(category, offset, uid)


@app.get('/api/mobile/community/mine')
def community_mine(account=Depends(owner)):
    return CloudCommunity(studio().db).mine(account.removeprefix('firebase:'))


@app.post('/api/mobile/community/check-link')
def community_check(body: GameLink, account=Depends(owner)):
    return CloudCommunity(studio().db).check_link(account.removeprefix('firebase:'), body.url)


@app.post('/api/mobile/community/games')
def community_submit(body: Submission, account=Depends(owner)):
    return CloudCommunity(studio().db).submit(account.removeprefix('firebase:'), body)


@app.get('/api/mobile/community/games/{ident}/play')
def community_play(ident: str, uid=Depends(community_viewer)):
    return CloudCommunity(studio().db).play(ident, uid)


@app.put('/api/mobile/community/games/{ident}/vote')
def community_vote(ident: str, body: Vote, account=Depends(owner)):
    return CloudCommunity(studio().db).vote(account.removeprefix('firebase:'), ident, body)


@app.delete('/api/mobile/community/games/{ident}')
def community_remove(ident: str, account=Depends(owner)):
    return CloudCommunity(studio().db).remove(account.removeprefix('firebase:'), ident)


@app.post('/api/mobile/community/games/{ident}/recheck')
def community_recheck(ident: str, account=Depends(owner)):
    return CloudCommunity(studio().db).recheck(account.removeprefix('firebase:'), ident)


@app.post('/api/mobile/community/games/{ident}/report')
def community_report(ident: str, body: Report, account=Depends(owner)):
    return CloudCommunity(studio().db).report(account.removeprefix('firebase:'), ident, body)


@app.post('/api/mobile/community/games/{ident}/block')
def community_block(ident: str, account=Depends(owner)):
    return CloudCommunity(studio().db).block(account.removeprefix('firebase:'), ident)


@app.get('/api/mobile/community/blocks')
def community_blocks(account=Depends(owner)):
    return CloudCommunity(studio().db).blocks(account.removeprefix('firebase:'))


@app.delete('/api/mobile/community/blocks/{ident}')
def community_unblock(ident: str, account=Depends(owner)):
    return CloudCommunity(studio().db).unblock(account.removeprefix('firebase:'), ident)


@app.api_route('/api/{path:path}',methods=['GET','POST','PUT','DELETE','PATCH'])
def unavailable(path: str, account=Depends(owner)):
    raise HTTPException(503,'This cloud feature is being prepared. No Tokens were charged.')
