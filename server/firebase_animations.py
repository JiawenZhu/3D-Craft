"""Looping character animations: durable Seedance jobs with Token settlement.

The same shape as `firebase_model_jobs`: one idempotent job record, Tokens
reserved up front and settled once, a lease so only one worker advances a job,
and a signed provider callback that recovers a lost submit response. A paid
submission is never repeated.

The output is a muted MP4 that returns to its first frame, stored beside the
user's other creations so the app, the API and the library all see it.
"""
import hashlib
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
from pydantic import BaseModel, ConfigDict, Field
from typing import Literal

from . import cloud_animation_provider as provider
from . import atlas_animation_provider
from . import atlas_model_provider
from .firebase_billing import CloudBilling
from .firebase_projects import CloudProjects
from .firebase_studio import BUCKET, uid_for
from .firebase_usage import reserve, settle
from .firebase_subscriptions import expire_allowance
from .pricing import animation_quote, animation_usage

LIFETIME = 3600
LEASE = 900
TERMINAL = ('done', 'failed')
QUEUE = 'craft-model-jobs'


class AnimationRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    idempotencyKey: str = Field(min_length=8, max_length=120)
    model: Literal['seedance-2.5', 'minimax-h3', 'atlas-seedance-2.0-mini',
                   'atlas-seedance-2.0', 'atlas-seedance-2.5',
                   'atlas-minimax-h3', 'atlas-wan-3.0-prime'] = 'seedance-2.5'
    motion: str | None = Field(default=None, max_length=600)
    resolution: Literal['480p', '720p', '768p', '2K'] = '480p'
    duration: Literal['4', '5', '6'] = '4'
    aspect: Literal['1:1', '16:9', '9:16'] = '1:1'
    maxTokens: int = Field(strict=True, ge=1, le=1000)


def quote_for(body) -> dict:
    return animation_quote(body.resolution, int(body.duration), body.aspect, getattr(body, 'model', 'seedance-2.5'))


def enqueue(uid, jid):
    from google.cloud import tasks_v2
    base = os.environ['CRAFT_TASK_ORIGIN'].rstrip('/')
    identity = os.environ['CRAFT_TASK_IDENTITY']
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path('forma-studio-2026', 'us-central1', QUEUE)
    client.create_task(parent=parent, task={'http_request': {
        'http_method': tasks_v2.HttpMethod.POST,
        'url': f'{base}/internal/animation-jobs/{quote(uid, safe="")}/{jid}',
        'headers': {'X-Craft-Queued-At': str(int(time.time()))},
        'oidc_token': {'service_account_email': identity, 'audience': base}}}, timeout=30, retry=None)


