"""Opt-in acceptance using disposable Firebase accounts and community records.

CRAFT_RUN_FIRESTORE_INTEGRATION=1 python scripts/verify_cloud_community.py
Add CRAFT_CHECK_DEPLOYED_COMMUNITY=1 after deploying the cloud API.
No purchases, generation requests, or messages to other users are made.
"""
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
if os.getenv('CRAFT_RUN_FIRESTORE_INTEGRATION') != '1':
    raise SystemExit('Set CRAFT_RUN_FIRESTORE_INTEGRATION=1 to run disposable cloud-data checks.')
import requests
import firebase_admin
from firebase_admin import credentials, firestore, auth
from google.oauth2.credentials import Credentials
from google.cloud.firestore_v1.base_query import FieldFilter
from fastapi import HTTPException
from server.firebase_community import CloudCommunity, Submission, Vote, Report, key
from server.account_deletion import erase_vote

PROJECT = 'forma-studio-2026'
BASE = 'https://3d-craft.web.app/api/mobile/community'


class CLIIdentity(credentials.Base):
    def get_credential(self):
        return Credentials(subprocess.check_output(['gcloud','auth','print-access-token'],text=True).strip(),quota_project_id=PROJECT)


app = firebase_admin.initialize_app(CLIIdentity(), {'projectId': PROJECT})
db = firestore.client(app=app)
run = uuid.uuid4().hex
creator, player = 'craft-community-author-'+run, 'craft-community-player-'+run
service = CloudCommunity(db, checker=lambda url: {'url':url, 'status':'reachable'})
fixture_ids = []


def denied(operation, code):
    try: operation()
    except HTTPException as exc: assert exc.status_code == code, (exc.status_code, code)
    else: raise AssertionError('Expected rejection')


