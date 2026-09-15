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

if __name__=='__main__':unittest.main()
