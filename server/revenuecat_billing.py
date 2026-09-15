"""RevenueCat-confirmed Apple purchases. Client claims alone never mint Tokens.

The pull path supports local Apple-sandbox testing without exposing the Mac.
Authenticated webhooks deliver renewals while the app is closed in production.
"""
import hmac
import json
import os
import time
from urllib.parse import quote

import requests
from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field
from . import mobile
from .identity import require_account

router = APIRouter(tags=['RevenueCat billing'])
APP_ID = 'appb88bdcb0f7'
SUBSCRIPTION_PRODUCTS = frozenset(('craft.creator.weekly.v1', 'craft.creator.monthly.v1'))


def compatible_claim_product(requested, actual):
    # StoreKit can return the current subscription transaction when a change is
    # deferred. The verified transaction's product determines the grant, never
    # the selected button. Older clients persisted the selected product instead.
    return requested == actual or {requested, actual} <= SUBSCRIPTION_PRODUCTS


def already_delivered(owner, expected):
    """A verified ledger receipt remains valid after RC's latest-only snapshot moves on."""
    product, transaction = expected
    with mobile.connect() as c:
        if not c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='revenuecat_transactions'").fetchone():
            return False
        for environment in ('PRODUCTION', 'SANDBOX'):
            if not environment_allowed(environment):
                continue
            row = c.execute('SELECT * FROM revenuecat_transactions WHERE id=?',
                            ('revenuecat:APP_STORE:' + environment + ':' + transaction,)).fetchone()
            if (row and row['owner'] == owner and compatible_claim_product(product, row['product'])
                and row['granted'] and not row['refunded']):
                return True
    return False


def products():
    return {p['id']: p for p in mobile.PRODUCTS if p['id'].startswith('craft.')}


def environment_allowed(environment):
    return (environment == 'PRODUCTION' or
            (environment == 'SANDBOX' and not mobile.IS_PRODUCTION
             and os.getenv('CRAFT_REVENUECAT_SANDBOX') == '1'))


def subscriber(owner):
    key = os.getenv('REVENUECAT_API_KEY', '')
    if not key:
        raise HTTPException(503, 'Purchase verification is not configured. No Tokens have been added.')
    uid = owner.removeprefix('firebase:')
    if not owner.startswith('firebase:') or not uid:
        raise HTTPException(401, 'Sign in before restoring purchases.')
    try:
        response = requests.get('https://api.revenuecat.com/v1/subscribers/' + quote(uid, safe=''),
                                headers={'Authorization': 'Bearer ' + key}, timeout=15)
        response.raise_for_status()
        result = response.json()['subscriber']
        if not isinstance(result, dict):
            raise ValueError('Invalid customer response')
        return result
    except (requests.RequestException, ValueError, KeyError):
        raise HTTPException(503, 'RevenueCat could not confirm your purchase yet. Please restore again shortly; do not buy again.') from None


def records(info):
    for product, item in info.get('subscriptions', {}).items():
        if isinstance(item, dict):
            yield product, item, True
    for product, items in info.get('non_subscriptions', {}).items():
        for item in items:
            if isinstance(item, dict):
                yield product, item, False


def settle(owner, product, transaction, environment, *, refund=False, source='api'):
    """One grant per store transaction; refunds work before or after delivery."""
    offer = products().get(product)
    if not offer or not transaction or len(transaction) > 150:
        raise HTTPException(422, 'Unknown purchase product or transaction.')
    if not environment_allowed(environment):
        raise HTTPException(403, 'Sandbox purchases cannot fund this wallet.')
    key = 'revenuecat:APP_STORE:' + environment + ':' + transaction
    with mobile.connect() as c:
        c.execute('BEGIN IMMEDIATE')
        c.execute('CREATE TABLE IF NOT EXISTS revenuecat_transactions (id TEXT PRIMARY KEY, owner TEXT NOT NULL, product TEXT NOT NULL, tokens INTEGER NOT NULL, granted INTEGER NOT NULL DEFAULT 0, refunded INTEGER NOT NULL DEFAULT 0)')
        prior = c.execute('SELECT * FROM revenuecat_transactions WHERE id=?', (key,)).fetchone()
        if prior and (prior['owner'] != owner or prior['product'] != product):
            raise HTTPException(409, 'This transaction is already assigned to another account or product.')
        c.execute('INSERT OR IGNORE INTO users(id, token, paid, trial) VALUES(?, ?, 0, 0)', (owner, owner))
        if not prior:
            c.execute('INSERT INTO revenuecat_transactions(id,owner,product,tokens) VALUES(?,?,?,?)', (key, owner, product, offer['tokens']))
            prior = {'granted': 0, 'refunded': 0, 'tokens': offer['tokens']}
        delta = 0
        if refund and not prior['refunded']:
            delta = -prior['tokens'] if prior['granted'] else 0
            c.execute('UPDATE revenuecat_transactions SET refunded=1 WHERE id=?', (key,))
        elif not refund and not prior['granted'] and not prior['refunded']:
            delta = prior['tokens']
            c.execute('UPDATE revenuecat_transactions SET granted=1 WHERE id=?', (key,))
        if delta:
            # A refund debt offsets future top-ups if the Tokens were already spent.
            c.execute('UPDATE users SET paid=paid+? WHERE id=?', (delta, owner))
            kind = 'purchase_refund' if refund else ('verified_purchase' if environment == 'PRODUCTION' else 'sandbox_purchase')
            c.execute('INSERT INTO ledger VALUES(?,?,?,?,?,?)',
                      (key + (':refund' if refund else ':grant'), owner, kind, delta, time.time(),
                       json.dumps({'provider': 'revenuecat', 'product': product, 'transactionId': transaction,
                                   'environment': environment, 'realPayment': environment == 'PRODUCTION', 'source': source})))
        return {'delta': delta, 'refunded': bool(refund or prior['refunded'])}


