"""Cloud-only studio API. No SQLite databases, laptop paths or local sessions.

Readiness reports whether the verified Gemini-to-3D cloud pipeline is enabled.
It is an operational signal, not an App Store review or device-QA status.
"""
from functools import lru_cache
import os
import json
from urllib.parse import quote
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException, Header, Form, File, UploadFile, Request, Query, Response
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
from .firebase_creations import CloudCreations, CreationRequest, RenameRequest, continue_to_model
from .firebase_animations import CloudAnimations, AnimationRequest
from . import cloud_animation_provider
from . import firebase_creations
import time
from .firebase_community import CloudCommunity, Submission, Vote, Report, GameLink, Category
from . import cloud_model_provider, pricing
from pydantic import BaseModel, Field
from typing import Literal, Optional
from .account_deletion import ensure_active, request_deletion, erase_account, verify_worker

app = FastAPI(title='3D Craft Cloud API')
app.add_middleware(CORSMiddleware, allow_origins=['https://3d-craft.web.app'], allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type'])

@lru_cache
def studio(): return FirebaseStudio()

import re

ROUTE_SCOPES = [
    # 1. Wallet
    (re.compile(r"^/api/v1/wallet$"), {"GET": "wallet:read"}),
    # 2. 3D Model reconstruction (MUST be matched before general concepts!)
    (re.compile(r"^/api/v1/concepts/[^/]+/model$"), {"POST": "models:write", "GET": "assets:read"}),
    # 3. Prompt planning & Chat
    (re.compile(r"^/api/v1/concepts/[^/]+/model-prompt$"), {"POST": "prompt:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/planning/prompt$"), {"POST": "prompt:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/planning/quote$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/planning/[^/]+$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/projects/[^/]+/chat$"), {"POST": "prompt:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/projects/[^/]+/references$"), {"POST": "prompt:write", "GET": "assets:read"}),
    # 4. Concepts creation & refinement
    (re.compile(r"^/api/v1/projects/[^/]+/concepts$"), {"POST": "concepts:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/concepts/[^/]+/refine$"), {"POST": "concepts:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/projects$"), {"POST": "concepts:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/projects/[^/]+$"), {"GET": "assets:read", "PATCH": "concepts:write", "DELETE": "assets:delete"}),
    (re.compile(r"^/api/v1/projects/[^/]+/archive$"), {"POST": "assets:delete"}),
    (re.compile(r"^/api/v1/projects/[^/]+/restore$"), {"POST": "concepts:write"}),
    (re.compile(r"^/api/v1/concepts/[^/]+/image$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/concepts/[^/]+$"), {"DELETE": "assets:delete"}),
    # Animated characters
    (re.compile(r"^/api/v1/animations/quote$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/concepts/[^/]+/animation$"), {"POST": "models:write", "GET": "assets:read"}),
    # One-step prompt-to-3D
    (re.compile(r"^/api/v1/creations/quote$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/creations$"), {"POST": "models:write"}),
    (re.compile(r"^/api/v1/creations/[^/]+$"), {"GET": "assets:read"}),
    # 5. Assets & Jobs & Readouts
    (re.compile(r"^/api/v1/assets/[^/]+/download$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets/[^/]+/archive$"), {"POST": "assets:delete"}),
    (re.compile(r"^/api/v1/assets/[^/]+/restore$"), {"POST": "models:write"}),
    (re.compile(r"^/api/v1/archive$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets/[^/]+$"), {"DELETE": "assets:delete"}),
    (re.compile(r"^/api/v1/jobs/[^/]+$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/jobs$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/pricing$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/image-models$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/openapi.json$"), {"GET": "assets:read"}),
]

def is_allowed_api_key_path(path: str) -> bool:
    norm_path = path.rstrip("/") if path != "/" else path
    return any(pattern.match(norm_path) for pattern, _ in ROUTE_SCOPES)

def required_scope_for_path(path: str, method: str) -> str:
    norm_path = path.rstrip("/") if path != "/" else path
    for pattern, methods in ROUTE_SCOPES:
        if pattern.match(norm_path):
            return methods.get(method.upper(), "assets:read")
    return "assets:read"

def owner(claims: dict = Depends(require_claims)) -> str:
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    return 'firebase:' + uid

def v1_owner(request: Request, authorization: str = Header(default='')) -> str:
    if authorization.startswith('Bearer craft_live_'):
        path = request.url.path
        if not is_allowed_api_key_path(path):
            raise HTTPException(403, "API keys are only accepted on /api/v1 pipeline endpoints. This endpoint requires account sign-in.")
        scope = required_scope_for_path(path, request.method)
        token = authorization[7:].strip()
        from .api_keys import verify_api_key
        uid, meta = verify_api_key(studio().db, token, scope)
        request.state.is_api_key = True
        request.state.api_key_meta = meta
        return 'firebase:' + uid

    claims = require_claims(authorization)
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    request.state.is_api_key = False
    return 'firebase:' + uid

# API keys bill the production wallet, so TestFlight testers cannot run paid
# generation through the API on free sandbox Tokens. Accounts listed in
# CRAFT_API_SANDBOX_UIDS instead follow their billing context like the app does
# (sandbox still requires CRAFT_REVENUECAT_SANDBOX=1).
V1_BILLING_NOTE = ('API keys spend Tokens from App Store purchases only. '
    'TestFlight and sandbox test Tokens stay in the app and cannot be used through the API.')

def v1_environment(account):
    allowed = {uid.strip() for uid in os.getenv('CRAFT_API_SANDBOX_UIDS', '').split(',') if uid.strip()}
    return None if account.removeprefix('firebase:') in allowed else 'PRODUCTION'

def v1_charge(account, create):
    try:
        return create()
    except HTTPException as exc:
        if exc.status_code == 402 and v1_environment(account) == 'PRODUCTION':
            raise HTTPException(402, f'{exc.detail} {V1_BILLING_NOTE}') from None
        raise

def user_only_claims(
    authorization: str = Header(default=''),
    claims: dict = Depends(require_claims),
) -> dict:
    if authorization.startswith('Bearer craft_live_'):
        raise HTTPException(403, "API keys cannot manage API keys or perform account administration.")
    if not authorization.startswith('Bearer ') or not authorization[7:].strip():
        raise HTTPException(401, "Sign in to manage API keys.")
    from firebase_admin import auth
    from .identity import firebase_app
    try:
        verified = auth.verify_id_token(authorization[7:].strip(), app=firebase_app(), check_revoked=True)
        uid = verified.get('uid') or verified.get('sub')
        if not uid or uid != (claims.get('uid') or claims.get('sub')):
            raise HTTPException(401, "Your sign-in could not be verified.")
        user = auth.get_user(uid, app=firebase_app())
        if user.disabled:
            raise HTTPException(401, "Your account has been disabled.")
    except auth.RevokedIdTokenError:
        raise HTTPException(401, "Your sign-in token has been revoked. Please sign in again.") from None
    except auth.UserDisabledError:
        raise HTTPException(401, "Your account has been disabled.") from None
    except auth.UserNotFoundError:
        raise HTTPException(401, "Your account no longer exists.") from None
    except auth.InvalidIdTokenError:
        raise HTTPException(401, "Your sign-in could not be verified. Please sign in again.") from None
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Account verification is temporarily unavailable. Please try again.") from None
    ensure_active(studio().db, uid)
    return verified


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
def mobile_generate_model(concept_id: str, body: ModelRequest, account=Depends(owner)):
    if not model_ready(): raise HTTPException(503,'Cloud 3D generation is temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudModelJobs(studio()).create(account,concept_id,body),account)


@app.post('/api/v1/concepts/{concept_id}/model')
def v1_generate_model(concept_id: str, body: ModelRequest, account=Depends(v1_owner)):
    if not model_ready(): raise HTTPException(503,'Cloud 3D generation is temporarily unavailable. No Tokens were charged.')
    return public_shape(v1_charge(account, lambda: CloudModelJobs(studio()).create(account,concept_id,body,environment=v1_environment(account))),account)


def animations_ready():
    return os.getenv('CRAFT_ANIMATION_JOBS_ENABLED') == '1' and bool(os.getenv('FAL_KEY'))


@app.get('/api/mobile/animations/quote')
def mobile_animation_quote(resolution: Literal['480p', '720p', '768p'] = '480p',
                           duration: Literal['4', '5', '6'] = '4',
                           aspect: Literal['1:1', '16:9', '9:16'] = '1:1',
                           model: Literal['seedance-2.5', 'minimax-h3'] = 'seedance-2.5',
                           account=Depends(owner)):
    quote = pricing.animation_quote(resolution, int(duration), aspect, model)
    return {**quote, 'maxTokens': quote['usageWithServiceFee']['credits'], 'available': animations_ready()}


@app.get('/api/v1/animations/quote')
def v1_animation_quote(resolution: Literal['480p', '720p', '768p'] = '480p',
                       duration: Literal['4', '5', '6'] = '4',
                       aspect: Literal['1:1', '16:9', '9:16'] = '1:1',
                       model: Literal['seedance-2.5', 'minimax-h3'] = 'seedance-2.5',
                       account=Depends(v1_owner)):
    quote = pricing.animation_quote(resolution, int(duration), aspect, model)
    return {**quote, 'maxTokens': quote['usageWithServiceFee']['credits'], 'available': animations_ready()}


@app.post('/api/mobile/concepts/{concept_id}/animation')
def mobile_animate_concept(concept_id: str, body: AnimationRequest, account=Depends(owner)):
    if not animations_ready(): raise HTTPException(503,'Character animation is temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudAnimations(studio()).create(account,concept_id,body),account)


@app.post('/api/v1/concepts/{concept_id}/animation')
def v1_animate_concept(concept_id: str, body: AnimationRequest, account=Depends(v1_owner)):
    if not animations_ready(): raise HTTPException(503,'Character animation is temporarily unavailable. No Tokens were charged.')
    return public_shape(v1_charge(account, lambda: CloudAnimations(studio()).create(account,concept_id,body,environment=v1_environment(account))),account)


def planning_ready():
    return os.getenv('CRAFT_PLANNING_ENABLED') == '1'


def concepts_ready():
    return planning_ready() and os.getenv('CRAFT_CONCEPT_JOBS_ENABLED') == '1'


def generation_ready():
    return concepts_ready() and model_ready()


@app.get('/api/mobile/image-models')
def mobile_image_models(account=Depends(owner)):
    now=time.time()
    return {'defaultModel':cloud_concept_provider.MODEL,'expiresAt':cloud_concept_provider.quote(now)['expiresAt'],
        'maxTokensByCount':{str(n):cloud_concept_provider.quote(now,n)['maxTokens'] for n in range(1,5)},
        'models':[dict(id=cloud_concept_provider.MODEL,name='Gemini 3 Pro Image · Nano Banana Pro',provider='google',
            quality='Pro',imageSize='2K',available=concepts_ready(),unavailableReason=None if concepts_ready() else 'Cloud concepts are temporarily unavailable.')]}


@app.get('/api/v1/image-models')
def v1_image_models(account=Depends(v1_owner)):
    now=time.time()
    return {'defaultModel':cloud_concept_provider.MODEL,'expiresAt':cloud_concept_provider.quote(now)['expiresAt'],
        'maxTokensByCount':{str(n):cloud_concept_provider.quote(now,n)['maxTokens'] for n in range(1,5)},
        'models':[dict(id=cloud_concept_provider.MODEL,name='Gemini 3 Pro Image · Nano Banana Pro',provider='google',
            quality='Pro',imageSize='2K',available=concepts_ready(),unavailableReason=None if concepts_ready() else 'Cloud concepts are temporarily unavailable.')]}


@app.post('/api/mobile/projects/{project_id}/concepts')
def mobile_generate_concepts(project_id:str,body:ConceptRequest,account=Depends(owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudConcepts(studio()).create(account,project_id,body),account)


@app.post('/api/v1/projects/{project_id}/concepts')
def v1_generate_concepts(project_id:str,body:ConceptRequest,account=Depends(v1_owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    return public_shape(v1_charge(account, lambda: CloudConcepts(studio()).create(account,project_id,body,environment=v1_environment(account))),account)


@app.post('/api/mobile/concepts/{concept_id}/refine')
def mobile_refine_concept(concept_id:str,body:ConceptRequest,account=Depends(owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    uid=account.removeprefix('firebase:');service=CloudConcepts(studio())
    concept=service.projects.ref(uid,'studioConcepts',concept_id).get().to_dict()
    if not concept or concept.get('ownerId')!=uid:raise HTTPException(404,'Image not found in this account.')
    return public_shape(service.create(account,concept['projectId'],body,concept_id),account)


@app.post('/api/v1/concepts/{concept_id}/refine')
def v1_refine_concept(concept_id:str,body:ConceptRequest,account=Depends(v1_owner)):
    if not concepts_ready():raise HTTPException(503,'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    uid=account.removeprefix('firebase:');service=CloudConcepts(studio())
    concept=service.projects.ref(uid,'studioConcepts',concept_id).get().to_dict()
    if not concept or concept.get('ownerId')!=uid:raise HTTPException(404,'Image not found in this account.')
    return public_shape(v1_charge(account, lambda: service.create(account,concept['projectId'],body,concept_id,environment=v1_environment(account))),account)


@app.post('/internal/concepts/{uid}/{job_id}')
def concept_worker(uid:str,job_id:str,authorization:str=Header(default=''),x_craft_queued_at:int|None=Header(default=None)):
    verify_worker(authorization)
    result = CloudConcepts(studio()).run(uid,job_id,x_craft_queued_at)
    continue_to_model(studio(), uid, job_id)
    return result


@app.get('/api/mobile/planning/quote')
def mobile_planning_quote(kind: Literal['prompt','chat']='prompt', account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable.')
    return cloud_planner_provider.quote(time.time(),kind)


@app.get('/api/v1/planning/quote')
def v1_planning_quote(kind: Literal['prompt','chat']='prompt', account=Depends(v1_owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable.')
    return cloud_planner_provider.quote(time.time(),kind)


@app.post('/api/mobile/projects/{project_id}/chat')
def mobile_send_chat(project_id: str, body: ChatRequest, account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503,'Cloud creative chat is temporarily unavailable. No Tokens were charged.')
    return CloudPlanning(studio()).create_chat(account,project_id,body)


@app.post('/api/v1/projects/{project_id}/chat')
def v1_send_chat(project_id: str, body: ChatRequest, account=Depends(v1_owner)):
    if not planning_ready(): raise HTTPException(503,'Cloud creative chat is temporarily unavailable. No Tokens were charged.')
    return v1_charge(account, lambda: CloudPlanning(studio()).create_chat(account,project_id,body,environment=v1_environment(account)))


@app.post('/api/mobile/concepts/{concept_id}/model-prompt')
def mobile_improve_prompt(concept_id: str, body: PromptRequest, account=Depends(owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable. No Tokens were charged.')
    return CloudPlanning(studio()).create(account, concept_id, body)


@app.post('/api/v1/concepts/{concept_id}/model-prompt')
def v1_improve_prompt(concept_id: str, body: PromptRequest, account=Depends(v1_owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable. No Tokens were charged.')
    return v1_charge(account, lambda: CloudPlanning(studio()).create(account, concept_id, body, environment=v1_environment(account)))


@app.post('/api/v1/planning/prompt')
def v1_standalone_prompt(body: PromptRequest, account=Depends(v1_owner)):
    if not planning_ready(): raise HTTPException(503, 'Cloud prompt improvement is temporarily unavailable. No Tokens were charged.')
    return v1_charge(account, lambda: CloudPlanning(studio()).create(account, 'standalone', body, environment=v1_environment(account)))


@app.get('/api/mobile/planning/{job_id}')
def mobile_planning_result(job_id: str, account=Depends(owner)):
    return CloudPlanning(studio()).get(account, job_id)


@app.get('/api/v1/planning/{job_id}')
def v1_planning_result(job_id: str, account=Depends(v1_owner)):
    return CloudPlanning(studio()).get(account, job_id)


@app.post('/internal/planning/{uid}/{job_id}')
def planning_worker(uid: str, job_id: str, authorization: str = Header(default=''),
                    x_craft_queued_at: int | None = Header(default=None)):
    verify_worker(authorization)
    return CloudPlanning(studio()).run(uid, job_id, x_craft_queued_at)


@app.get('/api/mobile/pricing')
def mobile_provider_pricing(account=Depends(owner)):
    return pricing.catalog()


@app.get('/api/v1/pricing')
def v1_provider_pricing(account=Depends(v1_owner)):
    return pricing.catalog()


@app.get('/api/mobile/projects')
def mobile_projects(account=Depends(owner), archived: bool = False):
    CloudCreations(studio()).purge_expired_archives(account)
    records = studio().records(account,'studioProjects')
    concepts = studio().records(account,'studioConcepts')
    turns = studio().records(account,'studioConversations')
    filtered = []
    for project in records:
        archived_at = firebase_creations.seconds(project.get('archivedAt'))
        if (archived_at is not None) != archived: continue
        project['concepts'] = sorted([c for c in concepts if c.get('projectId') == project['id']],key=lambda c:c.get('createdAt',0))
        project['conversation'] = sorted([t for t in turns if t.get('projectId') == project['id']],key=lambda t:t.get('createdAt',0))
        project['archivedAt'] = archived_at
        project['isArchived'] = archived_at is not None
        project['daysRemaining'] = max(0, 30 - int((time.time() - archived_at) / 86400)) if archived_at else None
        filtered.append(project)
    return public_shape(sorted(filtered,key=lambda p:p.get('createdAt',0),reverse=True),account)


@app.get('/api/v1/projects')
def v1_projects(account=Depends(v1_owner)):
    records = studio().records(account,'studioProjects')
    concepts = studio().records(account,'studioConcepts')
    turns = studio().records(account,'studioConversations')
    for project in records:
        project['concepts'] = sorted([c for c in concepts if c.get('projectId') == project['id']],key=lambda c:c.get('createdAt',0))
        project['conversation'] = sorted([t for t in turns if t.get('projectId') == project['id']],key=lambda t:t.get('createdAt',0))
    return public_shape(sorted(records,key=lambda p:p.get('createdAt',0),reverse=True),account)


@app.post('/api/mobile/projects')
async def mobile_create_project(prompt: str = Form(default=''), name: str = Form(default='Untitled idea'),
        style: str = Form(default='Stylized'), image: UploadFile | None = File(default=None),
        clientId: str | None = Form(default=None), account=Depends(owner)):
    raw = await image.read(MAX_BYTES + 1) if image else None
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        prompt=prompt, name=name, style=style, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.post('/api/v1/projects')
async def v1_create_project(prompt: str = Form(default=''), name: str = Form(default='Untitled idea'),
        style: str = Form(default='Stylized'), image: UploadFile | None = File(default=None),
        clientId: str | None = Form(default=None), account=Depends(v1_owner)):
    raw = await image.read(MAX_BYTES + 1) if image else None
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        prompt=prompt, name=name, style=style, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.get('/api/v1/projects/{project_id}')
def v1_project(project_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).project(account, project_id)


@app.patch('/api/v1/projects/{project_id}')
def v1_rename_project(project_id: str, body: RenameRequest, account=Depends(v1_owner)):
    return CloudCreations(studio()).rename(account, project_id, body.name)


@app.delete('/api/mobile/projects/{project_id}')
@app.delete('/api/v1/projects/{project_id}')
def delete_project_endpoint(project_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).delete_project(account, project_id)


@app.post('/api/mobile/projects/{project_id}/archive')
@app.post('/api/v1/projects/{project_id}/archive')
def archive_project_endpoint(project_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).archive_project(account, project_id)


@app.post('/api/mobile/projects/{project_id}/restore')
@app.post('/api/v1/projects/{project_id}/restore')
def restore_project_endpoint(project_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).restore_project(account, project_id)


@app.get('/api/v1/concepts/{concept_id}/image')
def v1_concept_image(concept_id: str, account=Depends(v1_owner)):
    content = CloudCreations(studio()).concept_image(account, concept_id)
    return Response(content=content, media_type='image/jpeg', headers={
        'Content-Disposition': f'attachment; filename="{concept_id}.jpg"', 'Cache-Control': 'private, max-age=3600'})


@app.delete('/api/v1/concepts/{concept_id}')
def v1_delete_concept(concept_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).delete_concept(account, concept_id)


@app.get('/api/v1/creations/quote')
def v1_creation_quote(engine: firebase_creations.Engine = 'rodin', effort: firebase_creations.Effort = 'high',
                      account=Depends(v1_owner)):
    return firebase_creations.quote(engine, effort)


@app.post('/api/v1/creations')
def v1_create(body: CreationRequest, account=Depends(v1_owner)):
    if not generation_ready():
        raise HTTPException(503, 'Cloud creation is temporarily unavailable. No Tokens were charged.')
    return v1_charge(account, lambda: CloudCreations(studio()).create(account, body, environment=v1_environment(account)))


@app.get('/api/v1/creations/{creation_id}')
def v1_creation(creation_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).status(account, creation_id)


@app.post('/api/mobile/projects/{project_id}/references')
async def mobile_add_reference(project_id: str, image: UploadFile = File(...),
        clientId: str | None = Form(default=None), account=Depends(owner)):
    raw = await image.read(MAX_BYTES + 1)
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        project_id=project_id, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.post('/api/v1/projects/{project_id}/references')
async def v1_add_reference(project_id: str, image: UploadFile = File(...),
        clientId: str | None = Form(default=None), account=Depends(v1_owner)):
    raw = await image.read(MAX_BYTES + 1)
    result = await run_in_threadpool(CloudProjects(studio()).create, account,
        project_id=project_id, raw=raw, client_id=clientId)
    return public_shape(result, account)


@app.get('/api/mobile/jobs')
def mobile_jobs(account=Depends(owner)):
    return public_shape(sorted(studio().records(account,'studioJobs'),key=lambda j:j.get('createdAt',0),reverse=True),account)


@app.get('/api/v1/jobs')
def v1_jobs(account=Depends(v1_owner)):
    return public_shape(sorted(studio().records(account,'studioJobs'),key=lambda j:j.get('createdAt',0),reverse=True),account)


@app.get('/api/mobile/jobs/{ident}')
def mobile_job(ident: str, account=Depends(owner)):
    item = next((j for j in studio().records(account,'studioJobs') if j['id']==ident),None)
    if item is None: raise HTTPException(404,'Creation not found in your account.')
    return public_shape(item,account)


@app.get('/api/v1/jobs/{ident}')
def v1_job(ident: str, account=Depends(v1_owner)):
    item = next((j for j in studio().records(account,'studioJobs') if j['id']==ident),None)
    if item is None: raise HTTPException(404,'Creation not found in your account.')
    return public_shape(item,account)


@app.get('/api/mobile/assets')
def mobile_assets(account=Depends(owner), archived: bool = False):
    uid = account.removeprefix('firebase:')
    CloudCreations(studio()).purge_expired_archives(account)
    result = []
    for item in studio().records(account,'mobileCreations'):
        kind = item.get('kind')
        if kind not in ('3D object','Animated character', 'Concept image'): continue
        archived_at = firebase_creations.seconds(item.get('archivedAt'))
        if (archived_at is not None) != archived: continue
        animated = kind == 'Animated character'
        is_concept = kind == 'Concept image'
        clean_id = item['id'].removeprefix('animation:' if animated else ('concept:' if is_concept else 'model:'))
        def media(field):
            path = item.get(field,'')
            return public_shape('gs://'+BUCKET+'/'+path,account) if path.startswith(f'users/{uid}/') else None
        entry = {'id':clean_id,
                 'name':item.get('name','Untitled creation'),'creationKind':kind,
                 'kind': 'animation' if animated else ('concept' if is_concept else 'model'),
                 'modelUrl':media('modelStoragePath') if not animated and not is_concept else None,
                 'animationUrl':media('animationStoragePath') if animated else None,
                 'videoUrl':media('animationStoragePath') if animated else None,
                 'thumbUrl':media('previewStoragePath') or item.get('preview'),
                 'sourceImageUrl':media('previewStoragePath') if is_concept else None,
                 'projectId':item.get('projectId'),
                 'conceptIds':item.get('conceptIds') or [],
                 'prompt':item.get('prompt') or '',
                 'createdAt':firebase_creations.seconds(item.get('createdAt')),
                 'archivedAt':archived_at,
                 'daysRemaining': max(0, 30 - int((time.time() - archived_at) / 86400)) if archived_at else None,
                 'isArchived': archived_at is not None,
                 'isExample':False}
        result.append(entry)
    result.sort(key=lambda a: a['createdAt'] or 0, reverse=True)
    return {'owned':result,'examples':[]}


@app.get('/api/v1/assets')
def v1_assets(account=Depends(v1_owner), archived: bool = False):
    uid = account.removeprefix('firebase:')
    CloudCreations(studio()).purge_expired_archives(account)
    result = []
    for item in studio().records(account,'mobileCreations'):
        kind = item.get('kind')
        if kind not in ('3D object','Animated character', 'Concept image'): continue
        archived_at = firebase_creations.seconds(item.get('archivedAt'))
        if (archived_at is not None) != archived: continue
        animated = kind == 'Animated character'
        is_concept = kind == 'Concept image'
        clean_id = item['id'].removeprefix('animation:' if animated else ('concept:' if is_concept else 'model:'))
        def media(field):
            path = item.get(field,'')
            return public_shape('gs://'+BUCKET+'/'+path,account) if path.startswith(f'users/{uid}/') else None
        result.append({'id':clean_id,'name':item.get('name','Untitled creation'),'creationKind':kind,
                       'kind': 'animation' if animated else ('concept' if is_concept else 'model'),
                       'animationUrl':media('animationStoragePath') if animated else None,
                       'videoUrl':media('animationStoragePath') if animated else None,
                       'modelUrl':media('modelStoragePath') if not animated and not is_concept else None,
                       'thumbUrl':media('previewStoragePath') or item.get('preview'),
                       'sourceImageUrl':media('previewStoragePath') if is_concept else None,
                       'projectId':item.get('projectId'),'conceptIds':item.get('conceptIds') or [],
                       'prompt':item.get('prompt') or '',
                       'createdAt':firebase_creations.seconds(item.get('createdAt')),
                       'archivedAt':archived_at,
                       'daysRemaining': max(0, 30 - int((time.time() - archived_at) / 86400)) if archived_at else None,
                       'isArchived': archived_at is not None,
                       'downloadUrl':f'/api/v1/assets/{clean_id}/download' + ('?kind=video' if animated else ('?kind=preview' if is_concept else '')),
                       'previewDownloadUrl':f'/api/v1/assets/{clean_id}/download?kind=preview',
                       'isExample':False})
    # Newest first, so an agent's latest creation is always the first entry.
    result.sort(key=lambda a: a['createdAt'] or 0, reverse=True)
    return {'owned':result,'examples':[]}


@app.get('/api/mobile/archive')
def mobile_archive(account=Depends(owner)):
    return mobile_assets(account, archived=True)


@app.get('/api/v1/archive')
def v1_archive(account=Depends(v1_owner)):
    return v1_assets(account, archived=True)


@app.post('/api/mobile/assets/{asset_id}/archive')
@app.post('/api/v1/assets/{asset_id}/archive')
def v1_archive_asset(asset_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).archive_asset(account, asset_id)


@app.post('/api/mobile/assets/{asset_id}/restore')
@app.post('/api/v1/assets/{asset_id}/restore')
def v1_restore_asset(asset_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).restore_asset(account, asset_id)


@app.delete('/api/mobile/assets/{asset_id}')
@app.delete('/api/v1/assets/{asset_id}')
def v1_delete_asset(asset_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).delete_asset(account, asset_id)


@app.get('/api/v1/assets/{asset_id}/download')
def v1_download_asset(asset_id: str, kind: Literal['model','preview','video','animation'] = 'model', account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    clean_id = asset_id.removeprefix('model:').removeprefix('animation:').removeprefix('concept:')
    creations = studio().db.collection('users').document(uid).collection('mobileCreations')
    doc = None
    for candidate in ('model:' + clean_id, 'animation:' + clean_id, 'concept:' + clean_id, clean_id):
        doc_ref = creations.document(candidate)
        doc = doc_ref.get()
        if doc.exists: break
    if doc is None or not doc.exists:
        raise HTTPException(404, "Asset not found in your account.")
    item = doc.to_dict() or {}
    if item.get('ownerId') != uid:
        raise HTTPException(403, "Access denied to requested asset.")
    field = 'previewStoragePath' if kind == 'preview' else \
        ('animationStoragePath' if (kind in ('video', 'animation') or item.get('kind') == 'Animated character') else 'modelStoragePath')
    path = item.get(field) or ''
    if not path or not path.startswith(f'users/{uid}/') or '..' in path:
        raise HTTPException(404, f"Asset {kind} file not found.")
    suffix = Path(path).suffix.lower()
    if suffix not in ('.glb', '.gltf', '.bin', '.usdz', '.obj', '.mtl', '.png', '.jpg', '.jpeg', '.webp', '.mp4'):
        raise HTTPException(403, "File type not permitted for download.")
    try:
        blob = studio().bucket.blob(path)
        content = blob.download_as_bytes()
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, "Failed to download asset file from storage.") from exc
    media_types = {
        '.glb': 'model/gltf-binary',
        '.mp4': 'video/mp4',
        '.usdz': 'model/vnd.usdz+zip',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.webp': 'image/webp',
    }
    media_type = media_types.get(suffix, 'application/octet-stream')
    filename = f"{clean_id}{suffix}"
    return Response(
        content=content,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Cache-Control": "private, max-age=3600",
        },
    )


@app.post('/api/mobile/cloud-library/sync')
def sync(account=Depends(owner)):
    return {'synced':0,'storage':'firebase'}


class LiveActivityBody(BaseModel):
    jobId: str = Field(min_length=3, max_length=120)
    token: str = Field(min_length=32, max_length=200)
    # Development builds register sandbox tokens; TestFlight and the App Store
    # register production ones. Apple serves them from different hosts.
    environment: Literal['sandbox', 'production'] = 'production'


@app.post('/api/mobile/live-activity')
def register_live_activity(body: LiveActivityBody, account=Depends(owner)):
    from . import live_activity
    return live_activity.register(studio().db, account.removeprefix('firebase:'),
                                  body.jobId, body.token, body.environment)


@app.get('/api/mobile/wallet')
def wallet(account=Depends(owner)):
    return CloudBilling(studio().db).wallet(account.removeprefix('firebase:'))


@app.get('/api/v1/wallet')
def v1_wallet(account=Depends(v1_owner)):
    data = CloudBilling(studio().db).wallet(account.removeprefix('firebase:'), environment=v1_environment(account))
    sandbox = data.get('environment') == 'SANDBOX'
    return {**data, 'note': 'This account is allowed to spend TestFlight test Tokens through the API.' if sandbox else V1_BILLING_NOTE}


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


class CreateApiKeyBody(BaseModel):
    name: str = Field(default='API Key', min_length=1, max_length=64)
    scopes: list[str] = Field(default=['*'])
    expiresInDays: int | None = Field(default=None, ge=1, le=365)


@app.post('/api/keys')
def create_key(body: CreateApiKeyBody, claims=Depends(user_only_claims)):
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    from .api_keys import create_api_key
    return create_api_key(studio().db, uid, body.name, body.scopes, body.expiresInDays)


@app.get('/api/keys')
def list_keys(claims=Depends(user_only_claims)):
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    from .api_keys import list_api_keys
    return {'keys': list_api_keys(studio().db, uid)}


@app.delete('/api/keys/{key_id}')
@app.post('/api/keys/{key_id}/revoke')
def revoke_key(key_id: str, claims=Depends(user_only_claims)):
    uid = claims.get('uid') or claims['sub']
    ensure_active(studio().db, uid)
    from .api_keys import revoke_api_key
    return revoke_api_key(studio().db, uid, key_id)


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


@app.post('/internal/animation-jobs/{uid}/{job_id}')
def animation_worker(uid: str, job_id: str, authorization: str = Header(default=''),
                     x_craft_queued_at: int | None = Header(default=None)):
    verify_worker(authorization)
    return CloudAnimations(studio()).run(uid,job_id,x_craft_queued_at)


@app.post('/api/animations/callback/{uid}/{job_id}/{token}')
async def animation_callback(uid: str, job_id: str, token: str, request: Request):
    raw=bytearray()
    async for chunk in request.stream():
        raw.extend(chunk)
        if len(raw)>1024*1024: raise HTTPException(413,'Notification too large.')
    rid=await run_in_threadpool(cloud_animation_provider.verify_callback,request.headers,bytes(raw))
    try: payload=json.loads(raw)
    except ValueError: raise HTTPException(422,'Invalid notification.') from None
    if not isinstance(payload,dict) or payload.get('request_id')!=rid or payload.get('status') not in ('OK','ERROR'):
        raise HTTPException(422,'Invalid notification.')
    try:
        await run_in_threadpool(CloudAnimations(studio()).request_received,uid,job_id,rid,token,payload['status']=='ERROR')
    except HTTPException as exc:
        if exc.status_code!=403: raise
    return {'status':'received'}


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


@app.get('/api/v1/openapi.json')
def openapi_spec():
    from .openapi_v1 import get_openapi_v1_spec
    return get_openapi_v1_spec()


@app.api_route('/api/{path:path}',methods=['GET','POST','PUT','DELETE','PATCH'])
def unavailable(path: str, account=Depends(owner)):
    raise HTTPException(503,'This cloud feature is being prepared. No Tokens were charged.')
