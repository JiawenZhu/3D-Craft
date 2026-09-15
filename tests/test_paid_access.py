import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from server import mobile, identity, billing

class PaidAccessTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        for p in [patch.object(mobile,'DB_PATH',Path(self.tmp.name)/'accounts.sqlite'),patch.dict(os.environ,{'CRAFT_ALLOW_LOCAL_REVIEW':'0'})]:
            p.start();self.addCleanup(p.stop)
        app=FastAPI();app.include_router(mobile.router);app.include_router(billing.router)
        self.client=TestClient(app)
        self.headers={'Authorization':'Bearer valid-token'}
    def claims(self,uid='alice',provider='password'):
        return patch.object(identity,'verify_token',return_value={'uid':uid,'firebase':{'sign_in_provider':provider}})
    def payment(self,owner='firebase:alice',ident='cs_paid_1'):
        return {'id':ident,'mode':'payment','payment_status':'paid','currency':'usd','amount_total':499,'client_reference_id':owner,'metadata':{'owner':owner,'product':'craft.credits.small.v1'}}
    def test_admin_demo_grants_require_role_and_are_idempotent(self):
        from uuid import uuid4
        payload={'recipientEmail':'recipient@example.com','credits':200,'reason':'Demo access','requestId':str(uuid4())}
        path='/api/billing/admin/credits'
        self.assertEqual(self.client.post(path,json=payload).status_code,401)
        with self.claims(),patch.object(billing,'recipient_uid') as lookup:
            self.assertEqual(self.client.post(path,json=payload,headers=self.headers).status_code,403)
            lookup.assert_not_called()
        admin={'uid':'admin','admin':True,'firebase':{'sign_in_provider':'password'}}
        with patch.object(identity,'verify_token',return_value=admin),patch.object(billing,'recipient_uid',return_value='bob'):
            self.assertTrue(self.client.get('/api/billing/account',headers=self.headers).json()['isAdmin'])
            for _ in range(2):
                self.assertEqual(self.client.post(path,json=payload,headers=self.headers).status_code,200)
            self.assertEqual(self.client.post(path,json={**payload,'credits':201},headers=self.headers).status_code,409)
            for value in [0,-1,1.5,True,100001]:
                self.assertEqual(self.client.post(path,json={**payload,'credits':value},headers=self.headers).status_code,422)
        self.assertEqual(mobile.wallet('firebase:bob')['available'],200)
        self.assertEqual(identity.require_paid('firebase:bob'),'firebase:bob')
        with mobile.connect() as c:
            audit=c.execute('SELECT * FROM admin_credit_grants').fetchall()
            self.assertEqual(len(audit),1)
            self.assertEqual(audit[0]['actor'],'firebase:admin')
            self.assertEqual(audit[0]['reason'],'Demo access')
            c.execute('UPDATE users SET paid=0 WHERE id=?',('firebase:bob',))
        with self.assertRaises(Exception) as err:identity.require_paid('firebase:bob')
        self.assertEqual(err.exception.status_code,402)

    def test_no_device_or_guest_access(self):
        self.assertEqual(self.client.post('/api/mobile/session',json={'deviceId':'test-device'}).status_code,403)
        self.assertEqual(self.client.get('/api/mobile/wallet').status_code,401)
        with self.claims(provider='anonymous'):
            self.assertEqual(self.client.get('/api/mobile/wallet',headers=self.headers).status_code,401)
    def test_expired_or_forged_token_rejected(self):
        with patch.object(identity,'verify_token',side_effect=ValueError('bad signature')):
            self.assertEqual(self.client.get('/api/mobile/wallet',headers=self.headers).status_code,401)
    def test_new_account_has_no_free_credits(self):
        with self.claims():
            r=self.client.get('/api/mobile/wallet',headers=self.headers)
            self.assertEqual(r.status_code,200);self.assertEqual(r.json()['available'],0);self.assertEqual(r.json()['freeConceptTokens'],0)
            self.assertEqual(self.client.post('/api/mobile/development/credits',headers=self.headers).status_code,403)
            self.assertEqual(self.client.post('/api/mobile/development/purchase',headers=self.headers,json={'transactionId':'fake-payment','productId':'starter'}).status_code,403)
    def test_real_accounts_stay_empty_in_local_acceptance_mode(self):
        with self.claims(), patch.dict(os.environ, {'CRAFT_ALLOW_LOCAL_REVIEW':'1'}):
            owner = identity.require_account('Bearer valid-token')
            mobile.grant_review_credits(owner, initial=True)
            self.assertEqual(mobile.wallet(owner)['available'], 0)
            self.assertEqual(mobile.wallet(owner)['freeConceptTokens'], 0)
            for action in ('credits', 'purchase'):
                with self.assertRaises(Exception) as err:
                    if action == 'credits': mobile.review_credits(owner)
                    else: mobile.purchase(mobile.Purchase(productId='craft.credits.small.v1', transactionId='fabricated-local'), owner)
                self.assertEqual(err.exception.status_code, 403)
            with mobile.connect() as c:
                c.execute('UPDATE users SET paid=123 WHERE id=?', (owner,))
            identity.require_account('Bearer valid-token')
            mobile.grant_review_credits(owner, initial=True)
            self.assertEqual(mobile.wallet(owner)['available'], 123)

    def test_verified_payment_is_idempotent_and_isolated(self):
        with self.claims(): self.client.get('/api/mobile/wallet',headers=self.headers)
        billing.fulfill(self.payment());billing.fulfill(self.payment())
        self.assertEqual(mobile.wallet('firebase:alice')['available'],200)
        with self.claims('bob'):
            self.assertEqual(self.client.get('/api/mobile/wallet',headers=self.headers).json()['available'],0)
        self.assertEqual(identity.require_paid('firebase:alice'),'firebase:alice')
        with self.assertRaises(Exception): identity.require_paid('firebase:bob')
    def test_wrong_amount_and_unpaid_never_grant(self):
        with self.claims(): self.client.get('/api/mobile/wallet',headers=self.headers)
        for field,value in [('payment_status','unpaid'),('amount_total',1),('currency','eur'),('client_reference_id','firebase:bob')]:
            data=self.payment();data[field]=value
            with self.assertRaises(Exception):billing.fulfill(data)
        self.assertEqual(mobile.wallet('firebase:alice')['available'],0)
    def test_checkout_fails_closed_without_configuration(self):
        with self.claims(),patch.dict(os.environ,{'STRIPE_SECRET_KEY':'','STRIPE_WEBHOOK_SECRET':''}):
            self.assertEqual(self.client.post('/api/billing/checkout',headers=self.headers).status_code,503)
    def test_webhook_requires_signature(self):
        with patch.dict(os.environ,{'STRIPE_WEBHOOK_SECRET':'whsec_test'}),patch.object(billing,'stripe_client') as stripe:
            stripe.return_value.Webhook.construct_event.side_effect=ValueError('invalid')
            self.assertEqual(self.client.post('/api/billing/stripe/webhook',json={'type':'checkout.session.completed','data':{'object':self.payment()}}).status_code,400)
    def test_legacy_generation_cannot_bypass_auth_or_wallet(self):
        from server.app import app
        client=TestClient(app)
        for path in ['/api/generate','/api/pipelines','/api/concept-set']:
            self.assertEqual(client.post(path).status_code,401)
            with self.claims():self.assertEqual(client.post(path,headers=self.headers).status_code,402)
    def test_paid_generation_fails_closed_while_metering_unavailable(self):
        with self.claims():self.client.get('/api/mobile/wallet',headers=self.headers)
        billing.fulfill(self.payment())
        with self.assertRaises(Exception) as err:mobile.enqueue('firebase:alice',{},'model',None)
        self.assertEqual(err.exception.status_code,503)
        self.assertEqual(mobile.wallet('firebase:alice')['available'],200)

    def test_personal_chatgpt_generation_needs_identity_but_no_paid_balance(self):
        with self.claims(): self.client.get('/api/mobile/wallet',headers=self.headers)
        request=mobile.Generate(idempotencyKey='own-account-zero',count=4,imageModel='codex-gpt-image-2',plannerModel='gpt-5.6-sol')
        from server import codex_bridge
        with patch.object(mobile.planning,'require_available'), patch.object(codex_bridge,'account_status',return_value={'connected':True,'imageGenerationSupported':True}), patch.object(mobile._pool,'submit'):
            result=mobile.enqueue('firebase:alice',{'id':'own-project'},'concepts',request)
        self.assertEqual((result['cost'],result['reserved'],result['paidReserved'],result['trialReserved']),(0,0,0,0))
        self.assertEqual(mobile.wallet('firebase:alice')['available'],0)

if __name__=='__main__':unittest.main()
