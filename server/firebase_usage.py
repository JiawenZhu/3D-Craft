"""Pure reservation accounting used inside durable generation transactions."""
from fastapi import HTTPException
from .firebase_subscriptions import expire_allowance


def reserve(wallet, cost, now):
    if type(cost) is not int or cost <= 0:
        raise ValueError('A verified positive Token quote is required')
    data = expire_allowance(wallet, now)
    subscription = min(max(0, int(data.get('subscriptionAvailable', 0))), cost)
    packs = cost - subscription
    if int(data.get('available', 0)) < packs:
        raise HTTPException(402, 'Not enough Tokens. Add Tokens and confirm again.')
    data['available'] = int(data.get('available', 0)) - packs
    data['subscriptionAvailable'] = int(data.get('subscriptionAvailable', 0)) - subscription
    data['reserved'] = int(data.get('reserved', 0)) + cost
    allocation = dict(cost=cost, packs=packs, subscription=subscription,
        subscriptionTransaction=data.get('subscriptionTransaction'),
        environment=data.get('environment', 'PRODUCTION'))
    return data, allocation


def settle(wallet, allocation, charge, now, subscription_refunded=False):
    cost = allocation['cost']
    if type(charge) is not int or not 0 <= charge <= cost:
        raise ValueError('Settlement must fit the authorized reservation')
    data = expire_allowance(wallet, now)
    if int(data.get('reserved', 0)) < cost:
        raise ValueError('Reservation balance is inconsistent')
    # Spend the expiring allowance first, then packs. A failed job cannot create
    # new-period Tokens or revive a refunded/expired subscription allowance.
    subscription_spent = min(allocation['subscription'], charge)
    packs_spent = charge - subscription_spent
    data['available'] = int(data.get('available', 0)) + allocation['packs'] - packs_spent
    returned_subscription = allocation['subscription'] - subscription_spent
    valid_period = (data.get('subscriptionTransaction') == allocation.get('subscriptionTransaction')
                    and data.get('subscriptionExpiresAt', 0) > now and not subscription_refunded)
    if valid_period:
        data['subscriptionAvailable'] = int(data.get('subscriptionAvailable', 0)) + returned_subscription
    data['reserved'] = int(data.get('reserved', 0)) - cost
    return data
