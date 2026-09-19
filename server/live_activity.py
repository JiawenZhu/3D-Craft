"""Live Activity push updates for running creation jobs.

The iOS app starts one Live Activity per job and hands us its push token. Every
time the job's public record changes we push the same state the app would have
shown, so the Dynamic Island keeps up while the app is closed, and we send an
`end` event when the job settles.

This is a courtesy channel: a missing key, an expired token or an APNs outage
must never fail, delay or alter the job itself. Every entry point swallows its
own errors and reports only through the return value.
"""
from __future__ import annotations

import json
import os
import time
from typing import Any, Dict, Optional

TOPIC_SUFFIX = '.push-type.liveactivity'
PRODUCTION_HOST = 'https://api.push.apple.com'
SANDBOX_HOST = 'https://api.sandbox.push.apple.com'
# Apple rejects a token older than an hour; refresh well inside that.
TOKEN_TTL = 2400
# The app shows its own waiting state for far longer than a job should take.
STALE_AFTER = 300

_jwt: tuple[str, float] | None = None


def configured() -> bool:
    return bool(os.getenv('APNS_PRIVATE_KEY') and os.getenv('APNS_KEY_ID') and os.getenv('APNS_TEAM_ID'))


def bundle_id() -> str:
    return os.getenv('APNS_BUNDLE_ID', 'studio.craft.ios')


def host() -> str:
    return SANDBOX_HOST if os.getenv('APNS_SANDBOX') == '1' else PRODUCTION_HOST


def authorization() -> str:
    """A cached ES256 provider token, signed with the App Store Connect key."""
    global _jwt
    now = time.time()
    if _jwt and now - _jwt[1] < TOKEN_TTL:
        return _jwt[0]
    from google.auth import crypt
    import base64

    def segment(value: dict) -> bytes:
        raw = json.dumps(value, separators=(',', ':')).encode()
        return base64.urlsafe_b64encode(raw).rstrip(b'=')

    signer = crypt.ES256Signer.from_string(os.environ['APNS_PRIVATE_KEY'], os.environ['APNS_KEY_ID'])
    header = segment({'alg': 'ES256', 'kid': os.environ['APNS_KEY_ID']})
    claims = segment({'iss': os.environ['APNS_TEAM_ID'], 'iat': int(now)})
    payload = header + b'.' + claims
    signature = base64.urlsafe_b64encode(signer.sign(payload)).rstrip(b'=')
    token = (payload + b'.' + signature).decode()
    _jwt = (token, now)
    return token


def ref(db, uid: str, job_id: str):
    return (db.collection('users').document(uid).collection('private')
            .document('liveActivities').collection('items').document(job_id))


def register(db, uid: str, job_id: str, token: str) -> Dict[str, Any]:
    """Stores the activity's push token. Called by the app, so it may raise."""
    from fastapi import HTTPException
    if not isinstance(token, str) or not 32 <= len(token) <= 200 or any(c not in '0123456789abcdefABCDEF' for c in token):
        raise HTTPException(422, 'Invalid Live Activity token.')
    if not isinstance(job_id, str) or not job_id.startswith(('mj-', 'cj-')) or len(job_id) > 120:
        raise HTTPException(422, 'Invalid creation identifier.')
    ref(db, uid, job_id).set({'token': token, 'jobId': job_id, 'frame': 1, 'updatedAt': time.time()})
    return {'registered': True, 'pushEnabled': configured()}


def content_state(job: Dict[str, Any], frame: int) -> Dict[str, Any]:
    """The Swift `CraftGenerationAttributes.State`, by its Codable property names."""
    status = job.get('status') or 'queued'
    active = status in ('queued', 'running')
    failed = not active and status not in ('done', 'partial')
    done = not active and not failed
    phase = 'thinking' if status == 'queued' else ('model' if job.get('kind') == 'model' else 'concept')
    progress = 1.0 if done else min(max(float(job.get('progress') or 0) / 100, 0.0), 1.0)
    return {'phase': phase, 'progress': progress, 'frame': max(1, min(frame, 6)),
            'finished': done, 'failed': failed}


def payload(state: Dict[str, Any], event: str) -> Dict[str, Any]:
    aps: Dict[str, Any] = {'timestamp': int(time.time()), 'event': event, 'content-state': state}
    if event == 'update':
        aps['stale-date'] = int(time.time() + STALE_AFTER)
    else:
        # Leave a finished creation on the Lock Screen briefly; a failure less so.
        aps['dismissal-date'] = int(time.time() + (30 if state.get('failed') else 120))
    return {'aps': aps}


def send(token: str, body: Dict[str, Any], *, timeout: float = 10) -> int:
    import httpx
    headers = {'authorization': 'bearer ' + authorization(),
               'apns-topic': bundle_id() + TOPIC_SUFFIX,
               'apns-push-type': 'liveactivity',
               'apns-priority': '10',
               'apns-expiration': str(int(time.time() + STALE_AFTER))}
    with httpx.Client(http2=True, timeout=timeout) as client:
        response = client.post(f'{host()}/3/device/{token}', json=body, headers=headers)
    return response.status_code


def notify(db, uid: str, job: Dict[str, Any]) -> Optional[str]:
    """Pushes the job's current state to its Live Activity, if one is registered.

    Returns a short outcome for logs and tests; never raises.
    """
    try:
        job_id = job.get('id')
        if not job_id or not configured():
            return None
        doc = ref(db, uid, job_id).get()
        record = doc.to_dict() if doc.exists else None
        if not record or not record.get('token'):
            return None
        status = job.get('status') or 'queued'
        ending = status not in ('queued', 'running')
        frame = int(record.get('frame') or 1) % 6 + 1
        state = content_state(job, frame)
        code = send(record['token'], payload(state, 'end' if ending else 'update'))
        if ending or code in (400, 403, 410):
            # Gone, unauthorized, or simply over: stop tracking this activity.
            ref(db, uid, job_id).delete()
        else:
            ref(db, uid, job_id).update({'frame': frame, 'pushedAt': time.time()})
        return f'{"end" if ending else "update"}:{code}'
    except Exception as exc:  # noqa: BLE001 - a push must never break a job
        print(f'Live Activity push skipped: {type(exc).__name__}: {exc}')
        return None
