"""Verified subscription periods, with non-rolling allowances separate from packs."""
from datetime import datetime
import math
import os
from fastapi import HTTPException

PLANS = {'craft.creator.weekly.v1': 250, 'craft.creator.monthly.v1': 850}


def timestamp(value):
    if not isinstance(value, str): return None
    try:
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        if parsed.tzinfo is None: return None
        result = parsed.timestamp()
        return result if math.isfinite(result) and result > 0 else None
    except (ValueError, OverflowError): return None


def verified_subscriptions(info, now):
    for product, item in (info.get('subscriptions') or {}).items():
        if product not in PLANS or not isinstance(item, dict): continue
        tid = item.get('store_transaction_id')
        start, end = timestamp(item.get('purchase_date')), timestamp(item.get('expires_date'))
        if (not isinstance(tid, str) or not tid or len(tid) > 150
                or item.get('store') != 'app_store' or type(item.get('is_sandbox')) is not bool
                or item.get('ownership_type', 'PURCHASED') != 'PURCHASED'
                or item.get('period_type') not in ('normal', 'intro')
                or start is None or end is None or not start < end or start > now):
            continue
        environment = 'SANDBOX' if item['is_sandbox'] else 'PRODUCTION'
        if environment == 'SANDBOX' and os.getenv('CRAFT_REVENUECAT_SANDBOX') != '1': continue
        yield dict(product=product, transaction=tid, environment=environment,
                   purchasedAt=start, expiresAt=end, refund=bool(item.get('refunded_at')),
                   superseded=item.get('is_upgraded') is True)


def expire_allowance(wallet, now):
    """Every balance read/spend must apply expiry, even without a webhook."""
    data = dict(wallet)
    if float(data.get('subscriptionExpiresAt', 0)) <= now:
        data['subscriptionAvailable'] = 0
    return data


def subscription_transition(prior, wallet, uid, purchase, now):
    if prior and (prior['ownerId'] != uid or prior['product'] != purchase['product']):
        raise HTTPException(409, 'This purchase belongs to another account or product.')
    data = expire_allowance(wallet, now)
    record = dict(prior or dict(ownerId=uid, product=purchase['product'],
        transaction=purchase['transaction'], environment=purchase['environment'],
        tokens=PLANS[purchase['product']], granted=False, refunded=False, creditedTokens=0))
    key = purchase['environment'] + ':' + purchase['transaction']
    current_key = data.get('subscriptionTransaction')
    current_start = float(data.get('subscriptionPurchasedAt', 0))
    incoming_order = (purchase['purchasedAt'], PLANS[purchase['product']], key)
    current_order = (current_start, PLANS.get(data.get('subscriptionProduct'), 0), current_key or '')
    grant = 0
    if purchase['refund']: record['refunded'] = True
    if current_key == key:
        # An extension of a paid period does not refill its allowance.
        data['subscriptionExpiresAt'] = max(float(data.get('subscriptionExpiresAt', 0)), purchase['expiresAt'])
        if record['refunded'] or purchase['superseded']:
            data['subscriptionAvailable'] = 0
    elif incoming_order > current_order:
        active = purchase['expiresAt'] > now and not record['refunded'] and not purchase['superseded']
        if active and not record['granted']:
            grant = PLANS[purchase['product']]
        data.update(subscriptionTransaction=key, subscriptionProduct=purchase['product'],
                    subscriptionPurchasedAt=purchase['purchasedAt'], subscriptionExpiresAt=purchase['expiresAt'],
                    subscriptionAvailable=grant)
    if not record['granted']:
        record['granted'] = True
        record['creditedTokens'] = grant
    data = expire_allowance(data, now)
    # available remains the non-expiring pack balance; no migration reinterprets it.
    return record, data, grant
