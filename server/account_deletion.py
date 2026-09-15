"""Retryable account erasure. Only a recent owner sign-in may enqueue work.

Cloud Tasks retries interrupted steps; the durable marker blocks stale clients
from recreating erased data. Financial receipt ownership remains retained to
prevent granting an already-spent purchase to another account.
"""
import hashlib
import os
import time
from urllib.parse import quote

import requests
from fastapi import HTTPException
from firebase_admin import auth, firestore
from google.api_core.exceptions import AlreadyExists, NotFound
from google.cloud.firestore_v1.base_query import FieldFilter
from .identity import firebase_app
from .firebase_studio import uid_for

PROJECT = 'forma-studio-2026'
REGION = 'us-central1'
QUEUE = 'craft-account-deletion'


def request_ref(db, uid):
    try: uid_for('firebase:' + uid)
    except (ValueError, TypeError): raise HTTPException(400, 'Invalid account ID.') from None
    return db.collection('accountDeletions').document(uid)


def ensure_active(db, uid):
    if request_ref(db, uid).get().exists:
        raise HTTPException(403, 'Account deletion has been requested. This account can no longer create or purchase.')


def recent_sign_in(claims, now=None):
    now = time.time() if now is None else now
    stamp = claims.get('auth_time')
    if not isinstance(stamp, (float, int)) or isinstance(stamp, bool) or not 0 <= now - stamp <= 300:
        raise HTTPException(401, 'Please sign in again to confirm account deletion.')


def enqueue(uid):
    from google.cloud import tasks_v2
    from google.protobuf.duration_pb2 import Duration
    base = os.environ.get('CRAFT_TASK_ORIGIN', '').rstrip('/')
    identity = os.environ.get('CRAFT_TASK_IDENTITY', '')
    if not base.startswith('https://') or not identity:
        raise HTTPException(503, 'Account deletion is temporarily unavailable. Please try again shortly.')
    client = tasks_v2.CloudTasksClient()
    parent = client.queue_path(PROJECT, REGION, QUEUE)
    task = {'name': parent + '/tasks/delete-' + hashlib.sha256(uid.encode()).hexdigest(),
            'http_request': {'http_method': tasks_v2.HttpMethod.POST,
                'url': base + '/internal/account-deletions/' + quote(uid, safe=''),
                'oidc_token': {'service_account_email': identity, 'audience': base}},
            'dispatch_deadline': Duration(seconds=1800)}
    try:
        client.create_task(parent=parent, task=task)
    except AlreadyExists:
        pass  # The existing durable task owns retries, including concurrent requests.


def request_deletion(db, claims):
    uid = claims.get('uid') or claims['sub']
    ref = request_ref(db, uid)
    prior = ref.get()
    if prior.exists:
        if prior.to_dict().get('state') != 'completed': enqueue(uid)
        return {'status': prior.to_dict().get('state', 'pending')}
    recent_sign_in(claims)
    # Check configuration before placing the account behind the deletion barrier.
    if not os.getenv('CRAFT_TASK_ORIGIN') or not os.getenv('CRAFT_TASK_IDENTITY'):
        raise HTTPException(503, 'Account deletion is temporarily unavailable. Please try again shortly.')
    # Create the durable task before the barrier: a queue outage must not lock
    # the account. Early delivery sees no marker and retries without erasing.
    enqueue(uid)
    try:
        ref.create({'state': 'pending', 'requestedAt': time.time()})
    except AlreadyExists:
        pass
    return {'status': 'pending'}


def verify_worker(authorization):
    from google.auth.transport.requests import Request
    from google.oauth2 import id_token
    identity = os.getenv('CRAFT_TASK_IDENTITY', '')
    audience = os.getenv('CRAFT_TASK_ORIGIN', '').rstrip('/')
    if not identity or not audience or not authorization.startswith('Bearer '):
        raise HTTPException(401, 'Worker authentication required.')
    try:
        claims = id_token.verify_oauth2_token(authorization[7:], Request(), audience=audience)
        if claims.get('email') != identity or claims.get('email_verified') is not True:
            raise ValueError('Unexpected worker identity')
    except Exception:
        raise HTTPException(403, 'Worker identity could not be verified.') from None


