import unittest
from unittest.mock import patch, Mock
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError
from google.api_core.exceptions import Aborted
from server.firebase_community import CloudCommunity, Submission, Report, Vote, public_game, visible, apply_vote, valid_id
from server import firebase_api as api


class CommunityTests(unittest.TestCase):
    def test_blocked_artifact_needs_explicit_operator_browser_verification(self):
        db=Mock(); service=CloudCommunity(db); service.active=Mock()
        data=dict(ownerId='author',rightsConfirmed=True,played=True,reachable=False,
                  moderationStatus='pending',linkVerification='browser_review_required')
        ref=Mock();ref.get.return_value.to_dict.return_value=data
        service.game=Mock(return_value=ref)
        with patch('server.firebase_community.firestore.transactional',side_effect=lambda f:f):
            with self.assertRaises(ValueError):service.moderate('game','approved','Reviewed','operator')
            db.transaction.return_value.update.assert_not_called()
            service.moderate('game','approved','Opened and played public artifact','operator',browser_verified=True)
        changes=db.transaction.return_value.update.call_args.args[1]
        self.assertTrue(changes['reachable'])
        self.assertEqual(changes['linkVerification'],'browser_verified')
        self.assertTrue(db.transaction.return_value.create.call_args.args[1]['browserVerified'])

    def test_read_contention_retries_but_real_failures_remain_errors(self):
        service=CloudCommunity(Mock())
        operation=Mock(side_effect=[Aborted('conflict'), {'saved':True}])
        with patch('server.firebase_community.time.sleep'):
            self.assertEqual(service.transact(operation),{'saved':True})
            self.assertEqual(operation.call_count,2)
            with self.assertRaises(HTTPException) as error:
                service.transact(Mock(side_effect=Aborted('busy')))
            self.assertEqual(error.exception.status_code,503)
            with self.assertRaises(ValueError): service.transact(Mock(side_effect=ValueError('invalid')))

    def test_submission_requires_actual_consent_and_rejects_owner_or_status_injection(self):
        body = dict(title='Game', creator='Author', url='https://example.com/',
                    played=True, rightsConfirmed=True, clientId='stable-request')
        Submission(**body)
        for change in ({'played':False}, {'rightsConfirmed':False}, {'played':'true'},
                       {'title':'  '}, {'ownerId':'victim'}, {'moderationStatus':'approved'},
                       {'clientId':'../bad'}, {'browser_verified':True}):
            with self.assertRaises(ValidationError): Submission(**(body | change))
        for reason in ('', ' ', 'x'*501):
            with self.assertRaises(ValidationError): Report(reason=reason)

    def test_votes_are_intents_and_retries_never_increment_again(self):
        game = {'votes':{'fun':10, 'visuals':2}}
        votes, cats = apply_vote(game, ['fun'], 'fun', True)
        self.assertEqual(votes['fun'], 10)
        votes, cats = apply_vote(game, ['visuals'], 'fun', True)
        self.assertEqual(votes['fun'], 11); self.assertEqual(cats, ['fun','visuals'])
        votes, cats = apply_vote({'votes':votes}, cats, 'fun', False)
        self.assertEqual(votes['fun'], 10); self.assertEqual(cats, ['visuals'])
        with self.assertRaises(ValidationError): Vote(category='total', liked=True)
        with self.assertRaises(ValidationError): Vote(category='fun', liked=1)

    def test_only_approved_games_visible_and_private_fields_never_escape(self):
        game = dict(id='game', ownerId='alice', title='Game', creator='Author', reachable=True,
                    requestSignature='secret', rightsConfirmedAt=123, reviewNote='private outcome')
        self.assertFalse(visible(game))
        game['moderationStatus']='pending';self.assertFalse(visible(game))
        game['moderationStatus']='approved';self.assertTrue(visible(game))
        self.assertFalse(visible(game, 'bob', blocked={'alice'}))
        self.assertFalse(visible(game, 'bob', hidden={'game'}))
        self.assertFalse(visible(game | {'removed':True}))
        result = public_game(game, 'bob', ['fun'])
        self.assertNotIn('ownerId', result);self.assertNotIn('requestSignature',result)
        self.assertEqual(result['reviewNote'],'');self.assertEqual(result['myVotes'],['fun'])
        self.assertEqual(public_game(game,'alice')['reviewNote'],'private outcome')

    def test_document_paths_cannot_escape_collections(self):
        for ident in ('../alice','a/b','', 'x'*129):
            with self.assertRaises(HTTPException): valid_id(ident)

    def test_filtered_pagination_does_not_drop_tail_of_a_partial_batch(self):
        data=[dict(id=str(i),ownerId='author',moderationStatus='approved',reachable=True) for i in range(32)]
        class Query:
            def where(self, **kwargs): return self
            def order_by(self, *args, **kwargs): return self
            def offset(self, n): self.start=n;return self
            def limit(self, n): self.size=n;return self
            def stream(self): return [Mock(to_dict=Mock(return_value=d)) for d in data[self.start:self.start+self.size]]
        db=Mock();db.collection.return_value=Query();service=CloudCommunity(db)
        with patch.object(service,'filters',return_value=(set(),{'0'})),patch.object(service,'present',side_effect=lambda d,u:d):
            first=service.feed(uid='player')
            self.assertEqual(len(first['games']),30);self.assertTrue(first['hasMore']);self.assertEqual(first['nextOffset'],31)
            second=service.feed(uid='player',offset=first['nextOffset'])
            self.assertEqual([g['id'] for g in second['games']],['31']);self.assertFalse(second['hasMore'])

    def test_mutations_require_identity_guests_can_only_read_approved_feed(self):
        client = TestClient(api.app)
        for method, path, body in [('post','/games',{}),('post','/games/g/report',{'reason':'Spam'}),
            ('post','/games/g/block',{}),('delete','/games/g',None),
            ('put','/games/g/vote',{'category':'fun','liked':True}),('get','/blocks',None)]:
            self.assertEqual(client.request(method, '/api/mobile/community'+path,json=body).status_code,401)
        with patch.object(api, 'CloudCommunity') as service, patch.object(api, 'studio'):
            service.return_value.feed.return_value={'games':[],'hasMore':False,'nextOffset':0}
            self.assertEqual(client.get('/api/mobile/community/games').status_code,200)
            service.return_value.feed.assert_called_once_with('fun',0,None)
            self.assertEqual(client.get('/api/mobile/community/games?category=hack').status_code,422)
            self.assertEqual(client.get('/api/mobile/community/games?offset=-1').status_code,422)
            self.assertEqual(client.get('/api/mobile/community/games',headers={'Authorization':'bad'}).status_code,401)

    def test_backend_failure_cannot_produce_report_success(self):
        api.app.dependency_overrides[api.owner] = lambda: 'firebase:alice'
        try:
            with patch.object(api,'CloudCommunity') as service, patch.object(api,'studio'):
                service.return_value.report.side_effect=HTTPException(503,'Could not save')
                response=TestClient(api.app).post('/api/mobile/community/games/g/report',json={'reason':'Spam'})
                self.assertEqual(response.status_code,503)
                service.return_value.report.assert_called_once()
                self.assertEqual(service.return_value.report.call_args.args[:2],('alice','g'))
        finally: api.app.dependency_overrides.clear()


if __name__ == '__main__': unittest.main()
