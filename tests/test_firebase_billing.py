import os
import unittest
from unittest.mock import Mock, patch
from fastapi import HTTPException
from server.firebase_billing import PACKS, CloudBilling, transition, verified_packs

class CloudPackTests(unittest.TestCase):
    def test_deleting_account_cannot_be_recreated_by_receipt_retry(self):
        db=Mock()
        db.collection.return_value.document.return_value.get.return_value.exists=True
        with patch('server.firebase_billing.firestore.transactional',side_effect=lambda fn:fn):
            with self.assertRaises(HTTPException) as error:
                CloudBilling(db).settle('alice',self.purchase())
        self.assertEqual(error.exception.status_code,403)
        db.transaction.return_value.set.assert_not_called()

    def purchase(self, **kwargs):
        return dict(product='craft.credits.small.v1', transaction='1001', environment='PRODUCTION', refund=False, **kwargs)

    def test_retry_does_not_credit_twice(self):
        p=self.purchase();receipt,delta=transition(None,'alice',p)
        self.assertEqual(delta,200)
        self.assertEqual(transition(receipt,'alice',p)[1],0)

    def test_receipt_cannot_move_to_another_account_or_product(self):
        p=self.purchase();receipt,_=transition(None,'alice',p)
        with self.assertRaises(HTTPException): transition(receipt,'bob',p)
        with self.assertRaises(HTTPException): transition(receipt,'alice',dict(p,product='craft.credits.large.v1'))

    def test_refund_once_and_cannot_regrant(self):
        p=self.purchase();receipt,_=transition(None,'alice',p)
        receipt,delta=transition(receipt,'alice',dict(p,refund=True));self.assertEqual(delta,-200)
        self.assertEqual(transition(receipt,'alice',dict(p,refund=True))[1],0)
        self.assertEqual(transition(receipt,'alice',p)[1],0)

    def test_refund_before_grant_never_credits(self):
        p=self.purchase();receipt,delta=transition(None,'alice',dict(p,refund=True))
        self.assertEqual(delta,0);self.assertEqual(transition(receipt,'alice',p)[1],0)

    def test_amounts_are_server_catalog_not_client_input(self):
        for product,tokens in PACKS.items():
            self.assertEqual(transition(None,'alice',dict(self.purchase(),product=product,tokens=999999))[1],tokens)

    def test_requires_apple_verified_fields_and_explicit_sandbox_enablement(self):
        item=dict(store_transaction_id='1001',store='app_store',is_sandbox=False)
        def parse(record):return list(verified_packs({'non_subscriptions':{'craft.credits.small.v1':[record]}}))
        self.assertEqual(parse(item)[0]['environment'],'PRODUCTION')
        for bad in [dict(item,store='stripe'),dict(item,is_sandbox='false'),dict(item,store_transaction_id=None),dict(item,ownership_type='FAMILY_SHARED')]:
            self.assertEqual(parse(bad),[])
        with patch.dict(os.environ,{'CRAFT_REVENUECAT_SANDBOX':'0'}):self.assertEqual(parse(dict(item,is_sandbox=True)),[])
        with patch.dict(os.environ,{'CRAFT_REVENUECAT_SANDBOX':'1'}):self.assertEqual(parse(dict(item,is_sandbox=True))[0]['environment'],'SANDBOX')

class CloudReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.db = Mock()
        self.snapshot = self.db.collection.return_value.document.return_value.get.return_value
        self.snapshot.exists = False
        self.billing = CloudBilling(self.db)
        self.billing.settle = Mock(return_value=dict(delta=200, tokens=200, refunded=False, receiptID='SANDBOX:new'))
        self.billing.settle_plan = Mock(side_effect=HTTPException(409, 'This purchase belongs to another account or product.'))
        self.billing.wallet = Mock(return_value=dict(available=200, environment='SANDBOX'))
        self.pack = dict(product='craft.credits.small.v1', transaction='new', environment='SANDBOX', refund=False)
        self.plan = dict(product='craft.creator.weekly.v1', transaction='old', environment='SANDBOX', purchasedAt=1)
        for target, value in [('subscriber', {}), ('verified_packs', [self.pack]), ('verified_subscriptions', [self.plan])]:
            patcher = patch('server.firebase_billing.' + target, return_value=value)
            patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch('server.firebase_billing.firestore.transactional', side_effect=lambda fn: fn)
        patcher.start(); self.addCleanup(patcher.stop)

    def test_pack_claim_ignores_foreign_subscription_and_selects_credited_wallet(self):
        result = self.billing.sync('new-user', (self.pack['product'], 'new'))
        self.billing.settle_plan.assert_not_called()
        self.billing.settle.assert_called_once_with('new-user', self.pack)
        self.billing.wallet.assert_called_once_with('new-user', 'SANDBOX')
        self.db.transaction.return_value.set.assert_called_once_with(
            self.billing.private('new-user', 'billingContext'), {'environment': 'SANDBOX'})
        self.assertEqual(result['purchaseCredit'], 200)

    def test_restore_skips_history_owned_by_another_account(self):
        self.snapshot.exists = True
        self.snapshot.to_dict.return_value = dict(ownerId='old-user')
        result = self.billing.sync('new-user')
        self.billing.settle.assert_not_called()
        self.billing.settle_plan.assert_not_called()
        self.assertEqual(result['available'], 200)

    def test_explicit_foreign_claim_still_fails(self):
        self.billing.settle.side_effect = HTTPException(409, 'This purchase belongs to another account or product.')
        with self.assertRaises(HTTPException) as error:
            self.billing.sync('new-user', (self.pack['product'], 'new'))
        self.assertEqual(error.exception.status_code, 409)
        self.db.transaction.return_value.set.assert_not_called()

    def test_unrelated_settlement_errors_are_not_silenced(self):
        self.billing.settle.side_effect = HTTPException(403, 'This account is being deleted.')
        with self.assertRaises(HTTPException) as error:
            self.billing.sync('new-user')
        self.assertEqual(error.exception.status_code, 403)

    def test_retained_verified_pack_acknowledges_animation_without_second_grant(self):
        receipt = dict(self.pack, ownerId='new-user', granted=True, refunded=False, tokens=200)
        receipt_snapshot = Mock(exists=True)
        receipt_snapshot.to_dict.return_value = receipt
        absent = Mock(exists=False)
        # Production receipt absent, sandbox receipt retained, account not deleted.
        self.db.collection.return_value.document.return_value.get.side_effect = [absent, receipt_snapshot, absent]
        with patch('server.firebase_billing.verified_packs', return_value=[]), \
             patch('server.firebase_billing.verified_subscriptions', return_value=[]), \
             patch.dict(os.environ, {'CRAFT_REVENUECAT_SANDBOX': '1'}):
            result = self.billing.sync('new-user', (self.pack['product'], 'new'))
        self.billing.settle.assert_not_called()
        self.assertEqual(result['purchaseCredit'], 0)
        self.assertEqual(result['purchaseTokens'], 200)
        self.assertEqual(result['purchaseReceiptID'], 'SANDBOX:new')

    def test_new_user_gets_50_welcome_tokens_one_time(self):
        wallet_ref = Mock()
        tx = Mock()
        initial_data = {}
        updated = self.billing.ensure_welcome('new_user_123', initial_data, wallet_ref, tx)
        self.assertEqual(updated['available'], 50)
        self.assertTrue(updated['welcomeTokensGranted'])
        tx.set.assert_any_call(wallet_ref, {
            'available': 50,
            'welcomeTokensGranted': True,
            'reserved': 0,
            'freeConceptTokens': 0,
        }, merge=True)

    def test_existing_welcome_tokens_not_regranted(self):
        wallet_ref = Mock()
        tx = Mock()
        initial_data = {'available': 120, 'welcomeTokensGranted': True}
        updated = self.billing.ensure_welcome('existing_user_456', initial_data, wallet_ref, tx)
        self.assertEqual(updated['available'], 120)
        tx.set.assert_not_called()

if __name__=='__main__':unittest.main()