def sync_customer(owner, expected=None):
    info = subscriber(owner)
    matched = False
    credited = 0
    for product, item, is_subscription in records(info):
        transaction = str(item.get('store_transaction_id') or '')
        if product not in products() or not transaction:
            continue
        if expected and (transaction != expected[1] or not compatible_claim_product(expected[0], product)):
            continue
        # Reject promotional, family-shared, trial and unknown environments.
        if (item.get('store') != 'app_store' or type(item.get('is_sandbox')) is not bool
            or item.get('ownership_type', 'PURCHASED') != 'PURCHASED'
            or (is_subscription and item.get('period_type') not in ('normal', 'intro'))):
            continue
        environment = 'SANDBOX' if item['is_sandbox'] else 'PRODUCTION'
        if not environment_allowed(environment):
            if expected: raise HTTPException(403, 'This test purchase cannot fund the current wallet.')
            continue
        result = settle(owner, product, transaction, environment, refund=bool(item.get('refunded_at')))
        credited += max(0, result['delta'])
        matched = not result['refunded'] or matched
    if expected and not matched and not already_delivered(owner, expected):
        raise HTTPException(409, 'RevenueCat has not confirmed this transaction for your account yet. Use Restore shortly; do not purchase again.')
    wallet = mobile.wallet(owner)
    if expected:
        # Presentation only: retries and already-delivered transactions return 0.
        wallet['purchaseCredit'] = credited
        for entry in wallet['ledger']:
            if entry['kind'] not in ('verified_purchase', 'sandbox_purchase'):
                continue
            receipt = json.loads(entry['data'])
            if receipt.get('transactionId') == expected[1] and compatible_claim_product(expected[0], receipt.get('product')):
                wallet['purchaseTokens'] = entry['amount']
                wallet['purchaseReceiptID'] = receipt['environment'] + ':' + expected[1]
                break
    return wallet


class PurchaseClaim(BaseModel):
    productId: str = Field(min_length=1, max_length=150)
    transactionId: str = Field(min_length=1, max_length=150)


@router.post('/api/mobile/purchases/revenuecat')
def verify_purchase(body: PurchaseClaim, owner=Depends(require_account)):
    return sync_customer(owner, (body.productId, body.transactionId))


@router.post('/api/mobile/purchases/revenuecat/sync')
def restore_purchases(owner=Depends(require_account)):
    return sync_customer(owner)


@router.post('/api/billing/revenuecat/webhook')
def webhook(payload: dict, authorization: str = Header(default='')):
    secret = os.getenv('REVENUECAT_WEBHOOK_AUTHORIZATION', '')
    if not secret:
        raise HTTPException(503, 'RevenueCat webhook is not configured.')
    if not hmac.compare_digest(authorization.encode(), secret.encode()):
        raise HTTPException(401, 'Invalid webhook authorization.')
    event = payload.get('event') or {}
    if not isinstance(event, dict): raise HTTPException(422, 'Invalid event.')
    if event.get('type') == 'TEST': return {'received': True}
    if event.get('app_id') != APP_ID or event.get('store') != 'APP_STORE':
        raise HTTPException(422, 'Event is not for the 3D Craft Apple app.')
    kind = event.get('type')
    refund = kind == 'CANCELLATION' and event.get('cancel_reason') == 'CUSTOMER_SUPPORT'
    if kind not in ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE') and not refund:
        return {'received': True, 'ignored': True}
    if event.get('is_family_share') or event.get('period_type') not in ('NORMAL', 'INTRO'):
        return {'received': True, 'ignored': True}
    if event.get('quantity', 1) != 1:
        raise HTTPException(422, 'Unsupported purchase quantity.')
    uid = event.get('app_user_id')
    if not isinstance(uid, str) or not uid or uid.startswith('$RCAnonymousID:'):
        raise HTTPException(409, 'Purchase must be associated with a signed-in 3D Craft account.')
    result = settle('firebase:' + uid, event.get('product_id'), str(event.get('transaction_id') or ''),
                    event.get('environment'), refund=refund, source='webhook')
    return {'received': True, **result}
