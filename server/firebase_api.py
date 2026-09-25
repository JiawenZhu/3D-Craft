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
from .identity import require_claims, firebase_app
from .firebase_studio import FirebaseStudio, BUCKET
from .firebase_billing import CloudBilling
from .firebase_webhooks import reconcile_webhook
from .firebase_projects import CloudProjects, MAX_BYTES
from .firebase_model_jobs import CloudModelJobs, ModelRequest
from .firebase_planning import CloudPlanning, PromptRequest, ChatRequest
from . import cloud_planner_provider, cloud_concept_provider
from .firebase_concepts import CloudConcepts, ConceptRequest
from .firebase_creations import CloudCreations, CreationRequest, RenameRequest, continue_to_model, continue_to_animation
from .firebase_animations import CloudAnimations, AnimationRequest
from . import cloud_animation_provider
from . import firebase_creations
import time
from .firebase_community import CloudCommunity, Submission, Vote, Report, GameLink, Category
from . import cloud_model_provider, atlas_model_provider, pricing
from pydantic import BaseModel, Field
from typing import Literal, Optional
from .account_deletion import ensure_active, request_deletion, erase_account, verify_worker

app = FastAPI(title='3D Craft Cloud API')
app.add_middleware(CORSMiddleware, allow_origins=['https://3d-craft.web.app'], allow_methods=['GET','POST','PUT','PATCH','DELETE'], allow_headers=['Authorization','Content-Type'])

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
    # Profile management
    (re.compile(r"^/api/v1/profile$"), {"GET": "profile:read", "PATCH": "profile:write"}),
    # Direct animations
    (re.compile(r"^/api/v1/animations/quote$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/animations$"), {"POST": "animations:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/animations/[^/]+$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/animations/[^/]+/download$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/concepts/[^/]+/animation$"), {"POST": "animations:write", "GET": "assets:read"}),
    # Direct images
    (re.compile(r"^/api/v1/images$"), {"POST": "concepts:write", "GET": "assets:read"}),
    (re.compile(r"^/api/v1/images/[^/]+$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/images/[^/]+/download$"), {"GET": "assets:read"}),
    # One-step prompt-to-3D
    (re.compile(r"^/api/v1/creations/quote$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/creations$"), {"POST": "models:write"}),
    (re.compile(r"^/api/v1/creations/[^/]+$"), {"GET": "assets:read"}),
    # Favorites
    (re.compile(r"^/api/v1/favorites$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets/[^/]+/favorite$"), {"POST": "models:write", "DELETE": "models:write"}),
    # Prompt enhancement
    (re.compile(r"^/api/v1/prompts/enhance$"), {"POST": "prompt:write"}),
    # Community
    (re.compile(r"^/api/v1/community/games$"), {"GET": "assets:read"}),
    # 5. Assets & Jobs & Readouts
    (re.compile(r"^/api/v1/assets/[^/]+/download$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets/[^/]+/archive$"), {"POST": "assets:delete"}),
    (re.compile(r"^/api/v1/assets/[^/]+/restore$"), {"POST": "models:write"}),
    (re.compile(r"^/api/v1/archive$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/assets/[^/]+$"), {"GET": "assets:read", "PATCH": "models:write", "DELETE": "assets:delete"}),
    (re.compile(r"^/api/v1/jobs/[^/]+$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/jobs$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/pricing$"), {"GET": "assets:read"}),
    (re.compile(r"^/api/v1/models$"), {"GET": "assets:read"}),
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
    return os.getenv('CRAFT_MODEL_JOBS_ENABLED') == '1' and (bool(os.getenv('ATLAS_API_KEY')) or bool(os.getenv('FAL_KEY')))


def model_engine_ready(engine):
    key = 'ATLAS_API_KEY' if atlas_model_provider.is_atlas_engine(engine) else 'FAL_KEY'
    return os.getenv('CRAFT_MODEL_JOBS_ENABLED') == '1' and bool(os.getenv(key))


