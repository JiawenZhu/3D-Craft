"""Server-created Stripe checkout and signed, idempotent credit delivery."""
import os
from decimal import Decimal
import json
import time
from fastapi import APIRouter, Depends, HTTPException, Request
from .identity import require_account, require_admin, require_claims, firebase_app
from pydantic import BaseModel, Field, StrictInt
from uuid import UUID
from .commerce import policy

router = APIRouter(prefix='/api/billing', tags=['billing'])

def ready():
    return bool(os.getenv('STRIPE_SECRET_KEY') and os.getenv('STRIPE_WEBHOOK_SECRET')
                and os.getenv('CRAFT_PAID_GENERATION_READY') == '1')

def stripe_client():
    import stripe
    stripe.api_key = os.getenv('STRIPE_SECRET_KEY')
    return stripe

@router.get('/account')
def account(owner=Depends(require_account), claims=Depends(require_claims)):
    from . import mobile
    return {**mobile.wallet(owner), 'isAdmin': claims.get('admin') is True, 'checkoutAvailable': ready(), 'pack': policy()['topups'][0]}

@router.post('/checkout')
def checkout(owner=Depends(require_account)):
    if not ready():
        raise HTTPException(503, 'Credit purchases are not available yet. Please try again later.')
    pack = policy()['topups'][0]
    # Prices, grants and redirects are server-controlled, never client input.
    origin = os.getenv('CRAFT_PUBLIC_URL', 'https://3d-craft.web.app').rstrip('/')
    if not origin.startswith('https://'):
        raise HTTPException(503, 'Secure checkout return URL is not configured.')
    session = stripe_client().checkout.Session.create(
        mode='payment', client_reference_id=owner,
        line_items=[{'price_data': {'currency': 'usd', 'unit_amount': int(Decimal(pack['usd'])*100),
                     'product_data': {'name': '3D Craft · 200 credits'}}, 'quantity': 1}],
        metadata={'owner': owner, 'product': pack['id']},
        success_url=origin+'/?checkout=success', cancel_url=origin+'/?checkout=cancelled')
    return {'url': session.url}


def fulfill(session):
    """The signed event is still checked against the immutable server offer."""
    from . import mobile
    pack = policy()['topups'][0]
    meta = session.get('metadata') or {}
    owner = meta.get('owner', '')
    if (session.get('payment_status') != 'paid' or session.get('mode') != 'payment'
        or session.get('currency') != 'usd' or session.get('amount_total') != int(Decimal(pack['usd'])*100)
        or meta.get('product') != pack['id'] or session.get('client_reference_id') != owner
        or not owner.startswith('firebase:') or not session.get('id')):
        raise HTTPException(422, 'Payment does not match the credit offer.')
    key = 'stripe:' + session['id']
    with mobile.connect() as c:
        c.execute('BEGIN IMMEDIATE')
        if not c.execute('SELECT 1 FROM users WHERE id=?', (owner,)).fetchone():
            raise HTTPException(409, 'Payment account is missing.')
        existing = c.execute('SELECT owner FROM purchases WHERE transaction_id=?', (key,)).fetchone()
        if existing:
            if existing['owner'] != owner: raise HTTPException(409, 'Payment account mismatch.')
            return
        c.execute('INSERT INTO purchases VALUES(?,?,?)', (key, owner, pack['id']))
        c.execute('UPDATE users SET paid=paid+? WHERE id=?', (pack['credits'], owner))
        c.execute('INSERT INTO ledger VALUES(?,?,?,?,?,?)', (key, owner, 'verified_purchase', pack['credits'], time.time(), json.dumps({'provider':'stripe','realPayment':True})))

@router.post('/stripe/webhook')
async def webhook(request: Request):
    secret = os.getenv('STRIPE_WEBHOOK_SECRET')
    if not secret: raise HTTPException(503, 'Billing webhook is not configured.')
    raw = await request.body()
    try:
        event = stripe_client().Webhook.construct_event(raw, request.headers.get('stripe-signature', ''), secret)
    except Exception:
        raise HTTPException(400, 'Invalid payment signature.') from None
    # Test payments cannot fund a production wallet.
    from .config import IS_PRODUCTION
    if IS_PRODUCTION and not event.get('livemode'):
        raise HTTPException(400, 'Test payments cannot grant production credits.')
    if event['type'] in ('checkout.session.completed', 'checkout.session.async_payment_succeeded'):
        obj = event['data']['object']
        if obj.get('payment_status') == 'paid': fulfill(obj)
    return {'received': True}


class CreditGrant(BaseModel):
    recipientEmail: str = Field(min_length=3, max_length=254)
    credits: StrictInt = Field(gt=0, le=100000)
    reason: str = Field(min_length=1, max_length=500)
    requestId: UUID

def recipient_uid(email):
    from firebase_admin import auth
    try:
        user = auth.get_user_by_email(email.strip(), app=firebase_app())
    except auth.UserNotFoundError:
        raise HTTPException(404, 'No account has that email. Ask the recipient to register first.') from None
    if user.disabled:
        raise HTTPException(409, 'This account is disabled.')
    return user.uid

@router.post('/admin/credits')
def grant_credits(grant: CreditGrant, actor=Depends(require_admin)):
    from . import mobile
    uid = recipient_uid(grant.recipientEmail)
    owner = 'firebase:' + uid
    key = 'admin-grant:' + str(grant.requestId)
    reason = grant.reason.strip()
    if not reason:
        raise HTTPException(422, 'Enter a reason for this grant.')
    with mobile.connect() as c:
        c.execute('BEGIN IMMEDIATE')
        c.execute('CREATE TABLE IF NOT EXISTS admin_credit_grants (id TEXT PRIMARY KEY, actor TEXT NOT NULL, owner TEXT NOT NULL, amount INTEGER NOT NULL, reason TEXT NOT NULL, created REAL NOT NULL)')
        prior = c.execute('SELECT * FROM admin_credit_grants WHERE id=?', (key,)).fetchone()
        if prior:
            if (prior['actor'], prior['owner'], prior['amount'], prior['reason']) != (actor, owner, grant.credits, reason):
                raise HTTPException(409, 'This request ID was already used for a different grant.')
            return {'granted': grant.credits, 'duplicate': True}
        now = time.time()
        c.execute('INSERT OR IGNORE INTO users(id,token,paid,trial) VALUES(?,?,0,0)', (owner, owner))
        c.execute('INSERT INTO admin_credit_grants VALUES(?,?,?,?,?,?)', (key, actor, owner, grant.credits, reason, now))
        c.execute('UPDATE users SET paid=paid+? WHERE id=?', (grant.credits, owner))
        c.execute('INSERT INTO ledger VALUES(?,?,?,?,?,?)', (key, owner, 'admin_credit', grant.credits, now, json.dumps({'source':'Admin-granted demo credits'})))
    return {'granted': grant.credits, 'duplicate': False}
