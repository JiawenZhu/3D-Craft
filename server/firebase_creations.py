"""API-key creations: one-step prompt-to-3D, project reads and permanent deletes.

A one-step creation is an ordinary concept job that carries an `autoModel`
request. When the concept worker settles that job, `continue_to_model` starts
the 3D job with a key derived from the concept job, so redelivery never starts
(or charges for) a second model. Everything is written to the same records the
iOS app reads, so API work appears in the app exactly like app work.
"""
import hashlib
import os
import time
from typing import Literal
from fastapi import HTTPException
from google.api_core.exceptions import NotFound
from pydantic import BaseModel, ConfigDict, Field
from . import cloud_concept_provider
from .firebase_billing import CloudBilling
from .firebase_concepts import CloudConcepts, ConceptRequest, TERMINAL as CONCEPT_TERMINAL
from .firebase_model_jobs import CloudModelJobs, ModelRequest, TERMINAL as MODEL_TERMINAL
from .firebase_projects import CloudProjects
from .firebase_studio import BUCKET, uid_for
from .pricing import model_quote

Engine = ModelRequest.model_fields['engine'].annotation
Quality = ModelRequest.model_fields['quality'].annotation
Effort = ModelRequest.model_fields['effort'].annotation


class CreationRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    idempotencyKey: str = Field(min_length=8, max_length=100)
    prompt: str = Field(default='', max_length=4000)
    projectId: str | None = Field(default=None, max_length=120)
    name: str | None = Field(default=None, max_length=120)
    style: str | None = Field(default=None, max_length=100)
    engine: Engine = 'rodin'
    quality: Quality = 'default'
    effort: Effort = 'high'
    maxTokens: int = Field(strict=True, ge=1, le=1000)


class RenameRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')
    name: str = Field(min_length=1, max_length=120)


def quote(engine='rodin', effort='high', now=None):
    now = now or time.time()
    concept = cloud_concept_provider.quote(now, 1)
    model = model_quote(engine, views=1, effort=effort)['usageWithServiceFee']['credits']
    if model is None:
        raise HTTPException(422, 'This 3D engine has no verified price.')
    return dict(conceptTokens=concept['maxTokens'], modelTokens=model,
                maxTokens=concept['maxTokens'] + model, expiresAt=concept['expiresAt'])


def model_job_id(uid, concept_job_id):
    return 'mj-' + hashlib.sha256((uid + ':' + auto_key(concept_job_id)).encode()).hexdigest()


def auto_key(concept_job_id):
    return 'auto:' + concept_job_id


def seconds(value):
    """Timestamps in seconds; older migrated records stored milliseconds."""
    if not isinstance(value, (int, float)):
        return None
    return value / 1000 if value > 1e11 else value


def api_image_url(concept_id):
    return f'/api/v1/concepts/{concept_id}/image'


def api_download_url(asset_id):
    return f'/api/v1/assets/{asset_id}/download'


def model_jobs_ready():
    return os.getenv('CRAFT_MODEL_JOBS_ENABLED') == '1' and bool(os.getenv('FAL_KEY'))


def continue_to_model(studio, uid, concept_job_id):
    """Start the 3D job for a settled one-step creation. Safe to call repeatedly."""
    concepts = CloudConcepts(studio)
    public, private = concepts.refs(uid, concept_job_id)
    auto = (private.get().to_dict() or {}).get('autoModel')
    job = public.get().to_dict() or {}
    if not auto or job.get('status') not in ('done', 'partial') or job.get('autoModelError'):
        return
    if not job.get('concepts'):
        return
    try:
        if not model_jobs_ready():
            raise HTTPException(503, 'Cloud 3D generation is temporarily unavailable. The concept image is kept.')
        body = ModelRequest(idempotencyKey=auto_key(concept_job_id), engine=auto['engine'],
                            quality=auto['quality'], effort=auto['effort'])
        model = CloudModelJobs(studio).create('firebase:' + uid, job['concepts'][0]['id'], body,
                                              environment=auto.get('environment'))
    except HTTPException as exc:
        # Transient failures retry through the worker; a decision (not enough
        # Tokens, removed image, unavailable engine) is final and shown.
        if exc.status_code in (402, 403, 404, 409, 422, 503):
            public.update({'autoModelError': str(exc.detail)})
            return
        raise
    public.update({'modelJobId': model['id']})