class CloudAnimations:
    def __init__(self, studio, clock=time.time):
        self.studio = studio
        self.db = studio.db
        self.projects = CloudProjects(studio)
        self.billing = CloudBilling(self.db)
        self.now = clock

    def refs(self, uid, jid):
        if not jid.startswith('an-'):
            raise HTTPException(422, 'Invalid animation identifier.')
        return (self.projects.ref(uid, 'studioJobs', jid),
                self.billing.private(uid, 'animationJobs').collection('items').document(jid))

    def active(self, uid, tx=None):
        if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
            raise HTTPException(403, 'This account is being deleted.')

    def image_path(self, uid, url):
        prefix = f'gs://{BUCKET}/users/{uid}/'
        if not isinstance(url, str) or not url.startswith(prefix) or '..' in url.removeprefix(prefix).split('/'):
            raise HTTPException(422, 'The character must be saved in your private library.')
        return url.removeprefix(f'gs://{BUCKET}/')

    def create(self, owner, concept_id, body, environment=None):
        started = self.now()
        if atlas_animation_provider.is_atlas_animation(body.model):
            atlas_model_provider.headers()
            atlas_animation_provider.arguments('pending', body.motion, body.resolution,
                                               body.duration, body.aspect, body.model)
        else:
            provider.headers()  # Fail before reserving if the service has no key.
        uid = uid_for(owner)
        jid = 'an-' + hashlib.sha256((uid + ':' + body.idempotencyKey).encode()).hexdigest()
        public, private = self.refs(uid, jid)
        payload = body.model_dump(exclude={'idempotencyKey'})
        signature = hashlib.sha256(json.dumps([concept_id, payload], sort_keys=True).encode()).hexdigest()
        estimate = quote_for(body)
        cost = estimate['usageWithServiceFee']['credits']
        if cost is None:
            raise HTTPException(422, 'This animation has no verified price.')
        if body.maxTokens < cost:
            raise HTTPException(409, f'This animation costs {cost} Tokens. Set maxTokens to at least {cost}.')

        @firestore.transactional
        def create(tx):
            self.active(uid, tx)
            prior = private.get(transaction=tx)
            if prior.exists:
                if prior.to_dict()['signature'] != signature:
                    raise HTTPException(409, 'This request was already used for different work.')
                return public.get(transaction=tx).to_dict()
            snap = self.projects.ref(uid, 'studioConcepts', concept_id).get(transaction=tx)
            concept = snap.to_dict() if snap.exists else None
            if not concept or concept.get('ownerId') != uid:
                raise HTTPException(404, 'Image not found in your account.')
            project_snap = self.projects.ref(uid, 'studioProjects', concept['projectId']).get(transaction=tx)
            project = project_snap.to_dict() if project_snap.exists else None
            if not project or project.get('ownerId') != uid:
                raise HTTPException(404, 'Project not found in your account.')
            self.image_path(uid, concept.get('imageUrl'))
            effective_env = environment if environment is not None else \
                (self.billing.private(uid, 'billingContext').get(transaction=tx).to_dict() or {}).get('environment', 'PRODUCTION')
            if effective_env != 'SANDBOX' or os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1':
                effective_env = 'PRODUCTION'
            wallet_name = 'sandboxWallet' if effective_env == 'SANDBOX' else 'wallet'
            wallet_ref = self.billing.private(uid, wallet_name)
            before = wallet_ref.get(transaction=tx).to_dict() or {}
            before = self.billing.ensure_welcome(uid, before, wallet_ref, tx)
            after, allocation = reserve({**before, 'environment': effective_env}, cost, self.now())
            if self.now() - started > 120:
                raise HTTPException(503, 'The request took too long. Please retry.')
            data = dict(id=jid, ownerId=uid, projectId=concept['projectId'], kind='animation', status='queued',
                        stage='queued', progress=0, message='Preparing your character', concepts=[], assets=[],
                        cost=cost, reserved=cost, charged=0, createdAt=self.now(), error=None,
                        selectedConceptId=concept_id, selectedImageUrl=concept['imageUrl'],
                        providerEstimate=estimate,
                        animationSettings=dict(model=getattr(body, 'model', 'seedance-2.5'),
                                               resolution=body.resolution, duration=body.duration,
                                               aspect=body.aspect, motion=(body.motion or '').strip()))
            tx.create(public, data)
            tx.create(private, dict(signature=signature, phase='preparing', createdAt=self.now(),
                                    deadline=self.now() + LIFETIME, allocation=allocation, walletName=wallet_name,
                                    conceptId=concept_id, imageUrl=concept['imageUrl'], options=payload,
                                    projectId=concept['projectId'],
                                    name=project.get('name', 'Your character'),
                                    callbackToken=secrets.token_urlsafe(32), leaseUntil=0))
            tx.set(wallet_ref, after, merge=True)
            expired = max(0, int(before.get('subscriptionAvailable', 0)) - int(after.get('subscriptionAvailable', 0)) - allocation['subscription'])
            if expired:
                tx.create(wallet_ref.collection('entries').document(jid + ':expiry-reserve'),
                          dict(id=jid + ':expiry-reserve', amount=-expired, kind='subscription_expiry', createdAt=self.now()))
            tx.create(wallet_ref.collection('entries').document(jid + ':reserve'),
                      dict(id=jid + ':reserve', amount=-cost, kind='generation_reservation', createdAt=self.now(), jobId=jid))
            return data

        result = create(self.db.transaction())
        enqueue(uid, jid)
        return result

    def claim(self, uid, jid):
        public, private = self.refs(uid, jid)
        token = uuid.uuid4().hex

        @firestore.transactional
        def claim(tx):
            self.active(uid, tx)
            snap = private.get(transaction=tx)
            if not snap.exists:
                raise HTTPException(503, 'Waiting for the job record.')
            data = snap.to_dict()
            if data['phase'] in TERMINAL:
                return None, data
            if data.get('leaseUntil', 0) > self.now():
                raise HTTPException(503, 'This animation is already being checked.')
            tx.update(private, dict(leaseToken=token, leaseUntil=self.now() + LEASE))
            return token, data

        return claim(self.db.transaction())

    def advance(self, uid, jid, token, phase, updates, visible=None):
        public, private = self.refs(uid, jid)

        @firestore.transactional
        def advance(tx):
            self.active(uid, tx)
            data = private.get(transaction=tx).to_dict() or {}
            if data.get('leaseToken') != token or (phase is not None and data.get('phase') != phase) \
                    or data.get('leaseUntil', 0) <= self.now():
                return False
            tx.update(private, updates)
            if visible:
                tx.update(public, visible)
            return True

        moved = advance(self.db.transaction())
        if moved and visible:
            self.notify_activity(uid, jid)
        return moved

    def notify_activity(self, uid, jid):
        from . import live_activity
        try:
            job = self.projects.ref(uid, 'studioJobs', jid).get().to_dict()
        except Exception:
            return
        if job:
            live_activity.notify(self.db, uid, {**job, 'id': jid})

    def request_received(self, uid, jid, request_id, callback_token=None, failed=False):
        _, private = self.refs(uid, jid)
        if not isinstance(request_id, str) or not 1 <= len(request_id) <= 128 \
                or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in request_id):
            raise HTTPException(422, 'Invalid provider request identifier.')

        @firestore.transactional
        def receive(tx):
            self.active(uid, tx)
            data = private.get(transaction=tx).to_dict()
            if not data:
                raise HTTPException(404, 'Animation not found.')
            if callback_token is not None and not secrets.compare_digest(data['callbackToken'], callback_token):
                raise HTTPException(401, 'Invalid notification destination.')
            if data['phase'] in TERMINAL:
                return
            if data['phase'] not in ('submitting', 'submitted'):
                raise HTTPException(409, 'Animation has not been submitted.')
            if data.get('requestId') and data['requestId'] != request_id:
                raise HTTPException(409, 'Conflicting provider request identifier.')
            update = dict(requestId=request_id, phase='submitted')
            if failed:
                update['providerFailed'] = True
            tx.update(private, update)

        receive(self.db.transaction())

    def finish(self, uid, jid, token, *, asset=None, error=None, usage=None):
        public, private = self.refs(uid, jid)

        @firestore.transactional
        def finish(tx):
            self.active(uid, tx)
            data = private.get(transaction=tx).to_dict()
            if data['phase'] in TERMINAL:
                return data['phase']
            if data.get('leaseToken') != token or data.get('leaseUntil', 0) <= self.now():
                raise HTTPException(503, 'Settlement will resume.')
            allocation = data['allocation']
            # Charge for the clip fal actually produced, never more than was
            # authorized. A shorter or smaller result costs less.
            measured = (usage or {}).get('usageWithServiceFee', {}).get('credits') if asset else None
            charge = min(allocation['cost'], measured) if measured is not None else (allocation['cost'] if asset else 0)
            wallet_ref = self.billing.private(uid, data['walletName'])
            wallet = wallet_ref.get(transaction=tx).to_dict() or {}
            refunded = False
            if allocation.get('subscriptionTransaction'):
                key = hashlib.sha256(('APP_STORE:' + allocation['subscriptionTransaction']).encode()).hexdigest()
                receipt = self.db.collection('billingReceipts').document(key).get(transaction=tx).to_dict()
                refunded = not receipt or receipt.get('refunded', False)
            current = expire_allowance(wallet, self.now())
            after = settle(wallet, allocation, charge, self.now(), refunded)
            returned = after.get('available', 0) + after.get('subscriptionAvailable', 0) \
                - current.get('available', 0) - current.get('subscriptionAvailable', 0)
            state = 'done' if asset else 'failed'
            tx.set(wallet_ref, after, merge=True)
            tx.create(wallet_ref.collection('entries').document(jid + ':settled'),
                      dict(id=jid + ':settled', amount=max(0, returned),
                           kind='generation_complete' if asset else 'generation_refund',
                           charged=charge, createdAt=self.now(), jobId=jid))
            tx.update(private, dict(phase=state, leaseUntil=0, finishedAt=self.now()))
            visible = dict(status=state, stage=state, progress=100 if asset else 0,
                           message='Your animated character is ready' if asset else error, error=error,
                           assets=[asset] if asset else [], reserved=0, charged=charge,
                           completedAt=self.now())
            if usage:
                visible['providerUsage'] = {k: usage.get(k) for k in
                                            ('providerTokens', 'width', 'height', 'seconds', 'totalUsd')}
            tx.update(public, visible)
            if asset:
                tx.create(self.projects.ref(uid, 'mobileCreations', 'animation:' + jid),
                          dict(ownerId=uid, source='ios', storageVersion=2, name=data['name'],
                               kind='Animated character', projectId=data['projectId'],
                               model=data.get('options', {}).get('model'),
                               conceptIds=[data['conceptId']], previewStoragePath=self.image_path(uid, data['imageUrl']),
                               animationStoragePath=f'users/{uid}/animations/{jid}.mp4', createdAt=self.now()))
            return state

        state = finish(self.db.transaction())
        self.notify_activity(uid, jid)
        return state

    def run(self, uid, jid, queued_at=None):
        try:
            token, data = self.claim(uid, jid)
        except HTTPException as exc:
            if exc.status_code == 403:
                return {'status': 'account-deleted'}
            if exc.status_code == 503 and queued_at and self.now() - queued_at > 600:
                if not self.refs(uid, jid)[1].get().exists:
                    return {'status': 'unpublished-request'}
            raise
        if token is None:
            return {'status': data['phase']}
        phase = data['phase']
        try:
            if self.now() > data['deadline']:
                return {'status': self.finish(uid, jid, token,
                                              error='This animation could not be completed. Your reserved Tokens have been released.')}
            if phase == 'preparing':
                with tempfile.TemporaryDirectory() as folder:
                    blob = self.studio.bucket.blob(self.image_path(uid, data['imageUrl']))
                    blob.reload(timeout=30)
                    if blob.size > 20 * 1024 * 1024:
                        raise ValueError('Character image exceeds the size limit')
                    target = Path(folder) / 'character.jpg'
                    blob.download_to_filename(str(target), if_generation_match=blob.generation, timeout=120, retry=None)
                    model_name = data['options'].get('model', 'seedance-2.5')
                    if atlas_animation_provider.is_atlas_animation(model_name):
                        url = atlas_model_provider.upload_media(target)
                    else:
                        import fal_client
                        from fal_client.client import StorageSettings
                        url = fal_client.upload_file(target, lifecycle=StorageSettings(expires_in=7200))
                options = data['options']
                model_name = options.get('model', 'seedance-2.5')
                if atlas_animation_provider.is_atlas_animation(model_name):
                    arguments = atlas_animation_provider.arguments(url, options.get('motion'),
                        options['resolution'], options['duration'], options['aspect'], model_name)
                else:
                    arguments = provider.arguments(url, options.get('motion'), options['resolution'],
                                                   options['duration'], options['aspect'], model=model_name)
                if not self.advance(uid, jid, token, phase, dict(phase='prepared', arguments=arguments),
                                    dict(status='running', stage='animating', progress=10,
                                         message='Bringing your character to life')):
                    raise HTTPException(503, 'Job state changed; retrying.')
                data['arguments'] = arguments
                phase = 'prepared'
            if phase == 'prepared':
                if not self.advance(uid, jid, token, phase, dict(phase='submitting', submittedAt=self.now())):
                    raise HTTPException(503, 'Job state changed; retrying.')
                phase = 'submitting'
                callback = ('https://3d-craft.web.app/api/animations/callback/' + quote(uid, safe='')
                            + '/' + jid + '/' + data['callbackToken'])
                model_name = data.get('options', {}).get('model', 'seedance-2.5')
                if atlas_animation_provider.is_atlas_animation(model_name):
                    rid = atlas_animation_provider.submit(data['arguments'], callback)
                else:
                    endpoint = provider.endpoint_for(model_name)
                    rid = provider.submit(endpoint, data['arguments'], callback)
                self.request_received(uid, jid, rid)
                data['requestId'] = rid
                phase = 'submitted'
            if phase == 'submitting':
                # The POST response was lost. Wait for the signed callback rather
                # than paying for a second animation.
                raise HTTPException(503, 'Waiting for provider confirmation.')
            if phase == 'submitted':
                if data.get('providerFailed'):
                    return {'status': self.finish(uid, jid, token,
                                                  error='The animation service could not complete this character. Your reserved Tokens have been released.')}
                model_name = data.get('options', {}).get('model', 'seedance-2.5')
                if atlas_animation_provider.is_atlas_animation(model_name):
                    try:
                        result = atlas_animation_provider.status(data['requestId'])
                    except RuntimeError:
                        return {'status': self.finish(uid, jid, token,
                                                      error='The animation service could not complete this character. Your reserved Tokens have been released.')}
                else:
                    endpoint = provider.endpoint_for(model_name)
                    result = provider.status(endpoint, data['requestId'])
                if result is None:
                    raise HTTPException(503, 'The animation is still rendering.')
                with tempfile.TemporaryDirectory() as folder:
                    target = Path(folder) / 'animation.mp4'
                    if atlas_animation_provider.is_atlas_animation(model_name):
                        atlas_animation_provider.download_video(result, str(target))
                    else:
                        provider.download_video(result, str(target))
                    try:
                        width, height, seconds = provider.measure(str(target))
                        usage = animation_usage(width, height, seconds, model=model_name,
                                                resolution=data['options']['resolution'])
                    except (ValueError, OSError):
                        usage = None  # Unreadable header: fall back to the authorized quote.
                    blob = self.studio.bucket.blob(f'users/{uid}/animations/{jid}.mp4')
                    blob.cache_control = 'private, max-age=3600'
                    try:
                        blob.upload_from_filename(str(target), content_type='video/mp4',
                                                  if_generation_match=0, timeout=180, retry=None)
                    except PreconditionFailed:
                        pass  # The same finished job uploaded before a crash.
                asset = dict(id=jid, name=data['name'], kind='animation',
                             animationUrl=f'gs://{BUCKET}/users/{uid}/animations/{jid}.mp4',
                             thumbUrl=data['imageUrl'], isExample=False)
                return {'status': self.finish(uid, jid, token, asset=asset, usage=usage)}
        except (ValueError, NotFound):
            return {'status': self.finish(uid, jid, token,
                                          error='The animation could not be saved. Your reserved Tokens have been released.')}
        finally:
            try:
                self.advance(uid, jid, token, None, dict(leaseUntil=0))
            except Exception:
                pass
        raise HTTPException(503, 'Animation will be checked again.')
