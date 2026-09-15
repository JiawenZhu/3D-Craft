import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from server import mobile, identity, revenuecat_billing as rc

MONTH = 'craft.creator.monthly.v1'
WEEK = 'craft.creator.weekly.v1'
PACK = 'craft.credits.small.v1'

class RevenueCatBillingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        for p in (patch.object(mobile, 'DB_PATH', Path(self.temp.name)/'billing.sqlite'),
                  patch.object(mobile, 'IS_PRODUCTION', False),
                  patch.dict(os.environ, {'CRAFT_ALLOW_LOCAL_REVIEW':'0', 'CRAFT_REVENUECAT_SANDBOX':'1', 'REVENUECAT_WEBHOOK_AUTHORIZATION':'Bearer test-webhook'})):
            p.start(); self.addCleanup(p.stop)
        with mobile.connect() as c:
            for uid in ('alice', 'bob'):
                c.execute('INSERT INTO users VALUES(?,?,0,0)', ('firebase:'+uid,'firebase:'+uid))
        app=FastAPI();app.include_router(rc.router);self.client=TestClient(app)
        self.auth={'Authorization':'Bearer test-user'}
        self.identity=patch.object(identity,'verify_token',return_value={'uid':'alice','firebase':{'sign_in_provider':'password'}})
        self.identity.start();self.addCleanup(self.identity.stop)

    def item(self, tid='apple-1', **values):
        return {'store':'app_store','store_transaction_id':tid,'is_sandbox':True,'ownership_type':'PURCHASED','period_type':'normal','refunded_at':None,**values}
    def info(self, product=MONTH, item=None):
        return {'subscriptions':{product:item or self.item()},'non_subscriptions':{}}
    def claim(self, product=MONTH, tid='apple-1'):
        return self.client.post('/api/mobile/purchases/revenuecat',headers=self.auth,json={'productId':product,'transactionId':tid})
    def event(self, tid='apple-1', **values):
        return {'type':'INITIAL_PURCHASE','app_id':rc.APP_ID,'store':'APP_STORE','app_user_id':'alice','product_id':MONTH,'transaction_id':tid,'environment':'SANDBOX','period_type':'NORMAL',**values}
    def webhook(self,event,header='Bearer test-webhook'):
        return self.client.post('/api/billing/revenuecat/webhook',headers={'Authorization':header},json={'event':event})
    def balance(self,who='alice'):return mobile.wallet('firebase:'+who)['available']

    def test_acceptance_purchase_generate_retry_restore_and_signout(self):
        import io
        from PIL import Image
        app = FastAPI(); app.include_router(mobile.router); app.include_router(rc.router)
        client = TestClient(app)
        headers = {'Authorization':'Bearer test.firebase.token'}
        queued = []
        info = {'subscriptions':{}, 'non_subscriptions':{PACK:[self.item('pack-acceptance')]}}
        with patch.dict(os.environ, {'CRAFT_ALLOW_LOCAL_REVIEW':'1', 'RODIN_MOBILE_DEVELOPMENT':'1'}), patch.object(mobile, 'STORAGE', Path(self.temp.name)/'assets'), patch.object(mobile._pool, 'submit', side_effect=lambda fn,*args: queued.append((fn,args))):
            self.assertEqual(client.get('/api/mobile/wallet').status_code,401)
            self.assertEqual(client.get('/api/mobile/wallet',headers=headers).json()['available'],0)
            image = io.BytesIO(); Image.new('RGB',(128,128),'orange').save(image,format='PNG')
            project = client.post('/api/mobile/projects',headers=headers,files={'image':('own.png',image.getvalue(),'image/png')}).json()
            route = '/api/mobile/concepts/'+project['concepts'][0]['id']+'/model'
            body = {'engine':'trellis-2','idempotencyKey':'acceptance-model'}
            self.assertEqual(client.post(route,headers=headers,json=body).status_code,402)
            self.assertEqual(queued,[])
            with patch.object(rc,'subscriber',return_value=info):
                purchase = client.post('/api/mobile/purchases/revenuecat',headers=headers,json={'productId':PACK,'transactionId':'pack-acceptance'})
                self.assertEqual(purchase.status_code,200)
                self.assertEqual(purchase.json()['available'],200)
                job = client.post(route,headers=headers,json=body)
                self.assertEqual(job.status_code,200,job.text)
                self.assertEqual(job.json()['cost'],35)
                self.assertEqual(self.balance(),165)
                self.assertEqual(client.post(route,headers=headers,json=body).json()['id'],job.json()['id'])
                self.assertEqual(len(queued),1)
                with patch.object(mobile.jobs,'submit',return_value='provider-acceptance'), patch.object(mobile.jobs,'get_job',return_value={'stage':'done','progress':100,'message':'Ready','assets':[{'id':'acceptance-model','name':'Own model'}]}):
                    fn,args = queued.pop(); fn(*args)
                result = client.get('/api/mobile/jobs/'+job.json()['id'],headers=headers).json()
                self.assertEqual(result['charged'],35)
                self.assertEqual(client.post('/api/mobile/purchases/revenuecat/sync',headers=headers).json()['available'],165)
                self.assertEqual(client.post('/api/mobile/purchases/revenuecat/sync',headers=headers).json()['available'],165)
            with patch.object(identity,'verify_token',return_value={'uid':'bob','firebase':{'sign_in_provider':'password'}}):
                self.assertEqual(client.get('/api/mobile/wallet',headers=headers).json()['available'],0)
                self.assertEqual(client.get('/api/mobile/jobs/'+job.json()['id'],headers=headers).status_code,404)
            self.assertEqual(client.get('/api/mobile/wallet').status_code,401)
        lease = mobile._process_leases.pop(str(mobile.DB_PATH.resolve()),None)
        if lease: lease.close()

    def test_authenticated_claim_uses_server_customer_and_product(self):
        with patch.object(rc,'subscriber',return_value=self.info()) as fetch:
            self.assertEqual(self.claim().status_code,200)
            fetch.assert_called_once_with('firebase:alice')
        self.assertEqual(self.balance(),850)
        self.assertEqual(self.balance('bob'),0)
    def test_forged_product_or_transaction_never_grants(self):
        with patch.object(rc,'subscriber',return_value=self.info()):
            self.assertEqual(self.claim(tid='forged').status_code,409)
            self.assertEqual(self.claim(product=PACK).status_code,409)
        self.assertEqual(self.balance(),0)
    def test_deferred_switch_uses_actual_subscription_not_selected_product(self):
        with patch.object(rc,'subscriber',return_value=self.info()):
            self.assertEqual(self.claim().status_code,200)
            # Old iOS versions paired a weekly selection with the existing monthly transaction.
            self.assertEqual(self.claim(product=WEEK).status_code,200)
            self.assertEqual(self.claim(product=WEEK).status_code,200)
        self.assertEqual(self.balance(),850)
        with mobile.connect() as c:
            self.assertEqual(c.execute('SELECT COUNT(*) FROM ledger').fetchone()[0],1)
    def test_deferred_switch_never_credits_unverified_selected_plan(self):
        with patch.object(rc,'subscriber',return_value=self.info()):
            self.assertEqual(self.claim(product=WEEK).status_code,200)
        self.assertEqual(self.balance(),850)
        with patch.object(rc,'subscriber',return_value={'non_subscriptions':{PACK:[self.item()]}}):
            self.assertEqual(self.claim(product=WEEK,tid='other').status_code,409)
    def test_delivered_receipt_acknowledged_after_provider_snapshot_moves_on(self):
        self.webhook(self.event())
        with patch.object(rc,'subscriber',return_value=self.info(item=self.item('renewed'))):
            self.assertEqual(self.claim().status_code,200)
            self.assertEqual(self.claim(product=WEEK).status_code,200)
            self.assertEqual(self.claim(product=PACK).status_code,409)
            with patch.object(identity,'verify_token',return_value={'uid':'bob','firebase':{'sign_in_provider':'password'}}):
                self.assertEqual(self.claim().status_code,409)
        self.assertEqual(self.balance(),850)
        self.assertEqual(self.balance('bob'),0)
        with patch.object(mobile,'IS_PRODUCTION',True),patch.object(rc,'subscriber',return_value={}):
            with self.assertRaises(Exception) as error:
                rc.sync_customer('firebase:alice',(MONTH,'apple-1'))
            self.assertEqual(error.exception.status_code,409)
    def test_refunded_receipt_never_acknowledged_as_delivered(self):
        self.webhook(self.event())
        with patch.object(rc,'subscriber',return_value=self.info(item=self.item(refunded_at='2026-09-13'))):
            self.assertEqual(self.claim(product=WEEK).status_code,409)
        with patch.object(rc,'subscriber',return_value={}):
            self.assertEqual(self.claim().status_code,409)
        self.assertEqual(self.balance(),0)
    def test_no_identity_or_failed_verification_never_grants(self):
        self.assertEqual(self.client.post('/api/mobile/purchases/revenuecat/sync').status_code,401)
        with patch.dict(os.environ,{'REVENUECAT_API_KEY':''}):self.assertEqual(self.claim().status_code,503)
        self.assertEqual(self.balance(),0)
    def test_claim_restore_and_webhook_share_idempotency(self):
        with patch.object(rc,'subscriber',return_value=self.info()):
            first = self.claim()
            self.assertEqual(first.status_code,200)
            self.assertEqual(first.json()['purchaseCredit'],850)
            self.assertEqual(first.json()['purchaseTokens'],850)
            self.assertEqual(first.json()['purchaseReceiptID'],'SANDBOX:apple-1')
            repeat = self.claim()
            self.assertEqual(repeat.status_code,200)
            self.assertEqual(repeat.json()['purchaseCredit'],0)
            self.assertEqual(repeat.json()['purchaseTokens'],850)
            self.assertEqual(self.client.post('/api/mobile/purchases/revenuecat/sync',headers=self.auth).status_code,200)
        self.assertEqual(self.webhook(self.event()).status_code,200)
        self.assertEqual(self.balance(),850)
    def test_renewal_credits_once_with_new_transaction(self):
        for tid in ('apple-1','apple-2','apple-2'):
            self.assertEqual(self.webhook(self.event(tid,type='RENEWAL')).status_code,200)
        self.assertEqual(self.balance(),1700)
    def test_restore_does_not_give_existing_transaction_to_another_user(self):
        rc.settle('firebase:alice',MONTH,'apple-1','SANDBOX')
        with self.assertRaises(Exception) as error:rc.settle('firebase:bob',MONTH,'apple-1','SANDBOX')
        self.assertEqual(error.exception.status_code,409)
        self.assertEqual(self.balance('bob'),0)
    def test_refund_before_or_after_purchase_is_idempotent(self):
        self.webhook(self.event())
        refund=self.event(type='CANCELLATION',cancel_reason='CUSTOMER_SUPPORT')
        self.webhook(refund);self.webhook(refund);self.webhook(self.event())
        self.assertEqual(self.balance(),0)
        self.webhook(self.event('apple-2',type='CANCELLATION',cancel_reason='CUSTOMER_SUPPORT'))
        self.webhook(self.event('apple-2'))
        self.assertEqual(self.balance(),0)
    def test_cancel_and_expiration_do_not_erase_rollover_tokens(self):
        self.webhook(self.event())
        self.webhook(self.event(type='CANCELLATION',cancel_reason='UNSUBSCRIBE'))
        self.webhook(self.event(type='EXPIRATION'))
        self.assertEqual(self.balance(),850)
    def test_sandbox_rejected_in_production_even_if_enabled(self):
        with patch.object(mobile,'IS_PRODUCTION',True),patch.object(rc,'subscriber',return_value=self.info()):
            self.assertEqual(self.claim().status_code,403)
            self.assertEqual(self.webhook(self.event()).status_code,403)
        self.assertEqual(self.balance(),0)
    def test_webhook_auth_app_and_store_must_match(self):
        self.assertEqual(self.webhook(self.event(),header='forged').status_code,401)
        self.assertEqual(self.webhook(self.event(app_id='other')).status_code,422)
        self.assertEqual(self.webhook(self.event(store='TEST_STORE')).status_code,422)
        self.assertEqual(self.balance(),0)
    def test_trial_promotional_family_or_missing_environment_never_grants(self):
        for invalid in ({'period_type':'trial'},{'store':'promotional'},{'ownership_type':'FAMILY_SHARED'},{'is_sandbox':None}):
            with patch.object(rc,'subscriber',return_value=self.info(item=self.item(**invalid))):
                self.assertEqual(self.claim().status_code,409)
        self.assertEqual(self.balance(),0)
    def test_topup_restores_all_verified_transactions(self):
        info={'subscriptions':{},'non_subscriptions':{PACK:[self.item('p1'),self.item('p2')]}}
        with patch.object(rc,'subscriber',return_value=info):
            purchase = self.claim(product=PACK,tid='p1')
            self.assertEqual(purchase.status_code,200)
            self.assertEqual(purchase.json()['purchaseCredit'],200)
            self.assertEqual(purchase.json()['purchaseTokens'],200)
            self.client.post('/api/mobile/purchases/revenuecat/sync',headers=self.auth)
            self.client.post('/api/mobile/purchases/revenuecat/sync',headers=self.auth)
        self.assertEqual(self.balance(),400)
    def test_live_confirmed_purchase_qualifies_for_paid_access(self):
        self.webhook(self.event(environment='PRODUCTION'))
        self.assertEqual(identity.require_paid('firebase:alice'),'firebase:alice')
        self.assertEqual(self.balance(),850)
    def test_verified_refund_debt_offsets_next_purchase(self):
        self.webhook(self.event())
        with mobile.connect() as c:c.execute('UPDATE users SET paid=50 WHERE id=?',('firebase:alice',))
        self.webhook(self.event(type='CANCELLATION',cancel_reason='CUSTOMER_SUPPORT'))
        self.assertEqual(self.balance(),-800)
        self.webhook(self.event('apple-2'))
        self.assertEqual(self.balance(),50)

if __name__=='__main__':unittest.main()