class CloudCreations:
    def __init__(self, studio):
        self.studio = studio
        self.db = studio.db
        self.projects = CloudProjects(studio)

    # ---------- create ----------

    def create(self, owner, body, environment=None):
        uid = uid_for(owner)
        if not body.prompt.strip() and not body.projectId:
            raise HTTPException(422, 'Describe what to create, or pass the projectId of a project with a reference image.')
        estimate = quote(body.engine, body.effort)
        if body.maxTokens < estimate['maxTokens']:
            raise HTTPException(409, f"This creation can cost up to {estimate['maxTokens']} Tokens "
                                     f"({estimate['conceptTokens']} for the image, {estimate['modelTokens']} for 3D). "
                                     f"Set maxTokens to at least {estimate['maxTokens']}.")
        concepts = CloudConcepts(self.studio)
        job_id = 'cj-' + hashlib.sha256((uid + ':' + body.idempotencyKey).encode()).hexdigest()
        if not concepts.refs(uid, job_id)[0].get().exists:
            wallet = CloudBilling(self.db).wallet(uid, environment=environment)
            if wallet['available'] < estimate['maxTokens']:
                raise HTTPException(402, f"Not enough Tokens. This creation can cost up to {estimate['maxTokens']} "
                                         f"Tokens and the wallet has {wallet['available']}.")
        project_id = body.projectId
        if not project_id:
            name = (body.name or body.prompt.strip()[:60] or 'Untitled idea').strip()
            project = self.projects.create(owner, prompt=body.prompt, name=name, style=body.style or 'Stylized',
                                           client_id='creation:' + body.idempotencyKey)
            project_id = project['id']
        request = ConceptRequest(idempotencyKey=body.idempotencyKey, count=1, prompt=body.prompt,
                                 style=body.style, maxTokens=estimate['conceptTokens'])
        auto = dict(engine=body.engine, quality=body.quality, effort=body.effort, environment=environment)
        job = concepts.create(owner, project_id, request, environment=environment, auto_model=auto)
        return self.status(owner, job['id'])

    # ---------- read ----------

    def job(self, uid, job_id):
        snap = self.projects.ref(uid, 'studioJobs', job_id).get()
        data = snap.to_dict() if snap.exists else None
        return {**data, 'id': snap.id} if data and data.get('ownerId') == uid else None

    def status(self, owner, creation_id):
        uid = uid_for(owner)
        concept = self.job(uid, creation_id) if creation_id.startswith('cj-') else None
        if not concept:
            raise HTTPException(404, 'Creation not found in your account.')
        model_id = concept.get('modelJobId') or model_job_id(uid, creation_id)
        model = self.job(uid, model_id)
        tokens = int(concept.get('charged') or 0) + int(concept.get('reserved') or 0)
        if model:
            tokens += int(model.get('charged') or model.get('reserved') or 0)
        result = dict(id=creation_id, projectId=concept.get('projectId'), prompt=concept.get('sourcePrompt'),
                      conceptJobId=creation_id, modelJobId=model['id'] if model else None,
                      concepts=[dict(id=c['id'], label=c.get('label'), imageUrl=api_image_url(c['id']))
                                for c in concept.get('concepts') or []],
                      asset=None, tokens=tokens, error=None, createdAt=concept.get('createdAt'))
        if concept.get('status') not in CONCEPT_TERMINAL:
            stage, status, progress = 'concepts', concept.get('status', 'queued'), int(0.4 * (concept.get('progress') or 0))
            message = concept.get('message')
        elif not concept.get('concepts'):
            stage, status, progress, message = 'failed', 'failed', 100, concept.get('message')
            result['error'] = concept.get('error') or 'The concept image could not be created. Unused Tokens were released.'
        elif concept.get('autoModelError') and not model:
            stage, status, progress, message = 'failed', 'failed', 100, 'The concept image is ready, but 3D could not start.'
            result['error'] = concept['autoModelError']
        elif not model:
            stage, status, progress, message = 'model', 'running', 40, 'Starting your 3D model'
        elif model.get('status') not in MODEL_TERMINAL:
            stage, status = 'model', model.get('status', 'queued')
            progress, message = 40 + int(0.6 * (model.get('progress') or 0)), model.get('message')
        elif model.get('status') == 'done':
            stage, status, progress, message = 'done', 'done', 100, model.get('message')
            result['asset'] = dict(id=model['id'], downloadUrl=api_download_url(model['id']),
                                   previewUrl=api_image_url(concept['concepts'][0]['id']))
        else:
            stage, status, progress, message = 'failed', 'failed', 100, model.get('message')
            result['error'] = model.get('error') or '3D generation did not complete. Unused Tokens were released.'
        result.update(stage=stage, status=status, progress=progress, message=message)
        return result

    def project(self, owner, project_id):
        uid = uid_for(owner)
        project = self.owned(uid, 'studioProjects', project_id)
        concepts = [c for c in self.studio.records(owner, 'studioConcepts') if c.get('projectId') == project_id]
        turns = [t for t in self.studio.records(owner, 'studioConversations') if t.get('projectId') == project_id]
        jobs = [j for j in self.studio.records(owner, 'studioJobs') if j.get('projectId') == project_id]
        models = [m for m in self.studio.records(owner, 'mobileCreations')
                  if m.get('projectId') == project_id and m.get('kind') == '3D object']
        for c in concepts:
            c['imageUrl'] = api_image_url(c['id'])
        by_time = lambda item: seconds(item.get('createdAt')) or 0
        return dict(
            id=project_id, name=project.get('name'), prompt=project.get('prompt'), style=project.get('style'),
            createdAt=project.get('createdAt'), updatedAt=project.get('updatedAt'),
            concepts=sorted(concepts, key=by_time),
            conversation=sorted(turns, key=by_time),
            jobs=[dict(id=j['id'], kind=j.get('kind'), status=j.get('status'), prompt=j.get('sourcePrompt'),
                       progress=j.get('progress'), message=j.get('message'), error=j.get('error'),
                       conceptIds=[c['id'] for c in j.get('concepts') or []], createdAt=j.get('createdAt'))
                  for j in sorted(jobs, key=by_time)],
            models=[dict(id=m['id'].removeprefix('model:'), name=m.get('name'), conceptIds=m.get('conceptIds') or [],
                         createdAt=seconds(m.get('createdAt')), downloadUrl=api_download_url(m['id'].removeprefix('model:')))
                    for m in sorted(models, key=by_time, reverse=True)])

    def owned(self, uid, collection, ident):
        snap = self.projects.ref(uid, collection, ident).get()
        data = snap.to_dict() if snap.exists else None
        if not data or data.get('ownerId') != uid:
            noun = {'studioProjects': 'Project', 'studioConcepts': 'Image', 'mobileCreations': '3D object'}[collection]
            raise HTTPException(404, f'{noun} not found in your account.')
        return data

    def concept_image(self, owner, concept_id):
        uid = uid_for(owner)
        concept = self.owned(uid, 'studioConcepts', concept_id)
        path = self.storage_path(uid, concept.get('imageUrl'))
        if not path:
            raise HTTPException(404, 'This image file is not available.')
        try:
            return self.studio.bucket.blob(path).download_as_bytes(timeout=60)
        except NotFound:
            raise HTTPException(404, 'This image file is not available.') from None

    # ---------- update ----------

    def rename(self, owner, project_id, name):
        uid = uid_for(owner)
        self.owned(uid, 'studioProjects', project_id)
        clean = name.strip()
        if not clean:
            raise HTTPException(422, 'Name cannot be empty.')
        self.projects.ref(uid, 'studioProjects', project_id).update({'name': clean, 'updatedAt': time.time()})
        return self.project(owner, project_id)

    # ---------- delete (permanent) ----------

    def storage_path(self, uid, url):
        prefix = f'gs://{BUCKET}/'
        path = url.removeprefix(prefix) if isinstance(url, str) and url.startswith(prefix) else url
        if isinstance(path, str) and path.startswith(f'users/{uid}/') and '..' not in path:
            return path
        return None

    def ensure_idle(self, jobs):
        if any(j.get('status') not in ('done', 'failed', 'partial') for j in jobs):
            raise HTTPException(409, 'A creation in this project is still running. Delete it after it finishes.')

    def remove(self, refs, paths):
        refs = list(refs)
        for start in range(0, len(refs), 400):
            batch = self.db.batch()
            for ref in refs[start:start + 400]:
                batch.delete(ref)
            batch.commit()
        for path in sorted(set(p for p in paths if p)):
            try:
                self.studio.bucket.blob(path).delete(timeout=30)
            except NotFound:
                pass

    def delete_project(self, owner, project_id):
        uid = uid_for(owner)
        project = self.owned(uid, 'studioProjects', project_id)
        of_project = lambda collection: [r for r in self.studio.records(owner, collection) if r.get('projectId') == project_id]
        jobs = of_project('studioJobs')
        self.ensure_idle(jobs)
        concepts, turns, creations = of_project('studioConcepts'), of_project('studioConversations'), of_project('mobileCreations')
        ref = self.projects.ref
        refs = ([ref(uid, 'studioJobs', j['id']) for j in jobs] + [ref(uid, 'studioConcepts', c['id']) for c in concepts] +
                [ref(uid, 'studioConversations', t['id']) for t in turns] + [ref(uid, 'mobileCreations', m['id']) for m in creations] +
                [ref(uid, 'studioProjects', project_id)])
        paths = ([self.storage_path(uid, c.get('imageUrl')) for c in concepts] + [self.storage_path(uid, project.get('imageUrl'))] +
                 [self.storage_path(uid, m.get(field)) for m in creations
                  for field in ('modelStoragePath', 'previewStoragePath', 'animationStoragePath')])
        self.remove(refs, paths)
        return dict(deleted=True, id=project_id, images=len(concepts),
                    models=sum(1 for m in creations if m.get('kind') == '3D object'),
                    animations=sum(1 for m in creations if m.get('kind') == 'Animated character'),
                    jobs=len(jobs))

    def delete_concept(self, owner, concept_id):
        uid = uid_for(owner)
        concept = self.owned(uid, 'studioConcepts', concept_id)
        project_id = concept.get('projectId')
        jobs = [j for j in self.studio.records(owner, 'studioJobs') if j.get('projectId') == project_id]
        self.ensure_idle(jobs)
        # Jobs embed the images they produced and the conversation shows those
        # copies, so the image must leave them too or it stays visible.
        for j in jobs:
            kept = [c for c in j.get('concepts') or [] if c.get('id') != concept_id]
            if len(kept) != len(j.get('concepts') or []):
                self.projects.ref(uid, 'studioJobs', j['id']).update({'concepts': kept})
        project_ref = self.projects.ref(uid, 'studioProjects', project_id)
        project = project_ref.get().to_dict() or {}
        if project.get('imageUrl') and project.get('imageUrl') == concept.get('imageUrl'):
            project_ref.update({'imageUrl': None})
        path = self.storage_path(uid, concept.get('imageUrl'))
        # A 3D model keeps using this file as its preview; keep the file then.
        shared = any(m.get('previewStoragePath') == path for m in self.studio.records(owner, 'mobileCreations')
                     if m.get('kind') in ('3D object', 'Animated character'))
        self.remove([self.projects.ref(uid, 'studioConcepts', concept_id),
                     self.projects.ref(uid, 'mobileCreations', 'concept:' + concept_id)],
                    [] if shared else [path])
        return dict(deleted=True, id=concept_id)

    def delete_asset(self, owner, asset_id):
        uid = uid_for(owner)
        clean = asset_id.removeprefix('model:').removeprefix('animation:')
        record, item = None, None
        for prefix in ('model:', 'animation:'):
            snap = self.projects.ref(uid, 'mobileCreations', prefix + clean).get()
            data = snap.to_dict() if snap.exists else None
            if data and data.get('ownerId') == uid:
                record, item = prefix + clean, data
                break
        if item is None:
            raise HTTPException(404, '3D object not found in your account.')
        refs = [self.projects.ref(uid, 'mobileCreations', record)]
        job = self.job(uid, clean)
        if job:
            self.ensure_idle([job])
            refs.append(self.projects.ref(uid, 'studioJobs', clean))
        # Only this creation's own file is deleted; its preview is the concept
        # image, which the project and any other creation still use.
        own = self.storage_path(uid, item.get('animationStoragePath') or item.get('modelStoragePath'))
        folder = 'animations' if item.get('kind') == 'Animated character' else 'models'
        paths = [own] if own and own.startswith(f'users/{uid}/{folder}/') else []
        self.remove(refs, paths)
        return dict(deleted=True, id=clean)
