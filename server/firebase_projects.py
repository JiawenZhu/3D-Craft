"""Native project/reference uploads published atomically to Firebase.

Queue cleanup before writing bytes. A delayed, authenticated task removes an
unpublished upload even if this request dies, or account erasure races upload.
Only temporary buffers live in this process; durable records and files are cloud.
"""
import hashlib
import io
import json
import os
import time
import uuid
import warnings
from urllib.parse import quote

from fastapi import HTTPException
from firebase_admin import firestore
from google.api_core.exceptions import NotFound, PreconditionFailed
from PIL import Image, ImageOps, UnidentifiedImageError
from .firebase_studio import BUCKET, uid_for
from .account_deletion import ensure_active

MAX_BYTES = 20 * 1024 * 1024
QUEUE = 'craft-upload-cleanup'


def normalized_image(raw):
    if len(raw) > MAX_BYTES:
        raise HTTPException(413, 'Choose a photo under 20 MB.')
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(raw)) as image:
                if image.format not in ('JPEG', 'PNG', 'WEBP') or image.width * image.height > 40_000_000:
                    raise ValueError('Unsupported image')
                image.load()
                clean = ImageOps.exif_transpose(image).convert('RGB')
                # A fresh image removes EXIF/GPS and embedded metadata.
                stripped = Image.new('RGB', clean.size)
                stripped.paste(clean)
                output = io.BytesIO()
                stripped.save(output, format='JPEG', quality=95)
                data = output.getvalue()
                if len(data) > MAX_BYTES:
                    raise HTTPException(413, 'Choose a smaller photo.')
                return data, stripped.width, stripped.height
    except HTTPException:
        raise
    except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise HTTPException(422, 'Choose a valid JPEG, PNG or WebP image.') from None


def enqueue_cleanup(uid, concept_id):
    from google.cloud import tasks_v2
    from google.protobuf.timestamp_pb2 import Timestamp
    base = os.getenv('CRAFT_TASK_ORIGIN', '').rstrip('/')
    identity = os.getenv('CRAFT_TASK_IDENTITY', '')
    if not base.startswith('https://') or not identity:
        raise HTTPException(503, 'Cloud uploads are temporarily unavailable. Please retry.')
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path('forma-studio-2026', 'us-central1', QUEUE)
    scheduled = Timestamp(seconds=int(time.time()) + 3600)
    # Unique per attempt: an old successful cleanup must not suppress cleanup of
    # a retry that arrives after Cloud Tasks' task-name retention window.
    task = {'http_request': {'http_method': tasks_v2.HttpMethod.POST,
        'url': base + '/internal/uploads/' + quote(uid, safe='') + '/' + concept_id,
        'oidc_token': {'service_account_email': identity, 'audience': base}},
        'schedule_time': scheduled}
    client.create_task(parent=parent, task=task, timeout=30, retry=None)