@app.post('/api/mobile/concepts/{concept_id}/model')
def mobile_generate_model(concept_id: str, body: ModelRequest, account=Depends(owner)):
    if not model_engine_ready(body.engine): raise HTTPException(503,'Cloud 3D generation is temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudModelJobs(studio()).create(account,concept_id,body),account)


@app.post('/api/v1/concepts/{concept_id}/model')
def v1_generate_model(concept_id: str, body: ModelRequest, account=Depends(v1_owner)):
    if not model_engine_ready(body.engine): raise HTTPException(503,'Cloud 3D generation is temporarily unavailable. No Tokens were charged.')
    return public_shape(v1_charge(account, lambda: CloudModelJobs(studio()).create(account,concept_id,body,environment=v1_environment(account))),account)


def animations_ready():
    return os.getenv('CRAFT_ANIMATION_JOBS_ENABLED') == '1' and (bool(os.getenv('FAL_KEY')) or bool(os.getenv('ATLAS_API_KEY')))


def animation_model_ready(model):
    if os.getenv('CRAFT_ANIMATION_JOBS_ENABLED') != '1':
        return False
    if model.startswith('atlas-'):
        return bool(os.getenv('ATLAS_API_KEY'))
    return bool(os.getenv('FAL_KEY'))


@app.get('/api/mobile/animations/quote')
def mobile_animation_quote(resolution: Literal['480p', '720p', '768p', '2K'] = '480p',
                           duration: Literal['4', '5', '6'] = '4',
                           aspect: Literal['1:1', '16:9', '9:16'] = '1:1',
                           model: Literal['seedance-2.5', 'minimax-h3', 'atlas-seedance-2.0-mini',
                                          'atlas-seedance-2.0', 'atlas-seedance-2.5',
                                          'atlas-minimax-h3', 'atlas-wan-3.0-prime'] = 'seedance-2.5',
                           account=Depends(owner)):
    quote = pricing.animation_quote(resolution, int(duration), aspect, model)
    return {**quote, 'maxTokens': quote['usageWithServiceFee']['credits'], 'available': animation_model_ready(model)}


@app.get('/api/v1/animations/quote')
def v1_animation_quote(resolution: Literal['480p', '720p', '768p', '2K'] = '480p',
                       duration: Literal['4', '5', '6'] = '4',
                       aspect: Literal['1:1', '16:9', '9:16'] = '1:1',
                       model: Literal['seedance-2.5', 'minimax-h3', 'atlas-seedance-2.0-mini',
                                      'atlas-seedance-2.0', 'atlas-seedance-2.5',
                                      'atlas-minimax-h3', 'atlas-wan-3.0-prime'] = 'seedance-2.5',
                       account=Depends(v1_owner)):
    quote = pricing.animation_quote(resolution, int(duration), aspect, model)
    return {**quote, 'maxTokens': quote['usageWithServiceFee']['credits'], 'available': animation_model_ready(model)}


@app.post('/api/mobile/concepts/{concept_id}/animation')
def mobile_animate_concept(concept_id: str, body: AnimationRequest, account=Depends(owner)):
    if not animation_model_ready(body.model): raise HTTPException(503,'Character animation is temporarily unavailable. No Tokens were charged.')
    return public_shape(CloudAnimations(studio()).create(account,concept_id,body),account)


@app.post('/api/v1/concepts/{concept_id}/animation')
def v1_animate_concept(concept_id: str, body: AnimationRequest, account=Depends(v1_owner)):
    if not animation_model_ready(body.model): raise HTTPException(503,'Character animation is temporarily unavailable. No Tokens were charged.')
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
    continue_to_animation(studio(), uid, job_id)
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


@app.get('/api/v1/models')
def v1_models(account=Depends(v1_owner)):
    from typing import get_args
    catalog = pricing.catalog()['models']
    engines = get_args(ModelRequest.model_fields['engine'].annotation)
    animations = get_args(AnimationRequest.model_fields['model'].annotation)
    video_catalog_keys = {'seedance-2.5': 'seedance-2.5-i2v', 'minimax-h3': 'minimax-h3-i2v'}
    return {
        'imageTo3D': [dict(id=engine, name=catalog[engine]['name'],
                           provider='Atlas' if atlas_model_provider.is_atlas_engine(engine) else 'fal',
                           available=model_engine_ready(engine),
                           providerUsd=catalog[engine].get('unitUsd'),
                           quoteUrl=f'/api/v1/creations/quote?engine={engine}')
                      for engine in engines],
        'video': [dict(id=model, name=catalog[video_catalog_keys.get(model, model)]['name'],
                       provider='Atlas' if model.startswith('atlas-') else 'fal',
                       available=animation_model_ready(model),
                       resolutions=list(pricing.ATLAS_ANIMATION_RATES[model]) if model.startswith('atlas-') else
                       (['480p', '768p'] if model == 'minimax-h3' else ['480p', '720p']),
                       quoteUrl=f'/api/v1/animations/quote?model={model}')
                  for model in animations],
    }


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
    if not concepts_ready() or not model_engine_ready(body.engine):
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


def v1_asset_entry(item, account):
    uid = account.removeprefix('firebase:')
    kind = item.get('kind')
    archived_at = firebase_creations.seconds(item.get('archivedAt'))
    animated = kind == 'Animated character'
    is_concept = kind == 'Concept image'
    clean_id = item['id'].removeprefix('animation:' if animated else ('concept:' if is_concept else 'model:'))
    def media(field):
        path = item.get(field) or ''
        return public_shape('gs://'+BUCKET+'/'+path,account) if isinstance(path, str) and path.startswith(f'users/{uid}/') else None
    return {'id':clean_id,'name':item.get('name','Untitled creation'),'creationKind':kind,
            'kind': 'animation' if animated else ('concept' if is_concept else 'model'),
            'engine': item.get('engine') if not animated and not is_concept else None,
            'model': item.get('model') if animated else None,
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
            'isExample':False}


@app.get('/api/v1/assets')
def v1_assets(account=Depends(v1_owner), archived: bool = False):
    CloudCreations(studio()).purge_expired_archives(account)
    result = []
    for item in studio().records(account,'mobileCreations'):
        kind = item.get('kind')
        if kind not in ('3D object','Animated character', 'Concept image'): continue
        archived_at = firebase_creations.seconds(item.get('archivedAt'))
        if (archived_at is not None) != archived: continue
        result.append(v1_asset_entry(item, account))
    # Newest first, so an agent's latest creation is always the first entry.
    result.sort(key=lambda a: a['createdAt'] or 0, reverse=True)
    return {'owned':result,'examples':[]}


@app.get('/api/v1/assets/{asset_id}')
def v1_asset(asset_id: str, account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    record, item = CloudCreations(studio()).find_creation_record(uid, asset_id)
    if item is None or item.get('kind') not in ('3D object', 'Animated character', 'Concept image'):
        raise HTTPException(404, 'Creation not found in your account.')
    return v1_asset_entry({**item, 'id': record}, account)


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


@app.patch('/api/v1/assets/{asset_id}')
def v1_rename_asset(asset_id: str, body: RenameRequest, account=Depends(v1_owner)):
    return CloudCreations(studio()).rename_asset(account, asset_id, body.name)


@app.get('/api/v1/assets/{asset_id}/download')
def v1_download_asset(asset_id: str, kind: Literal['model', 'preview', 'video', 'animation', 'image', 'auto'] = 'auto', account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    clean_id = asset_id.removeprefix('model:').removeprefix('animation:').removeprefix('concept:')
    creations = studio().db.collection('users').document(uid).collection('mobileCreations')
    doc = None
    for candidate in ('model:' + clean_id, 'animation:' + clean_id, 'concept:' + clean_id, clean_id):
        doc_ref = creations.document(candidate)
        doc = doc_ref.get()
        if doc.exists: break

    item = None
    if doc is not None and doc.exists:
        item = doc.to_dict() or {}
    else:
        concept_snap = studio().db.collection('users').document(uid).collection('studioConcepts').document(clean_id).get()
        if concept_snap.exists:
            item = concept_snap.to_dict() or {}
            item['kind'] = 'Concept image'
            item['previewStoragePath'] = item.get('imageUrl')

    if not item or item.get('ownerId') != uid:
        raise HTTPException(404, "Asset not found in your account.")

    creation_kind = item.get('kind')
    if kind in ('video', 'animation'):
        path = item.get('animationStoragePath')
    elif kind in ('preview', 'image'):
        path = item.get('previewStoragePath') or item.get('imageUrl')
    elif kind == 'model':
        path = item.get('modelStoragePath')
    else:  # auto
        if creation_kind == 'Animated character':
            path = item.get('animationStoragePath') or item.get('previewStoragePath') or item.get('modelStoragePath')
        elif creation_kind == 'Concept image':
            path = item.get('previewStoragePath') or item.get('imageUrl') or item.get('modelStoragePath')
        else:  # 3D object
            path = item.get('modelStoragePath') or item.get('previewStoragePath') or item.get('animationStoragePath')

    if not path:
        path = item.get('animationStoragePath') or item.get('modelStoragePath') or item.get('previewStoragePath') or item.get('imageUrl')

    if isinstance(path, str) and path.startswith(f'gs://{BUCKET}/'):
        path = path.removeprefix(f'gs://{BUCKET}/')

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


# -------------------------------------------------------------
# Direct Animation Endpoints
# -------------------------------------------------------------

class DirectAnimationRequest(BaseModel):
    idempotencyKey: str = Field(min_length=8, max_length=120)
    conceptId: Optional[str] = None
    assetId: Optional[str] = None
    prompt: Optional[str] = None
    motion: Optional[str] = None
    model: Literal['seedance-2.5', 'minimax-h3', 'atlas-seedance-2.0-mini',
                   'atlas-seedance-2.0', 'atlas-seedance-2.5',
                   'atlas-minimax-h3', 'atlas-wan-3.0-prime'] = 'seedance-2.5'
    resolution: Literal['480p', '720p', '768p', '2K'] = '480p'
    duration: Literal['4', '5', '6'] = '4'
    aspect: Literal['1:1', '16:9', '9:16'] = '1:1'
    maxTokens: int = Field(default=200, ge=1, le=1000)


@app.post('/api/v1/animations')
def v1_create_animation(body: DirectAnimationRequest, account=Depends(v1_owner)):
    if not animation_model_ready(body.model):
        raise HTTPException(503, 'Character animation is temporarily unavailable. No Tokens were charged.')
    uid = account.removeprefix('firebase:')

    # Case 1: Concept ID or Asset ID provided
    target_concept_id = body.conceptId
    if not target_concept_id and body.assetId:
        clean_asset_id = body.assetId.removeprefix('model:').removeprefix('animation:').removeprefix('concept:')
        for candidate in ('concept:' + clean_asset_id, 'model:' + clean_asset_id, 'animation:' + clean_asset_id, clean_asset_id):
            snap = studio().db.collection('users').document(uid).collection('mobileCreations').document(candidate).get()
            if snap.exists:
                c_ids = snap.to_dict().get('conceptIds') or []
                if c_ids:
                    target_concept_id = c_ids[0]
                    break
        if not target_concept_id:
            concept_snap = studio().db.collection('users').document(uid).collection('studioConcepts').document(clean_asset_id).get()
            if concept_snap.exists:
                target_concept_id = clean_asset_id

    if target_concept_id:
        clean_target = target_concept_id.removeprefix('concept:')
        anim_req = AnimationRequest(
            idempotencyKey=body.idempotencyKey,
            model=body.model,
            motion=body.motion,
            resolution=body.resolution,
            duration=body.duration,
            aspect=body.aspect,
            maxTokens=body.maxTokens,
        )
        return public_shape(v1_charge(account, lambda: CloudAnimations(studio()).create(account, clean_target, anim_req, environment=v1_environment(account))), account)

    # Case 2: Prompt provided (One-step prompt to animation)
    if not body.prompt or not body.prompt.strip():
        raise HTTPException(422, 'Provide either a conceptId, an assetId, or a prompt to create an animation.')

    if not concepts_ready():
        raise HTTPException(503, 'Cloud concepts are temporarily unavailable. No Tokens were charged.')

    quote_anim = pricing.animation_quote(body.resolution, int(body.duration), body.aspect, body.model)
    cost_anim = quote_anim['usageWithServiceFee']['credits']
    concept_quote = cloud_concept_provider.quote(time.time(), 1)
    cost_concept = concept_quote['maxTokens']
    total_tokens = cost_concept + cost_anim
    if body.maxTokens < total_tokens:
        raise HTTPException(409, f'This animation can cost up to {total_tokens} Tokens '
                                 f'({cost_concept} for the concept image, {cost_anim} for animation). '
                                 f'Set maxTokens to at least {total_tokens}.')

    name = body.prompt.strip()[:60]
    project = CloudProjects(studio()).create(account, prompt=body.prompt, name=name, style='Stylized',
                                             client_id='anim:' + body.idempotencyKey)
    concept_req = ConceptRequest(idempotencyKey=body.idempotencyKey, count=1, prompt=body.prompt,
                                 style='Stylized', maxTokens=cost_concept)
    auto_anim = dict(
        settings=dict(model=body.model, motion=body.motion, resolution=body.resolution,
                      duration=body.duration, aspect=body.aspect),
        maxTokens=cost_anim,
        environment=v1_environment(account)
    )
    job = CloudConcepts(studio()).create(account, project['id'], concept_req,
                                         environment=v1_environment(account), auto_animation=auto_anim)
    return public_shape(job, account)


@app.get('/api/v1/animations/{job_id}')
def v1_animation_status(job_id: str, account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    clean_id = job_id.removeprefix('animation:').removeprefix('concept:')

    # If it's a concept job that has an auto-animation:
    if clean_id.startswith('cj-'):
        concept = studio().db.collection('users').document(uid).collection('studioJobs').document(clean_id).get().to_dict()
        if not concept:
            raise HTTPException(404, 'Animation creation not found in your account.')
        anim_id = concept.get('animationJobId')
        anim = studio().db.collection('users').document(uid).collection('studioJobs').document(anim_id).get().to_dict() if anim_id else None

        stage = concept.get('stage', 'queued')
        status = concept.get('status', 'queued')
        progress = int(0.4 * (concept.get('progress') or 0))
        message = concept.get('message')
        error = concept.get('error')

        if concept.get('status') == 'done' and not anim:
            stage, status, progress, message = 'animation', 'running', 40, 'Starting your character animation'
        elif anim:
            if anim.get('status') == 'done':
                stage, status, progress, message = 'done', 'done', 100, anim.get('message')
            elif anim.get('status') == 'failed':
                stage, status, progress, message = 'failed', 'failed', 100, anim.get('error')
                error = anim.get('error')
            else:
                stage, status = 'animation', anim.get('status', 'running')
                progress = 40 + int(0.6 * (anim.get('progress') or 0))
                message = anim.get('message')

        asset = None
        if anim and anim.get('status') == 'done':
            asset = {
                'id': anim['id'],
                'downloadUrl': f'/api/v1/animations/{anim["id"]}/download',
                'videoUrl': f'/api/v1/assets/{anim["id"]}/download?kind=video'
            }

        return {
            'id': clean_id,
            'conceptJobId': clean_id,
            'animationJobId': anim_id,
            'status': status,
            'stage': stage,
            'progress': progress,
            'message': message,
            'error': error,
            'asset': asset,
            'createdAt': concept.get('createdAt')
        }

    # Direct animation job (an-...)
    job = studio().db.collection('users').document(uid).collection('studioJobs').document(clean_id).get().to_dict()
    if not job:
        raise HTTPException(404, 'Animation job not found in your account.')

    asset = None
    if job.get('status') == 'done':
        asset = {
            'id': clean_id,
            'downloadUrl': f'/api/v1/animations/{clean_id}/download',
            'videoUrl': f'/api/v1/assets/{clean_id}/download?kind=video'
        }

    return {
        'id': clean_id,
        'status': job.get('status', 'queued'),
        'stage': job.get('stage', 'queued'),
        'progress': job.get('progress', 0),
        'message': job.get('message'),
        'error': job.get('error'),
        'asset': asset,
        'cost': job.get('cost') or job.get('charged'),
        'createdAt': job.get('createdAt')
    }


@app.get('/api/v1/animations/{job_id}/download')
def v1_download_animation(job_id: str, account=Depends(v1_owner)):
    return v1_download_asset(job_id, kind='animation', account=account)


# -------------------------------------------------------------
# Direct Image Endpoints
# -------------------------------------------------------------

class DirectImageRequest(BaseModel):
    idempotencyKey: str = Field(min_length=8, max_length=120)
    prompt: str = Field(min_length=1, max_length=4000)
    projectId: Optional[str] = None
    style: Optional[str] = 'Stylized'
    count: int = Field(default=1, ge=1, le=4)
    maxTokens: int = Field(default=50, ge=1, le=500)


@app.post('/api/v1/images')
def v1_create_image(body: DirectImageRequest, account=Depends(v1_owner)):
    if not concepts_ready():
        raise HTTPException(503, 'Cloud concepts are temporarily unavailable. No Tokens were charged.')
    project_id = body.projectId
    if not project_id:
        name = body.prompt.strip()[:60]
        project = CloudProjects(studio()).create(account, prompt=body.prompt, name=name, style=body.style or 'Stylized',
                                                 client_id='img:' + body.idempotencyKey)
        project_id = project['id']
    req = ConceptRequest(idempotencyKey=body.idempotencyKey, count=body.count, prompt=body.prompt,
                         style=body.style, maxTokens=body.maxTokens)
    return public_shape(v1_charge(account, lambda: CloudConcepts(studio()).create(account, project_id, req, environment=v1_environment(account))), account)


@app.get('/api/v1/images/{concept_id}')
def v1_get_image(concept_id: str, account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    clean_id = concept_id.removeprefix('concept:')
    doc = studio().db.collection('users').document(uid).collection('studioConcepts').document(clean_id).get()
    if not doc.exists:
        raise HTTPException(404, 'Image not found in your account.')
    data = doc.to_dict() or {}
    return {
        'id': clean_id,
        'projectId': data.get('projectId'),
        'label': data.get('label'),
        'downloadUrl': f'/api/v1/images/{clean_id}/download',
        'imageUrl': public_shape(data.get('imageUrl'), account),
        'createdAt': data.get('createdAt')
    }


@app.get('/api/v1/images/{concept_id}/download')
def v1_download_image(concept_id: str, account=Depends(v1_owner)):
    clean_id = concept_id.removeprefix('concept:')
    content = CloudCreations(studio()).concept_image(account, clean_id)
    return Response(content=content, media_type='image/jpeg', headers={
        'Content-Disposition': f'attachment; filename="{clean_id}.jpg"',
        'Cache-Control': 'private, max-age=3600'
    })


# -------------------------------------------------------------
# Profile Management Endpoints
# -------------------------------------------------------------

class ProfileUpdateRequest(BaseModel):
    displayName: Optional[str] = Field(default=None, min_length=1, max_length=64)
    bio: Optional[str] = Field(default=None, max_length=500)
    avatarUrl: Optional[str] = Field(default=None, max_length=1000)
    avatarAssetId: Optional[str] = Field(default=None, max_length=100)
    appearance: Optional[dict] = None


@app.get('/api/v1/profile')
def v1_get_profile(account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    user_doc = studio().db.collection('users').document(uid).get()
    profile_data = user_doc.to_dict() if user_doc.exists else {}

    auth_user = None
    try:
        from firebase_admin import auth
        auth_user = auth.get_user(uid, app=firebase_app())
    except Exception:
        pass

    display_name = profile_data.get('displayName') or (auth_user.display_name if auth_user else None) or 'Creator'
    avatar_url = profile_data.get('avatarUrl') or (auth_user.photo_url if auth_user else None)

    # Read wallet summary
    wallet_info = CloudBilling(studio().db).wallet(uid, environment=v1_environment(account))

    # Aggregate counts
    creations = studio().records(account, 'mobileCreations')
    models_count = sum(1 for c in creations if c.get('kind') == '3D object')
    animations_count = sum(1 for c in creations if c.get('kind') == 'Animated character')
    concepts_count = sum(1 for c in creations if c.get('kind') == 'Concept image')
    projects = studio().records(account, 'studioProjects')

    return {
        'uid': uid,
        'displayName': display_name,
        'bio': profile_data.get('bio', ''),
        'avatarUrl': avatar_url,
        'avatarAssetId': profile_data.get('avatarAssetId'),
        'appearance': profile_data.get('appearance', {'theme': 'system'}),
        'wallet': {
            'available': wallet_info.get('available', 0),
            'subscriptionAvailable': wallet_info.get('subscriptionAvailable', 0),
            'packAvailable': wallet_info.get('packAvailable', 0),
        },
        'stats': {
            'totalCreations': len(creations),
            'modelsCount': models_count,
            'animationsCount': animations_count,
            'conceptsCount': concepts_count,
            'projectsCount': len(projects),
        },
        'updatedAt': profile_data.get('updatedAt')
    }


@app.patch('/api/v1/profile')
def v1_update_profile(body: ProfileUpdateRequest, account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    updates = {'updatedAt': time.time()}
    if body.displayName is not None:
        updates['displayName'] = body.displayName.strip()
    if body.bio is not None:
        updates['bio'] = body.bio.strip()
    if body.avatarUrl is not None:
        updates['avatarUrl'] = body.avatarUrl.strip()
    if body.avatarAssetId is not None:
        updates['avatarAssetId'] = body.avatarAssetId.strip()
    if body.appearance is not None:
        updates['appearance'] = body.appearance

    studio().db.collection('users').document(uid).set(updates, merge=True)

    # Sync with Firebase Auth best-effort
    try:
        from firebase_admin import auth
        auth_kwargs = {}
        if 'displayName' in updates: auth_kwargs['display_name'] = updates['displayName']
        if 'avatarUrl' in updates: auth_kwargs['photo_url'] = updates['avatarUrl']
        if auth_kwargs:
            auth.update_user(uid, **auth_kwargs, app=firebase_app())
    except Exception:
        pass

    return v1_get_profile(account)


# -------------------------------------------------------------
# Favorites Management Endpoints
# -------------------------------------------------------------

@app.get('/api/v1/favorites')
def v1_get_favorites(account=Depends(v1_owner)):
    return CloudCreations(studio()).favorites(account)


@app.post('/api/v1/assets/{asset_id}/favorite')
def v1_set_favorite(asset_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).set_favorite(account, asset_id, True)


@app.delete('/api/v1/assets/{asset_id}/favorite')
def v1_remove_favorite(asset_id: str, account=Depends(v1_owner)):
    return CloudCreations(studio()).set_favorite(account, asset_id, False)


# -------------------------------------------------------------
# AI Prompt Architect / Enhancement Endpoint
# -------------------------------------------------------------

class PromptEnhanceRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=4000)
    target: Literal['3d', 'animation', 'concept'] = '3d'
    style: Optional[str] = 'Stylized'


@app.post('/api/v1/prompts/enhance')
def v1_enhance_prompt(body: PromptEnhanceRequest, account=Depends(v1_owner)):
    """Architects & expands high-fidelity prompts optimized for 3D reconstruction and video loops."""
    raw_prompt = body.prompt.strip()
    target = body.target
    style = body.style or 'Stylized'

    if target == 'animation':
        enhanced = f"{raw_prompt}, full body turnaround, smooth natural character motion, expressive animation loop, high quality cinematic lighting, 4k render, style of {style}"
        negative = "ugly, distorted limbs, jerky motion, abrupt frame cuts, extra hands, missing fingers, low resolution, artifacts"
        engine = "seedance-2.5"
    elif target == 'concept':
        enhanced = f"{raw_prompt}, multi-angle character concept art, clean front view, T-pose, crisp silhouette, neutral studio lighting, isolated on solid background, style of {style}"
        negative = "cluttered background, cropped subject, harsh shadows, occluded details, text, watermark"
        engine = "gemini-3-pro-image"
    else:  # 3d
        enhanced = f"{raw_prompt}, clean watertight 3D game asset, sharp geometric bevels, PBR textured surface, uniform studio lighting, full turntable visibility, style of {style}"
        negative = "floating geometry, non-manifold edges, blurred albedo, baked hard shadows, low polygon artifacts"
        engine = "trellis"

    try:
        from . import cloud_planner_provider
        system_inst = (
            "You are an expert 3D generative AI prompt engineer and creative director for 3D Craft. "
            "MANDATORY LANGUAGE RULE: You MUST match the creator's language. If the creator prompt is in English, generate all fields ('enhancedPrompt', 'negativePrompt', 'suggestedStyle') 100% in English. If in Chinese, generate in Chinese. "
            "Given a creator's rough prompt, output a JSON object with: "
            "1. 'enhancedPrompt': an expanded, highly detailed description optimized for generative neural 3D and animation synthesis. "
            "2. 'negativePrompt': unwanted attributes to prevent deformities. "
            "3. 'suggestedEngine': 'trellis' or 'hunyuan' for 3d, 'seedance-2.5' or 'minimax-h3' for animation. "
            "4. 'suggestedStyle': aesthetic recommendation."
        )
        schema = {
            "type": "OBJECT",
            "properties": {
                "enhancedPrompt": {"type": "STRING"},
                "negativePrompt": {"type": "STRING"},
                "suggestedEngine": {"type": "STRING"},
                "suggestedStyle": {"type": "STRING"}
            },
            "required": ["enhancedPrompt", "negativePrompt", "suggestedEngine", "suggestedStyle"]
        }
        res = cloud_planner_provider.call(
            'generateContent',
            cloud_planner_provider.structured_body(system_inst, schema, f"Target: {target}\nStyle: {style}\nUser Prompt: {raw_prompt}", None, 'low', 1024),
            model='gemini-3.8-flash'
        )
        data = json.loads(res['candidates'][0]['content']['parts'][0]['text'])
        return {
            'originalPrompt': raw_prompt,
            'target': target,
            'enhancedPrompt': data.get('enhancedPrompt', enhanced),
            'negativePrompt': data.get('negativePrompt', negative),
            'suggestedEngine': data.get('suggestedEngine', engine),
            'suggestedStyle': data.get('suggestedStyle', style)
        }
    except Exception:
        return {
            'originalPrompt': raw_prompt,
            'target': target,
            'enhancedPrompt': enhanced,
            'negativePrompt': negative,
            'suggestedEngine': engine,
            'suggestedStyle': style
        }


# -------------------------------------------------------------
# Community Games for External Agents
# -------------------------------------------------------------

@app.get('/api/v1/community/games')
def v1_community_games(category: Category = 'fun', offset: int = Query(default=0, ge=0, le=10000), account=Depends(v1_owner)):
    uid = account.removeprefix('firebase:')
    return CloudCommunity(studio().db).feed(category, offset, uid)



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
    def engine_ready(ident):
        if os.getenv('CRAFT_MODEL_JOBS_ENABLED') != '1':
            return False
        if cloud_model_provider.atlas_model_provider.is_atlas_engine(ident):
            return bool(os.getenv('ATLAS_API_KEY'))
        return bool(os.getenv('FAL_KEY'))

    engines=[dict(id=ident,label=label,available=engine_ready(ident),ready=engine_ready(ident),provider='api',
        multiView=not cloud_model_provider.atlas_model_provider.is_atlas_engine(ident),
        multiViewDirections=([] if cloud_model_provider.atlas_model_provider.is_atlas_engine(ident)
                             else ['front','back','left'] if ident.startswith('hunyuan3d')
                             else ['front','back','left','right']))
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
    atlas = bool(request.headers.get('X-AtlasCloud-Webhook-Key-Id'))
    verifier = cloud_model_provider.atlas_model_provider.verify_callback if atlas else cloud_animation_provider.verify_callback
    rid=await run_in_threadpool(verifier,request.headers,bytes(raw))
    try: payload=json.loads(raw)
    except ValueError: raise HTTPException(422,'Invalid notification.') from None
    if not isinstance(payload,dict) or payload.get('session_id' if atlas else 'request_id')!=rid \
            or payload.get('status') not in ('OK','ERROR') \
            or (atlas and payload.get('event_type') != 'video.task.terminal'):
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
    atlas = bool(request.headers.get('X-AtlasCloud-Webhook-Key-Id'))
    verifier = cloud_model_provider.atlas_model_provider.verify_callback if atlas else cloud_model_provider.verify_callback
    rid=await run_in_threadpool(verifier,request.headers,bytes(raw))
    try: payload=json.loads(raw)
    except ValueError: raise HTTPException(422,'Invalid notification.') from None
    if not isinstance(payload,dict) or payload.get('session_id' if atlas else 'request_id')!=rid \
            or payload.get('status') not in ('OK','ERROR') \
            or (atlas and payload.get('event_type') != 'image.task.terminal'):
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
