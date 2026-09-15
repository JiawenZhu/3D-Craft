"""RevenueCat notifications trigger authoritative reconciliation, never client grants."""
import hmac
import os
from fastapi import HTTPException
from firebase_admin import auth
from .identity import firebase_app
from .firebase_studio import uid_for
from .firebase_billing import CloudBilling

APP_ID = 'appb88bdcb0f7'
EVENTS = {'INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE', 'CANCELLATION',
          'UNCANCELLATION', 'EXPIRATION', 'BILLING_ISSUE', 'PRODUCT_CHANGE',
          'SUBSCRIPTION_EXTENDED', 'REFUND_REVERSED'}


def reconcile_webhook(db, payload, authorization):
    secret = os.getenv('REVENUECAT_WEBHOOK_AUTHORIZATION', '')
    if not secret: raise HTTPException(503, 'Webhook not configured.')
    if not hmac.compare_digest(authorization.encode(), secret.encode()):
        raise HTTPException(401, 'Invalid webhook authorization.')
    event = payload.get('event')
    if not isinstance(event, dict): raise HTTPException(422, 'Invalid event.')
    if event.get('type') == 'TEST': return {'received': True}
    if event.get('app_id') != APP_ID or event.get('store') != 'APP_STORE':
        raise HTTPException(422, 'Event is not for the 3D Craft Apple app.')
    if event.get('type') not in EVENTS: return {'received': True, 'ignored': True}
    environment = event.get('environment')
    if environment not in ('PRODUCTION', 'SANDBOX'): raise HTTPException(422, 'Invalid environment.')
    if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1':
        return {'received': True, 'ignored': True}
    uid = event.get('app_user_id')
    try: uid_for('firebase:' + uid)
    except (ValueError, TypeError): raise HTTPException(422, 'Invalid account ID.') from None
    if uid.startswith('$RCAnonymousID:'): return {'received': True, 'ignored': True}
    if db.collection('accountDeletions').document(uid).get().exists:
        return {'received': True, 'ignored': True}
    try: auth.get_user(uid, app=firebase_app())
    except auth.UserNotFoundError: return {'received': True, 'ignored': True}
    # Pulling current state handles delayed/out-of-order cancellation and renewal
    # events, while Firestore receipt transactions make delivery retry-safe.
    CloudBilling(db).sync(uid)
    return {'received': True}