try:
    for uid in (creator, player): db.collection('users').document(uid).set({'fixture': True})
    # The injected checker is explicitly a transport mock. Real URL validation
    # is tested through the deployed API below; these records are not real games.
    body = Submission(title='Disposable acceptance fixture', creator='Acceptance fixture',
        url='https://3d-craft.web.app/', played=True, rightsConfirmed=True, clientId='stable-fixture')
    with ThreadPoolExecutor(2) as pool: saved = list(pool.map(lambda _: service.submit(creator, body),range(2)))
    ident = saved[0]['id'];fixture_ids.append(ident)
    assert saved[0] == saved[1] and saved[0]['moderationStatus'] == 'pending'
    assert not any(g['id'] == ident for g in service.feed(uid=player)['games'])
    assert service.mine(creator)[0]['id'] == ident
    denied(lambda: service.play(ident, player), 404)
    denied(lambda: service.vote(player,ident,Vote(category='fun',liked=True)),404)
    denied(lambda: service.remove(player,ident),404)
    denied(lambda: service.submit(creator, body.model_copy(update={'title':'Changed'})),409)
    service.moderate(ident,'approved','Temporary automated acceptance fixture, removed at completion.','acceptance')
    with ThreadPoolExecutor(4) as pool:
        list(pool.map(lambda _: service.vote(player,ident,Vote(category='fun',liked=True)), range(4)))
    assert service.game(ident).get().to_dict()['votes']['fun'] == 1
    assert service.feed(uid=player)['games'][0]['myVotes'] == ['fun']
    for category in ('fun','animation','visuals','creativity'):
        assert any(g['id']==ident for g in service.feed(category,uid=player)['games'])
    service.block(player,ident)
    assert not any(g['id']==ident for g in CloudCommunity(db).feed(uid=player)['games'])
    denied(lambda: service.play(ident,player),404)
    denied(lambda: service.vote(player,ident,Vote(category='visuals',liked=True)),404)
    service.unblock(player, service.blocks(player)[0]['id'])
    assert service.play(ident,player)['url'] == body.url
    with ThreadPoolExecutor(2) as pool:
        list(pool.map(lambda _: service.report(player,ident,Report(reason='Acceptance test report')),range(2)))
    report_ref = db.collection('communityReports').document(key(player+':'+ident))
    assert report_ref.get().to_dict()['reason'] == 'Acceptance test report'
    assert not any(g['id']==ident for g in CloudCommunity(db).feed(uid=player)['games'])
    denied(lambda: service.play(ident,player),404)
    assert all('reporterId' not in g and 'reason' not in g for g in service.mine(creator))
    service.moderate(ident,'rejected','Acceptance removal','acceptance')
    assert not any(g['id']==ident for g in service.feed()['games'])
    service.resolve_report(report_ref.id,'Fixture removed','acceptance')
    assert report_ref.get().to_dict()['status']=='resolved'
    service.restrict_posting(creator,True,'Acceptance restriction','acceptance')
    denied(lambda: service.submit(creator,body.model_copy(update={'clientId':'blocked-post'})),403)
    service.restrict_posting(creator,False,'Acceptance appeal','acceptance')
    db.collection('accountDeletions').document(player).set({'state':'pending'})
    denied(lambda: service.report(player,ident,Report(reason='Retry')),403)
    denied(lambda: service.blocks(player),403)
    db.collection('accountDeletions').document(player).delete()
    erase_vote(db,service.game(ident),player)
    assert service.game(ident).get().to_dict()['votes']['fun']==0
    print('Firebase transactions passed: pending publication, concurrent retries/votes/reports, private blocking, moderation, posting restriction and deletion barrier.',flush=True)

    if os.getenv('CRAFT_CHECK_DEPLOYED_COMMUNITY') == '1':
        # Firebase client key is public app configuration; no service credential
        # is placed in a client request or printed in test output.
        config_response=requests.get('https://3d-craft.web.app/__/firebase/init.json',timeout=30)
        config_response.raise_for_status();config=config_response.json()
        password = secrets.token_urlsafe(30)
        auth.create_user(uid=player,email=player+'@example.com',password=password,app=app)
        response=requests.post('https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword',
            params={'key':config['apiKey']},json={'email':player+'@example.com','password':password,'returnSecureToken':True},timeout=30)
        response.raise_for_status(); headers={'Authorization':'Bearer '+response.json()['idToken']}
        docbase=f'https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents'
        for path in ('communityGames/'+ident,'communityReports/'+report_ref.id,
                     'users/'+player+'/private/community/hidden/'+ident):
            assert requests.get(docbase+'/'+path,headers=headers,timeout=20).status_code == 403
        forged = requests.patch(docbase+'/communityGames/'+ident,headers=headers,
            json={'fields':{'moderationStatus':{'stringValue':'approved'}}},timeout=20)
        assert forged.status_code == 403
        response=requests.get(BASE+'/games',headers=headers,timeout=30)
        assert response.status_code==200,response.text[:300]
        # Restore only this disposable fixture to verify the deployed write path.
        report_ref.delete()
        service.private(player).collection('hidden').document(ident).delete()
        service.moderate(ident,'approved','Temporary deployed API fixture, removed at completion.','acceptance')
        def like(_):
            r=requests.put(BASE+'/games/'+ident+'/vote',headers=headers,json={'category':'fun','liked':True},timeout=30)
            assert r.status_code==200,r.text[:300]
            return r.json()
        with ThreadPoolExecutor(3) as pool: results=list(pool.map(like,range(3)))
        assert all(r['votes']['fun']==1 for r in results)
        assert requests.post(BASE+'/games/'+ident+'/block',headers=headers,timeout=20).status_code==200
        assert requests.get(BASE+'/games/'+ident+'/play',headers=headers,timeout=20).status_code==404
        blocks=requests.get(BASE+'/blocks',headers=headers,timeout=20).json()
        assert requests.delete(BASE+'/blocks/'+blocks[0]['id'],headers=headers,timeout=20).status_code==200
        assert requests.post(BASE+'/games/'+ident+'/report',headers=headers,json={'reason':'Deployed fixture report'},timeout=20).status_code==200
        assert report_ref.get().to_dict()['reason']=='Deployed fixture report'
        assert requests.get(BASE+'/games/'+ident+'/play',headers=headers,timeout=20).status_code==404
        assert requests.post(BASE+'/games/'+ident+'/report',json={'reason':'No auth'},timeout=20).status_code==401
        response=requests.post(BASE+'/check-link',headers=headers,json={'url':'http://127.0.0.1/private'},timeout=30)
        assert response.status_code==422,response.text[:300]
        response=requests.post(BASE+'/check-link',headers=headers,json={'url':'https://3d-craft.web.app/'},timeout=45)
        assert response.status_code==200,response.text[:300]
        data=body.model_dump() | {'clientId':'deployed-fixture'}
        response=requests.post(BASE+'/games',headers=headers,json=data,timeout=45)
        assert response.status_code==200,response.text[:300]
        new=response.json();fixture_ids.append(new['id'])
        assert new['moderationStatus']=='pending'
        assert requests.post(BASE+'/games',headers=headers,json=data,timeout=45).json()['id']==new['id']
        assert requests.get(BASE+'/games/'+new['id']+'/play',headers=headers,timeout=20).status_code==404
        assert any(g['id']==new['id'] for g in requests.get(BASE+'/mine',headers=headers,timeout=20).json())
        assert requests.delete(BASE+'/games/'+new['id'],headers=headers,timeout=20).status_code==200
        print('Canonical API passed: identity, real URL validation, pending submission/retry/removal; direct Firestore reads and forged approval denied.',flush=True)
        delete=requests.post('https://3d-craft.web.app/api/mobile/account/delete',headers=headers,json={'confirm':True},timeout=30)
        assert delete.status_code==202,delete.text[:300]
        assert requests.get(BASE+'/blocks',headers=headers,timeout=20).status_code==403
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            state=db.collection('accountDeletions').document(player).get().to_dict() or {}
            if state.get('state')=='completed': break
            time.sleep(3)
        else: raise AssertionError('Deletion worker did not complete in acceptance window')
        assert not report_ref.get().exists
        assert not service.private(player).collection('hidden').document(ident).get().exists
        assert not service.game(new['id']).get().exists
        assert service.game(ident).get().to_dict()['votes']['fun']==0
        print('Deployed deletion worker removed reports, private safety preferences, submission and vote; stale identity rejected.',flush=True)
finally:
    for ident in fixture_ids: db.recursive_delete(service.game(ident))
    for collection in ('communityReports','communityModeration'):
        for uid in (creator,player):
            for snap in db.collection(collection).where(filter=FieldFilter('ownerId','==',uid)).stream(): db.recursive_delete(snap.reference)
    for uid in (creator,player):
        db.recursive_delete(db.collection('users').document(uid))
        db.collection('accountDeletions').document(uid).delete()
        try: auth.delete_user(uid,app=app)
        except auth.UserNotFoundError: pass
    print('Disposable Firebase accounts, private records and community fixtures removed.',flush=True)