def delete_customer(uid):
    key = os.getenv('REVENUECAT_DELETION_API_KEY', '')
    project = os.getenv('REVENUECAT_PROJECT_ID', '')
    if not key or not project: raise RuntimeError('RevenueCat deletion is not configured')
    # A dedicated V2 key can manage customers only, with no product, pricing,
    # subscription or purchase-write permissions.
    response = requests.delete('https://api.revenuecat.com/v2/projects/' + quote(project, safe='') + '/customers/' + quote(uid, safe=''),
                               headers={'Authorization': 'Bearer ' + key}, timeout=30)
    if response.status_code != 404: response.raise_for_status()


def erase_vote(db, game_ref, uid):
    vote_ref = game_ref.collection('votes').document(uid)
    @firestore.transactional
    def erase(tx):
        vote = vote_ref.get(transaction=tx)
        game = game_ref.get(transaction=tx)
        if not vote.exists: return
        if game.exists:
            counts = dict((game.to_dict() or {}).get('votes') or {})
            for category in set((vote.to_dict() or {}).get('categories') or []):
                counts[category] = max(0, int(counts.get(category, 0)) - 1)
            tx.update(game_ref, {'votes': counts, 'likes': sum(counts.values())})
        tx.delete(vote_ref)
    erase(db.transaction())


def erase_account(studio, uid):
    ref = request_ref(studio.db, uid)
    snap = ref.get()
    if not snap.exists: raise HTTPException(404, 'No confirmed deletion request.')
    state = snap.to_dict()
    if state.get('state') == 'completed': return {'status': 'completed'}
    ref.update({'state': 'deleting'})
    app = firebase_app()
    # Disabling prevents new tokens; Firestore/Storage rules also reject existing
    # tokens as soon as the durable deletion marker exists.
    try:
        auth.update_user(uid, disabled=True, app=app)
        auth.revoke_refresh_tokens(uid, app=app)
    except auth.UserNotFoundError:
        pass
    # Finish one idempotent step at a time; retries skip only completed steps.
    def step(name, operation):
        if not state.get(name):
            operation()
            ref.update({name: True})
            state[name] = True
    def remove_files():
        for blob in studio.bucket.list_blobs(prefix=f'users/{uid}/'):
            try: blob.delete(if_generation_match=blob.generation)
            except NotFound: pass
    step('filesDeleted', remove_files)
    def remove_public_content():
        for collection in ('assets', 'pipelines', 'communityGames'):
            for doc in studio.db.collection(collection).where(filter=FieldFilter('ownerId', '==', uid)).stream():
                studio.db.recursive_delete(doc.reference)
        # Old votes are keyed by UID, including rows missing the userId field.
        # Streaming document references avoids loading all game content.
        for game_ref in studio.db.collection('communityGames').list_documents():
            erase_vote(studio.db, game_ref, uid)
        for collection, fields in [('communityReports', ('reporterId', 'ownerId')),
                                   ('communityModeration', ('ownerId',))]:
            for field in fields:
                for doc in studio.db.collection(collection).where(filter=FieldFilter(field, '==', uid)).stream():
                    studio.db.recursive_delete(doc.reference)
    step('publicContentDeleted', remove_public_content)
    step('privateDataDeleted', lambda: studio.db.recursive_delete(studio.db.collection('users').document(uid)))
    def remove_identity():
        try: auth.delete_user(uid, app=app)
        except auth.UserNotFoundError: pass
    step('identityDeleted', remove_identity)
    step('revenueCatDeleted', lambda: delete_customer(uid))
    ref.set({'state': 'completed', 'requestedAt': state.get('requestedAt'), 'completedAt': time.time()})
    return {'status': 'completed'}
