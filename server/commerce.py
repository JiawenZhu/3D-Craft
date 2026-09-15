"""Versioned commercial policy. Does not reinterpret the legacy review wallet.

Credit usage is based on provider costs, NOT the retail purchase price of credits.
Only trusted server/provider observations may be passed for settlement. Unknown
costs block a complete bill; callers must not substitute zero for missing usage.
"""
from decimal import Decimal, ROUND_CEILING, ROUND_HALF_UP
from pathlib import Path
import json

CATALOG_PATH = Path(__file__).resolve().parents[1] / 'config/commerce/plans.json'

def policy():
    return json.loads(CATALOG_PATH.read_text())

def money(value):
    if isinstance(value, bool):
        raise ValueError('Expected a nonnegative finite cost')
    result = Decimal(str(value))
    if not result.is_finite() or result < 0:
        raise ValueError('Expected a nonnegative finite cost')
    return result

def usage_quote(items):
    """Aggregate chat, images, model stages and add-ons, then mark up ONCE.

    Every item requires a unique server-owned usage ID. USD may be None for
    unresolved provider usage. An explicitly account-included call may be zero.
    Returns exact decimal strings so money is not accumulated in binary floats.
    """
    ids=set(); subtotal=Decimal(0); unknown=[]
    for item in items:
        ident=item['id']
        if not isinstance(ident,str) or not ident or ident in ids:
            raise ValueError('Each usage event must have a unique ID')
        ids.add(ident)
        if item.get('providerUsd') is None: unknown.append(ident)
        else: subtotal += money(item['providerUsd'])
    p=policy(); fee=subtotal*money(p['serviceFeeRate']); total=subtotal+fee
    credit_value=money(p['creditUsageUsd'])
    credits=int((total/credit_value).to_integral_value(rounding=ROUND_CEILING))
    return {'policyVersion':p['version'],'currency':'USD','complete':not unknown,
            'unpricedEvents':unknown,'knownProviderUsd':str(subtotal),
            'providerUsd':None if unknown else str(subtotal),
            'serviceFeeRate':p['serviceFeeRate'],
            'serviceFeeUsd':None if unknown else str(fee),
            'totalUsageUsd':None if unknown else str(total),
            'credits':None if unknown else credits,
            'roundingUsd':None if unknown else str(credits*credit_value-total)}

def plan_economics(plan, apple_rate='0.30', revenuecat_rate='0.01'):
    p=policy(); retail=money(plan['usd']); apple=money(apple_rate); rc=money(revenuecat_rate)
    if apple+rc >= 1: raise ValueError('Combined store fees must be below 100%')
    grants=plan.get('grantsPerPeriod',1)
    allowance=Decimal(plan['credits']*grants)*money(p['creditUsageUsd'])
    provider=allowance/(1+money(p['serviceFeeRate']))
    net=retail*(1-apple-rc)
    fmt=lambda d:str(d.quantize(Decimal('.000001'),rounding=ROUND_HALF_UP))
    return {'productId':plan['id'],'retailUsd':str(retail),'appleRate':str(apple),'revenuecatRate':str(rc),
            'usageAllowanceUsd':str(allowance),'maxProviderCostUsd':fmt(provider),
            'netAfterPlatformUsd':fmt(net),'contributionBeforeHostingAndTaxUsd':fmt(net-provider),
            'reserveAfterUsageBudgetUsd':fmt(net-allowance)}