class CloudProjects:
    def __init__(self, studio):
        self.studio = studio
        self.db = studio.db

    def ref(self, uid, collection, ident):
        if not ident or '/' in ident or ident in ('.', '..') or len(ident) > 150:
            raise HTTPException(422, 'Invalid project reference.')
        return self.db.collection('users').document(uid).collection(collection).document(ident)

    def create(self, owner, *, prompt='', name='Untitled idea', style='Stylized', raw=None,
               project_id=None, client_id=None):
        uid = uid_for(owner)
        ensure_active(self.db, uid)
        if len(prompt) > 4000 or len(name) > 120 or len(style) > 100:
            raise HTTPException(422, 'Description is too long.')
        if client_id is not None and not 8 <= len(client_id) <= 120:
            raise HTTPException(422, 'Invalid request identifier.')
        if project_id is None and not prompt.strip() and raw is None:
            raise HTTPException(422, 'Add a photo or describe your idea.')
        if project_id is not None and raw is None:
            raise HTTPException(422, 'Choose a reference image.')
        image = normalized_image(raw) if raw is not None else None
        signature = hashlib.sha256(json.dumps([project_id, prompt, name, style,
            hashlib.sha256(image[0]).hexdigest() if image else None], ensure_ascii=False).encode()).hexdigest()
        ident = hashlib.sha256((uid + ':' + client_id).encode()).hexdigest() if client_id else uuid.uuid4().hex
        project_ref = self.ref(uid, 'studioProjects', project_id or 'mp-' + ident)
        concept_id = 'mc-' + ident if image else None
        concept_ref = self.ref(uid, 'studioConcepts', concept_id) if image else None
        request_ref = self.ref(uid, 'studioRequests', ident)

        def check(tx=None):
            if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
                raise HTTPException(403, 'This account is being deleted.')
            request = request_ref.get(transaction=tx)
            project = project_ref.get(transaction=tx)
            if project_id and (not project.exists or project.to_dict().get('ownerId') != uid):
                raise HTTPException(404, 'Project not found in your account.')
            if request.exists:
                prior = request.to_dict()
                if prior.get('signature') != signature:
                    raise HTTPException(409, 'This request identifier was already used for different content.')
                return prior['result']
            return None

        prior = check()
        if prior is not None:
            return prior
        now = time.time()
        result = dict(id=project_ref.id, name=name, prompt=prompt, style=style,
                      imageUrl=None, createdAt=now, concepts=[])
        concept = None
        if image:
            object_name = f'users/{uid}/images/{concept_id}.jpg'
            enqueue_cleanup(uid, concept_id)
            blob = self.studio.bucket.blob(object_name)
            blob.cache_control = 'private, max-age=3600'
            blob.metadata = {'ownerId': uid, 'sha256': hashlib.sha256(image[0]).hexdigest()}
            try:
                blob.upload_from_string(image[0], content_type='image/jpeg', if_generation_match=0,
                                        timeout=120, retry=None)
            except PreconditionFailed:
                blob.reload(timeout=30)
                if (blob.metadata or {}).get('sha256') != hashlib.sha256(image[0]).hexdigest():
                    raise HTTPException(409, 'This image request already contains different content.') from None
            source = 'gs://' + BUCKET + '/' + object_name
            label = 'Reference' if project_id else 'Original (Direct 3D)'
            concept = dict(id=concept_id, projectId=project_ref.id, parentId=None, name=label,
                label=label, prompt=prompt, imageUrl=source, width=image[1], height=image[2],
                isOriginal=True, direction=None, createdAt=now, ownerId=uid, storageVersion=2)
            result.update(imageUrl=source, concepts=[concept])
        response = concept if project_id else result

        @firestore.transactional
        def publish(tx):
            prior = check(tx)
            if prior is not None:
                return prior
            if time.time() - now > 1800:
                raise HTTPException(503, 'The upload took too long. Please retry.')
            if not project_id:
                tx.create(project_ref, {**{k:v for k,v in result.items() if k != 'concepts'},
                    'ownerId': uid, 'storageVersion': 2})
            if concept:
                tx.create(concept_ref, concept)
                creation_ref = self.ref(uid, 'mobileCreations', 'concept:' + concept_id)
                tx.create(creation_ref, dict(ownerId=uid, source='ios', storageVersion=2,
                    name=name if not project_id else 'Reference', kind='Concept image',
                    projectId=project_ref.id, conceptIds=[concept_id], prompt=prompt,
                    previewStoragePath=object_name, createdAt=now))
            tx.create(request_ref, {'signature': signature, 'result': response, 'createdAt': now})
            return response
        return publish(self.db.transaction())

    def cleanup(self, uid, concept_id):
        uid_for('firebase:' + uid)
        if not concept_id.startswith('mc-') or any(c not in '0123456789abcdef' for c in concept_id[3:]) or len(concept_id) not in (35, 67):
            raise HTTPException(422, 'Invalid upload identifier.')
        name = f'users/{uid}/images/{concept_id}.jpg'
        deleted = self.db.collection('accountDeletions').document(uid).get().exists
        concept = self.ref(uid, 'studioConcepts', concept_id).get()
        if not deleted and concept.exists and concept.to_dict().get('imageUrl') == 'gs://' + BUCKET + '/' + name:
            return {'status': 'retained'}
        blob = self.studio.bucket.blob(name)
        try:
            blob.reload(timeout=30)
            blob.delete(if_generation_match=blob.generation, timeout=30)
        except NotFound:
            pass
        return {'status': 'removed'}
