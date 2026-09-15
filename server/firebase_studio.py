"""Durable creation storage shared by web and mobile.

Firestore contains metadata, not file bytes. Storage objects are immutable and
private; documents are published only after every referenced file is uploaded.
The runtime uses Application Default Credentials (a service identity in Cloud
Run), never a developer's browser token or service-account key in an app.
"""
from __future__ import annotations
import hashlib
import json
import mimetypes
from pathlib import Path
from urllib.parse import unquote, urlsplit
from firebase_admin import firestore, storage
from google.api_core.exceptions import PreconditionFailed
from .identity import firebase_app
from .config import RUNS, STORAGE

BUCKET = 'forma-studio-2026.firebasestorage.app'
ALLOWED = {'.png', '.jpg', '.jpeg', '.webp', '.glb', '.gltf', '.bin', '.usdz', '.obj', '.mtl'}


def uid_for(owner):
    if not isinstance(owner, str) or not owner.startswith('firebase:'):
        raise ValueError('Only verified Firebase accounts can own cloud creations')
    uid = owner.removeprefix('firebase:')
    if not uid or '/' in uid or uid in ('.', '..'):
        raise ValueError('Invalid account ID')
    return uid


def local_file(raw):
    path = unquote(urlsplit(raw).path)
    root = STORAGE if path.startswith('/files/') else RUNS if path.startswith('/runs/') else None
    if root is None:
        return None
    target = (root / path.split('/', 2)[2]).resolve()
    if not target.is_relative_to(root.resolve()) or target.suffix.lower() not in ALLOWED or not target.is_file():
        raise ValueError('A creation file is missing or outside its storage directory')
    return target


class FirebaseStudio:
    def __init__(self, db=None, bucket=None):
        self.db = db if db is not None else firestore.client(app=firebase_app())
        self.bucket = bucket if bucket is not None else storage.bucket(BUCKET, app=firebase_app())

    def file(self, owner, path: Path, category='files'):
        uid = uid_for(owner)
        if category not in ('files', 'models', 'images', 'previews') or path.suffix.lower() not in ALLOWED:
            raise ValueError('Unsupported creation file')
        if path.stat().st_size > 100 * 1024 * 1024:
            raise ValueError('Creation file exceeds the upload limit')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        name = f'users/{uid}/{category}/{digest}{path.suffix.lower()}'
        blob = self.bucket.blob(name)
        content_type = {'.glb': 'model/gltf-binary', '.usdz': 'model/vnd.usdz+zip'}.get(path.suffix.lower()) or mimetypes.guess_type(path.name)[0] or 'application/octet-stream'
        blob.cache_control = 'private, max-age=3600'
        blob.metadata = {'sha256': digest, 'ownerId': uid}
        try:
            blob.upload_from_filename(str(path), content_type=content_type, if_generation_match=0, checksum='auto')
        except PreconditionFailed:
            # Content-addressed objects can be shared by retries, never overwritten.
            blob.reload()
            if blob.size != path.stat().st_size or (blob.metadata or {}).get('sha256', digest) != digest:
                raise ValueError('Stored object does not match its creation file')
        return name

    def rewrite_files(self, owner, value):
        if isinstance(value, dict):
            return {k: self.rewrite_files(owner, v) for k, v in value.items()
                    if k not in ('workerId', 'providerKey', 'authorization', 'token')}
        if isinstance(value, list):
            return [self.rewrite_files(owner, v) for v in value]
        if isinstance(value, str) and value.startswith(('/files/', '/runs/')):
            path = local_file(value)
            return 'gs://' + BUCKET + '/' + self.file(owner, path)
        return value

    def save_creation(self, owner, item):
        uid = uid_for(owner)
        data = {k: item[k] for k in ('name', 'kind', 'createdAt', 'projectId', 'conceptIds', 'selectionKnown', 'prompt') if k in item}
        data.update(ownerId=uid, source='ios', storageVersion=2)
        for field, source, category in [('modelStoragePath', 'model', 'models'), ('previewStoragePath', 'image', 'previews')]:
            if item.get(source):
                path = local_file(item[source])
                if path is None: raise ValueError('Creation media must be an owned studio file')
                data[field] = self.file(owner, path, category)
        # Preserve legacy previews while older app versions are still installed.
        ref = self.db.collection('users').document(uid).collection('mobileCreations').document(item['id'])
        @firestore.transactional
        def publish(transaction):
            existing = ref.get(transaction=transaction)
            if not existing.exists:
                transaction.create(ref, data)
            else:
                prior = existing.to_dict()
                if prior.get('ownerId') != uid:
                    raise ValueError('Cloud creation owner does not match')
                # Preserve edits and existing object references in the live gallery.
                additions = {k: v for k, v in data.items() if k not in prior or prior[k] == ''}
                additions['storageVersion'] = 2
                transaction.update(ref, additions)
        publish(self.db.transaction())
        return data

    def save_record(self, owner, collection, ident, data):
        uid = uid_for(owner)
        if collection not in ('studioProjects', 'studioConcepts', 'studioJobs', 'studioConversations') or not ident or '/' in ident:
            raise ValueError('Invalid studio record')
        data = self.rewrite_files(owner, data)
        # Relationships are stored separately instead of duplicating growing arrays.
        if collection == 'studioProjects':
            data = {k: v for k, v in data.items() if k not in ('concepts', 'conversation')}
        data.update(ownerId=uid, storageVersion=2)
        if len(json.dumps(data).encode()) > 850_000:
            raise ValueError('Creation metadata must be split into smaller records')
        ref = self.db.collection('users').document(uid).collection(collection).document(ident)
        # Migration is non-destructive: a live cloud edit must never be replaced
        # by an older laptop snapshot. Re-running fills only missing records.
        from google.api_core.exceptions import AlreadyExists
        try: ref.create(data)
        except AlreadyExists:
            if collection == 'studioConversations' and data.get('projectId'):
                @firestore.transactional
                def link_conversation(transaction):
                    existing = ref.get(transaction=transaction).to_dict() or {}
                    if existing.get('ownerId') == uid and not existing.get('projectId'):
                        transaction.update(ref, {'projectId': data['projectId']})
                link_conversation(self.db.transaction())

    def records(self, owner, collection):
        uid = uid_for(owner)
        if collection not in ('studioProjects', 'studioConcepts', 'studioJobs', 'studioConversations', 'mobileCreations'):
            raise ValueError('Invalid studio collection')
        return [{**doc.to_dict(), 'id': doc.id} for doc in self.db.collection('users').document(uid).collection(collection).stream()]
