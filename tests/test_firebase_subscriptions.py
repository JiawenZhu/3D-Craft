import os
import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from server.firebase_subscriptions import PLANS, expire_allowance, subscription_transition, verified_subscriptions
from server.firebase_billing import CloudBilling
from server.firebase_webhooks import reconcile_webhook, APP_ID

WEEK='craft.creator.weekly.v1'; MONTH='craft.creator.monthly.v1'
class SubscriptionTests(unittest.TestCase):
    def purchase(self, **changes):
        return dict(dict(product=WEEK, transaction='1', environment='PRODUCTION', purchasedAt=100, expiresAt=200, refund=False, superseded=False), **changes)
    def test_new_purchase_retry_and_spending_do_not_refill(self):
        p=self.purchase();receipt,wallet,grant=subscription_transition(None,{'available':200},'alice',p,150)
        self.assertEqual((wallet['available'],wallet['subscriptionAvailable'],grant),(200,250,250))
        wallet['subscriptionAvailable']=70
        _,wallet,grant=subscription_transition(receipt,wallet,'alice',p,151)
        self.assertEqual((wallet['available'],wallet['subscriptionAvailable'],grant),(200,70,0))
    def test_renewal_replaces_unused_allowance_and_keeps_packs(self):
        _,wallet,_=subscription_transition(None,{'available':1200},'alice',self.purchase(),150)
        wallet['subscriptionAvailable']=30
        _,wallet,grant=subscription_transition(None,wallet,'alice',self.purchase(transaction='2',purchasedAt=200,expiresAt=300),201)
        self.assertEqual((wallet['available'],wallet['subscriptionAvailable'],grant),(1200,250,250))
    def test_expiration_without_notification_keeps_packs(self):
        receipt,wallet,_=subscription_transition(None,{'available':500},'alice',self.purchase(),150)
        self.assertEqual(expire_allowance(wallet,199)['subscriptionAvailable'],250)
        expired=expire_allowance(wallet,200)
        self.assertEqual((expired['available'],expired['subscriptionAvailable']),(500,0))
        _,expired,grant=subscription_transition(receipt,expired,'alice',self.purchase(),201)
        self.assertEqual((expired['subscriptionAvailable'],grant),(0,0))
    def test_expired_first_delivery_does_not_award_old_allowance(self):
        receipt,wallet,grant=subscription_transition(None,{},'alice',self.purchase(),201)
        self.assertEqual(grant,0);self.assertEqual(receipt['creditedTokens'],0)
    def test_upgrade_replaces_weekly_and_delayed_weekly_cannot_override(self):
        p=self.purchase();receipt,wallet,_=subscription_transition(None,{'available':200},'alice',p,150)
        monthly=self.purchase(product=MONTH,transaction='2',purchasedAt=160,expiresAt=500)
        _,wallet,grant=subscription_transition(None,wallet,'alice',monthly,161)
        self.assertEqual((wallet['subscriptionAvailable'],grant),(850,850))
        _,wallet,grant=subscription_transition(receipt,wallet,'alice',p,162)
        self.assertEqual((wallet['subscriptionAvailable'],grant,wallet['available']),(850,0,200))
    def test_current_refund_removes_only_plan_and_cannot_regrant(self):
        p=self.purchase();r,w,_=subscription_transition(None,{'available':500},'alice',p,150)
        r,w,_=subscription_transition(r,w,'alice',self.purchase(refund=True),151)
        self.assertEqual((w['available'],w['subscriptionAvailable']),(500,0))
        _,w,grant=subscription_transition(r,w,'alice',p,152)
        self.assertEqual((w['subscriptionAvailable'],grant),(0,0))
    def test_old_refund_does_not_remove_new_period(self):
        r,w,_=subscription_transition(None,{},'alice',self.purchase(),150)
        _,w,_=subscription_transition(None,w,'alice',self.purchase(transaction='2',purchasedAt=200,expiresAt=300),201)
        _,w,_=subscription_transition(r,w,'alice',self.purchase(refund=True),202)
        self.assertEqual(w['subscriptionAvailable'],250)
    def test_cancellation_and_extension_do_not_create_new_tokens(self):
        r,w,_=subscription_transition(None,{},'alice',self.purchase(),150)
        w['subscriptionAvailable']=40
        _,w,grant=subscription_transition(r,w,'alice',self.purchase(expiresAt=220),151)
        self.assertEqual((w['subscriptionAvailable'],w['subscriptionExpiresAt'],grant),(40,220,0))
    def test_receipt_cannot_transfer_or_change_product(self):
        p=self.purchase();r,w,_=subscription_transition(None,{},'alice',p,150)
        for uid,purchase in [('bob',p),('alice',self.purchase(product=MONTH))]:
            with self.assertRaises(HTTPException):subscription_transition(r,w,uid,purchase,151)
    def test_provider_dates_environment_trial_and_ownership_are_validated(self):
        valid=dict(store_transaction_id='1',store='app_store',is_sandbox=False,period_type='normal',purchase_date='2026-01-01T00:00:00Z',expires_date='2026-01-08T00:00:00Z')
        def parse(item):return list(verified_subscriptions({'subscriptions':{WEEK:item}},2_000_000_000))
        self.assertEqual(len(parse(valid)),1)
        for patch_ in [dict(store='stripe'),dict(is_sandbox='false'),dict(period_type='trial'),dict(ownership_type='FAMILY_SHARED'),dict(purchase_date='bad'),dict(expires_date=None),dict(purchase_date='2026-01-01T00:00:00'),dict(purchase_date='2040-01-01T00:00:00Z')]:
            self.assertEqual(parse(dict(valid,**patch_)),[])
        with patch.dict(os.environ,{'CRAFT_REVENUECAT_SANDBOX':'0'}):self.assertEqual(parse(dict(valid,is_sandbox=True)),[])
    def test_deleted_account_cannot_receive_renewal(self):
        db=Mock();db.collection.return_value.document.return_value.get.return_value.exists=True
        with patch('server.firebase_billing.firestore.transactional',side_effect=lambda f:f):
            with self.assertRaises(HTTPException):CloudBilling(db).settle_plan('alice',self.purchase())
        db.transaction.return_value.set.assert_not_called()

