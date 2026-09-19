"""Shared fakes for the cloud tests: an in-memory Firestore, Storage and studio.

These let the creation, animation and Live Activity tests exercise the real
transaction, settlement and cleanup code without touching a live project. The
Firestore fake itself lives in `test_api_keys`, which introduced it; it is
imported here so every other test file has one place to look.
"""
from unittest.mock import Mock

from google.api_core.exceptions import NotFound

from server.firebase_studio import BUCKET
from tests.test_api_keys import MockFirestore

UID = 'user_alice'
OWNER = 'firebase:' + UID


def image(concept_id: str) -> str:
    """The gs:// URL of a concept image in this account's library."""
    return f'gs://{BUCKET}/users/{UID}/images/{concept_id}.jpg'


class Batch:
    """firestore.Client.batch(): collect deletes, apply them on commit."""

    def __init__(self):
        self.refs = []

    def delete(self, ref):
        self.refs.append(ref)

    def commit(self):
        for ref in self.refs:
            ref.delete()


class Studio:
    """FirebaseStudio's record and bucket API over the in-memory Firestore."""

    def __init__(self):
        self.db = MockFirestore()
        self.db.batch = Batch
        self.blobs: dict[str, bytes] = {}
        self.bucket = Mock()
        self.bucket.blob.side_effect = self.blob

    def blob(self, path):
        blob = Mock()

        def delete(timeout=None):
            if path not in self.blobs:
                raise NotFound(path)
            del self.blobs[path]

        def download(timeout=None):
            if path not in self.blobs:
                raise NotFound(path)
            return self.blobs[path]

        blob.delete.side_effect = delete
        blob.download_as_bytes.side_effect = download
        return blob

    # --- the studio API used by the services under test ---

    def records(self, owner, collection):
        uid = owner.removeprefix('firebase:')
        return [{**doc.to_dict(), 'id': doc.id}
                for doc in self.db.collection('users').document(uid).collection(collection).stream()]

    # --- helpers for arranging and asserting ---

    def put(self, collection, ident, **data):
        self.db.collection('users').document(UID).collection(collection).document(ident).set(
            {'ownerId': UID, **data})

    def doc(self, collection, ident):
        return self.db.collection('users').document(UID).collection(collection).document(ident).get().to_dict()

    def wallet(self, available=500, name='wallet', environment='PRODUCTION'):
        """Gives the account Tokens to spend and returns the wallet reference."""
        ref = self.db.collection('users').document(UID).collection('private').document(name)
        ref.set({'available': available, 'subscriptionAvailable': 0, 'environment': environment})
        return ref


class ProjectFixture:
    """A finished app-style project: prompt, one image, one 3D object, one chat turn.

    This is the shape the delete, read and animation tests all start from, so
    they assert against records that look like real ones.
    """

    def build(self, studio: Studio, pid='mp-1', cid='mc-1', mj='mj-1', job_status='done'):
        studio.put('studioProjects', pid, name='Dragon', prompt='a dragon', createdAt=1)
        studio.put('studioConcepts', cid, projectId=pid, imageUrl=image(cid), createdAt=2)
        studio.put('studioJobs', 'cj-' + cid[3:], projectId=pid, kind='concepts', status='done', createdAt=2,
                   concepts=[{'id': cid, 'imageUrl': image(cid)}])
        studio.put('studioJobs', mj, projectId=pid, kind='model', status=job_status, createdAt=3)
        studio.put('studioConversations', 'turn-' + pid, projectId=pid, text='make it red', createdAt=2)
        studio.put('mobileCreations', 'concept:' + cid, projectId=pid, kind='Concept image',
                   previewStoragePath=f'users/{UID}/images/{cid}.jpg', createdAt=2)
        studio.put('mobileCreations', 'model:' + mj, projectId=pid, kind='3D object', conceptIds=[cid],
                   previewStoragePath=f'users/{UID}/images/{cid}.jpg',
                   modelStoragePath=f'users/{UID}/models/{mj}.glb', createdAt=3)
        studio.blobs[f'users/{UID}/images/{cid}.jpg'] = b'jpg'
        studio.blobs[f'users/{UID}/models/{mj}.glb'] = b'glb'
        return studio
