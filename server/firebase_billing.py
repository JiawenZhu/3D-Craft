"""Verified purchases with isolated production/sandbox wallets and expiring plans."""
import hashlib
import os
import time
from urllib.parse import quote
import requests
from fastapi import HTTPException
from firebase_admin import firestore
from .firebase_subscriptions import PLANS, verified_subscriptions, expire_allowance, subscription_transition

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
    def __init__(self, db, clock=None):
        self.db = db
        self.now = clock or time.time

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
                    product=purchase['product'], createdAt=self.now()))
            tx.set(receipt_ref, record)
            return dict(delta=delta, tokens=record['tokens'], refunded=record['refunded'], receiptID=receipt_id)
        return deliver(self.db.transaction())

    def settle_plan(self, uid, purchase):
        receipt_id = purchase['environment'] + ':' + purchase['transaction']
        key = hashlib.sha256(('APP_STORE:' + receipt_id).encode()).hexdigest()
        receipt_ref = self.db.collection('billingReceipts').document(key)
        ref = self.private(uid, 'sandboxWallet' if purchase['environment'] == 'SANDBOX' else 'wallet')
        @firestore.transactional
        def deliver(tx):
            if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
                raise HTTPException(403, 'This account is being deleted.')
            receipt, snapshot = receipt_ref.get(transaction=tx), ref.get(transaction=tx)
            before = snapshot.to_dict() if snapshot.exists else {}
            now = self.now()
            record, after, grant = subscription_transition(receipt.to_dict() if receipt.exists else None, before, uid, purchase, now)
            old = int(before.get('subscriptionAvailable', 0))
            removed = old + grant - int(after.get('subscriptionAvailable', 0))
            tx.set(receipt_ref, record)
            tx.set(ref, after, merge=True)
            if removed:
                ident = key + ':period-close:' + str(int(now * 1_000_000))
                tx.create(ref.collection('entries').document(ident), dict(id=ident, amount=-removed,
                    kind='subscription_refund' if purchase['refund'] else 'subscription_expiry',
                    product=before.get('subscriptionProduct'), createdAt=now))
            if grant:
                ident = key + ':grant'
                tx.create(ref.collection('entries').document(ident), dict(id=ident, amount=grant,
                    kind='sandbox_purchase' if purchase['environment']=='SANDBOX' else 'verified_purchase',
                    product=purchase['product'], createdAt=now))
            visible_tokens = record.get('creditedTokens', 0) if after.get('subscriptionTransaction') == receipt_id and after.get('subscriptionExpiresAt', 0) > now and not purchase['superseded'] else 0
            return dict(delta=grant, tokens=visible_tokens, refunded=record['refunded'], receiptID=receipt_id)
        return deliver(self.db.transaction())

    def wallet(self, uid, environment=None):
        if environment is None:
            context = self.private(uid, 'billingContext').get()
            environment = (context.to_dict() or {}).get('environment', 'PRODUCTION') if context.exists else 'PRODUCTION'
        if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1': environment = 'PRODUCTION'
        ref = self.private(uid, 'sandboxWallet' if environment == 'SANDBOX' else 'wallet')
        @firestore.transactional
        def current(tx):
            if self.db.collection('accountDeletions').document(uid).get(transaction=tx).exists:
                raise HTTPException(403, 'This account is being deleted.')
            snap = ref.get(transaction=tx)
            before = snap.to_dict() if snap.exists else {}
            now = self.now(); data = expire_allowance(before, now)
            removed = int(before.get('subscriptionAvailable', 0)) - int(data.get('subscriptionAvailable', 0))
            if removed:
                tx.update(ref, {'subscriptionAvailable': 0})
                ident = hashlib.sha256((str(data.get('subscriptionTransaction')) + ':expire:' + str(data.get('subscriptionExpiresAt'))).encode()).hexdigest()
                tx.set(ref.collection('entries').document(ident), dict(id=ident, amount=-removed,
                    kind='subscription_expiry', product=data.get('subscriptionProduct'), createdAt=now))
            return data
        data = current(self.db.transaction())
        entries = ref.collection('entries').order_by('createdAt', direction=firestore.Query.DESCENDING).limit(100).stream()
        packs, allowance = int(data.get('available', 0)), int(data.get('subscriptionAvailable', 0))
        return dict(available=packs + allowance, packAvailable=packs, subscriptionAvailable=allowance,
                    subscriptionProduct=data.get('subscriptionProduct'), subscriptionExpiresAt=data.get('subscriptionExpiresAt'),
                    reserved=int(data.get('reserved', 0)), freeConceptTokens=int(data.get('freeConceptTokens', 0)),
                    ledger=[item.to_dict() for item in entries], environment=environment)

    def sync(self, uid, expected=None):
        if expected and expected[0] not in PACKS and expected[0] not in PLANS:
            raise HTTPException(422, 'Unknown purchase product.')
        info = subscriber(uid)
        records = list(verified_packs(info))
        records += sorted(verified_subscriptions(info, self.now()), key=lambda p:(p['purchasedAt'], PLANS[p['product']], p['transaction']))
        matched = None
        for purchase in records:
            is_plan = purchase['product'] in PLANS
            compatible = expected and (expected[0] == purchase['product'] or (expected[0] in PLANS and is_plan))
            matches = compatible and expected[1] == purchase['transaction']
            if expected and not is_plan and not matches: continue
            result = self.settle_plan(uid, purchase) if is_plan else self.settle(uid, purchase)
            if matches: matched = purchase, result
        if expected:
            if matched is None:
                # Latest-only provider snapshots may have moved to the next period.
                # A retained, owner-matched receipt acknowledges an earlier delivery.
                for environment in ('PRODUCTION', 'SANDBOX'):
                    if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1': continue
                    key = hashlib.sha256(('APP_STORE:' + environment + ':' + expected[1]).encode()).hexdigest()
                    snap = self.db.collection('billingReceipts').document(key).get()
                    prior = snap.to_dict() if snap.exists else None
                    compatible = prior and (prior['product']==expected[0] or prior['product'] in PLANS and expected[0] in PLANS)
                    if compatible and prior['ownerId']==uid and prior.get('granted') and not prior.get('refunded'):
                        matched = prior, dict(delta=0, tokens=0, refunded=False, receiptID=environment+':'+expected[1])
                        break
            if matched is None:
                raise HTTPException(409, 'RevenueCat has not confirmed this purchase for your account yet. Retry shortly; do not buy again.')
            purchase, result = matched
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