class WebhookTests(unittest.TestCase):
    def test_requires_secret_and_never_trusts_event_amounts(self):
        db=Mock();db.collection.return_value.document.return_value.get.return_value.exists=False
        payload={'event':{'type':'RENEWAL','app_id':APP_ID,'store':'APP_STORE','environment':'PRODUCTION','app_user_id':'alice','tokens':999999}}
        with patch.dict(os.environ,{'REVENUECAT_WEBHOOK_AUTHORIZATION':'test-secret'}):
            with self.assertRaises(HTTPException):reconcile_webhook(db,payload,'wrong')
            with patch('server.firebase_webhooks.firebase_app'),patch('server.firebase_webhooks.auth.get_user'),patch('server.firebase_webhooks.CloudBilling') as billing:
                self.assertEqual(reconcile_webhook(db,payload,'test-secret'),{'received':True})
                billing.return_value.sync.assert_called_once_with('alice')
    def test_deleted_customer_notification_is_acknowledged_without_recreation(self):
        db=Mock();db.collection.return_value.document.return_value.get.return_value.exists=True
        payload={'event':{'type':'RENEWAL','app_id':APP_ID,'store':'APP_STORE','environment':'PRODUCTION','app_user_id':'deleted'}}
        with patch.dict(os.environ,{'REVENUECAT_WEBHOOK_AUTHORIZATION':'test-secret'}),patch('server.firebase_webhooks.CloudBilling') as billing:
            self.assertTrue(reconcile_webhook(db,payload,'test-secret')['ignored'])
            billing.assert_not_called()

if __name__=='__main__':unittest.main()
