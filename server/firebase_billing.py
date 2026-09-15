"""Verified consumable delivery. Production and Apple sandbox balances never mix.

Only RevenueCat-confirmed App Store transactions may write this ledger. Cloud
subscription expiry/renewals remain a separate unfinished release requirement.
"""
import hashlib
import os
import time
from urllib.parse import quote
import requests
from fastapi import HTTPException
from firebase_admin import firestore

PACKS = {'craft.credits.small.v1': 200, 'craft.credits.medium.v1': 500,
         'craft.credits.large.v1': 1200}


def subscriber(uid):
    key = os.getenv('REVENUECAT_API_KEY', '')
    if not key:
        raise HTTPException(503, 'Purchase verification is temporarily unavailable. Your purchase is saved; do not buy again.')
    try:
        response = requests.get('https://api.revenuecat.com/v1/subscribers/' + quote(uid, safe=''),
                                headers={'Authorization': 'Bearer ' + key}, timeout=20)
        response.raise_for_status()
        info = response.json()['subscriber']
        if not isinstance(info, dict): raise ValueError()
        return info
    except (requests.RequestException, ValueError, KeyError):
        raise HTTPException(503, 'Your purchase is waiting for verification. Please retry; do not buy again.') from None


def verified_packs(info):
    for product, items in info.get('non_subscriptions', {}).items():
        if product not in PACKS or not isinstance(items, list): continue
        for item in items:
            if not isinstance(item, dict): continue
            tid = item.get('store_transaction_id')
            if (not isinstance(tid, str) or not tid or len(tid) > 150
                    or item.get('store') != 'app_store'
                    or type(item.get('is_sandbox')) is not bool
                    or item.get('ownership_type', 'PURCHASED') != 'PURCHASED'):
                continue
            environment = 'SANDBOX' if item['is_sandbox'] else 'PRODUCTION'
            if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1': continue
            yield dict(product=product, transaction=tid, environment=environment,
                       refund=bool(item.get('refunded_at')))


def transition(prior, uid, purchase):
    """Pure receipt transition; called inside a Firestore transaction."""
    if prior and (prior['ownerId'] != uid or prior['product'] != purchase['product']):
        raise HTTPException(409, 'This purchase belongs to another account or product.')
    record = dict(prior or dict(ownerId=uid, product=purchase['product'],
        transaction=purchase['transaction'], environment=purchase['environment'],
        tokens=PACKS[purchase['product']], granted=False, refunded=False))
    delta = 0
    if purchase['refund'] and not record['refunded']:
        delta = -record['tokens'] if record['granted'] else 0
        record['refunded'] = True
    elif not purchase['refund'] and not record['granted'] and not record['refunded']:
        delta = record['tokens']; record['granted'] = True
    return record, delta


class CloudBilling:
    def __init__(self, db): self.db = db

    def private(self, uid, name):
        return self.db.collection('users').document(uid).collection('private').document(name)

    def settle(self, uid, purchase):
        receipt_id = purchase['environment'] + ':' + purchase['transaction']
        key = hashlib.sha256(('APP_STORE:' + receipt_id).encode()).hexdigest()
        receipt_ref = self.db.collection('billingReceipts').document(key)
        wallet_name = 'sandboxWallet' if purchase['environment'] == 'SANDBOX' else 'wallet'
        wallet_ref = self.private(uid, wallet_name)
        ledger_ref = wallet_ref.collection('entries').document(key + (':refund' if purchase['refund'] else ':grant'))
        @firestore.transactional
        def deliver(tx):
            if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
                raise HTTPException(403, 'This account is being deleted.')
            receipt = receipt_ref.get(transaction=tx)
            snapshot = wallet_ref.get(transaction=tx)
            prior = receipt.to_dict() if receipt.exists else None
            record, delta = transition(prior, uid, purchase)
            data = snapshot.to_dict() if snapshot.exists else {}
            if delta:
                tx.set(wallet_ref, dict(available=int(data.get('available', 0)) + delta,
                    reserved=int(data.get('reserved', 0)), freeConceptTokens=int(data.get('freeConceptTokens', 0)),
                    environment=purchase['environment']), merge=True)
                tx.create(ledger_ref, dict(id=key + (':refund' if purchase['refund'] else ':grant'),
                    amount=delta, kind='purchase_refund' if purchase['refund'] else
                    ('sandbox_purchase' if purchase['environment'] == 'SANDBOX' else 'verified_purchase'),
                    product=purchase['product'], createdAt=time.time()))
            tx.set(receipt_ref, record)
            return dict(delta=delta, tokens=record['tokens'], refunded=record['refunded'], receiptID=receipt_id)
        return deliver(self.db.transaction())

    def wallet(self, uid, environment=None):
        if environment is None:
            context = self.private(uid, 'billingContext').get()
            environment = (context.to_dict() or {}).get('environment', 'PRODUCTION') if context.exists else 'PRODUCTION'
        # Display context does not grant production spending access. A generation
        # service must explicitly select the production wallet, never this context.
        if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1': environment = 'PRODUCTION'
        ref = self.private(uid, 'sandboxWallet' if environment == 'SANDBOX' else 'wallet')
        snapshot = ref.get(); data = snapshot.to_dict() if snapshot.exists else {}
        entries = ref.collection('entries').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(100).stream()
        return dict(available=int(data.get('available', 0)), reserved=int(data.get('reserved', 0)),
                    freeConceptTokens=int(data.get('freeConceptTokens', 0)),
                    ledger=[item.to_dict() for item in entries], environment=environment)

    def sync(self, uid, expected=None):
        if expected and expected[0] not in PACKS:
            raise HTTPException(503, 'Subscription Token delivery is not available yet. Your purchase is saved; do not buy again.')
        records = list(verified_packs(subscriber(uid)))
        if expected:
            records = [p for p in records if (p['product'], p['transaction']) == expected]
            if not records:
                raise HTTPException(409, 'RevenueCat has not confirmed this purchase for your account yet. Retry shortly; do not buy again.')
        results = [(p, self.settle(uid, p)) for p in records]
        if expected:
            purchase, result = results[-1]
            if result['refunded']: raise HTTPException(409, 'This purchase was refunded; Tokens cannot be added.')
            environment = purchase['environment']
            @firestore.transactional
            def set_context(tx):
                if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
                    raise HTTPException(403, 'This account is being deleted.')
                tx.set(self.private(uid, 'billingContext'), {'environment': environment})
            set_context(self.db.transaction())
            wallet = self.wallet(uid, environment)
            wallet.update(purchaseCredit=max(0, result['delta']), purchaseTokens=result['tokens'],
                          purchaseReceiptID=result['receiptID'])
            return wallet
        return self.wallet(uid)
