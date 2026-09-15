"""Bounded Vertex planning using the Cloud Run service identity, never app keys."""
import base64
import io
import json
from decimal import Decimal, ROUND_CEILING

import google.auth
from google.auth.transport.requests import Request
import requests
from PIL import Image

MODEL = 'gemini-3.8-flash'
PROJECT = 'forma-studio-2026'
URL = f'https://aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/global/publishers/google/models/{MODEL}'
MAX_INPUT = 16000
MAX_OUTPUT = 1024
PRICE_CHANGE = 1798761600  # 2027-01-01 UTC, published introductory-price expiry.
from .creative_prompts import SYSTEM
from .commerce import policy


class PlannerError(RuntimeError):
    """Safe error text only. Raw provider responses must not reach logs or users."""


def rates(now):
    factor = 1 if now < PRICE_CHANGE else 2
    p = policy()
    return {'input': str(Decimal('.75')*factor), 'output': str(Decimal('3.75')*factor),
            'creditUsageUsd': str(p['creditUsageUsd']), 'serviceFeeRate': str(p['serviceFeeRate'])}


def cost(input_tokens, output_tokens, prices, cached_tokens=0):
    usd = ((Decimal(input_tokens-cached_tokens)+Decimal(cached_tokens)*Decimal('.1'))*Decimal(prices['input']) + Decimal(output_tokens)*Decimal(prices['output'])) / 1000000
    tokens = int((usd * (1+Decimal(prices['serviceFeeRate'])) / Decimal(prices['creditUsageUsd'])).to_integral_value(rounding=ROUND_CEILING))
    return {'providerUsd': str(usd), 'tokens': tokens}


def quote(now):
    return {'model': MODEL, 'maxTokens': cost(MAX_INPUT, MAX_OUTPUT, rates(now))['tokens'],
            'expiresAt': min(now+3600, PRICE_CHANGE) if now < PRICE_CHANGE else now+3600,
            'rates': rates(now)}


def body(words, image, effort='low'):
    # Uploaded source files were validated on ingestion; use a bounded preview
    # for planning, leaving the original unchanged for 3D reconstruction.
    with Image.open(io.BytesIO(image)) as source:
        if source.width*source.height > 40000000:
            raise PlannerError('This image is too large to plan from.')
        source.thumbnail((1024,1024))
        output=io.BytesIO(); source.convert('RGB').save(output,format='JPEG',quality=90)
    return {'systemInstruction': {'parts':[{'text': SYSTEM}]},
        'contents':[{'role':'user','parts':[
            {'inlineData':{'mimeType':'image/jpeg','data':base64.b64encode(output.getvalue()).decode()}},
            {'text': 'User asset description:\n'+words}]}],
        'generationConfig': {'maxOutputTokens':MAX_OUTPUT,'thinkingConfig':{'thinkingLevel':effort.upper()},
            'responseMimeType':'application/json','responseSchema':{'type':'OBJECT','properties':{'prompt':{'type':'STRING'}},'required':['prompt']}}}


def call(method, payload):
    credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    headers={'Content-Type':'application/json'}
    credentials.before_request(Request(), 'POST', URL+':'+method, headers)
    try:
        # A plain POST is deliberately not retried, including 401, 429 and 5xx.
        response=requests.post(URL+':'+method,headers=headers,json=payload,timeout=(15,180))
        if response.status_code != 200:
            raise PlannerError('The planning service could not finish. Reserved Tokens will be released.')
        return response.json()
    except (requests.RequestException, ValueError):
        raise PlannerError('The planning response could not be confirmed. Reserved Tokens will be released.') from None


def preflight(payload):
    result=call('countTokens',{k:v for k,v in payload.items() if k!='generationConfig'})
    total=result.get('totalTokens')
    if type(total) is not int or not 0 < total <= MAX_INPUT:
        raise PlannerError('This reference and description are too large to improve together.')
    return total


def generate(payload, prices):
    result=call('generateContent',payload)
    candidates=result.get('candidates') or []
    if not candidates or candidates[0].get('finishReason')!='STOP':
        raise PlannerError('No complete suggestion was returned. Your original description is unchanged.')
    try:
        parts=candidates[0]['content']['parts']
        text=''.join(p.get('text','') for p in parts if not p.get('thought'))
        prompt=json.loads(text)['prompt']
        if not isinstance(prompt,str) or not 1 <= len(prompt.strip()) <= 800: raise ValueError()
        usage=result['usageMetadata']
        counts=[usage['promptTokenCount'],usage.get('candidatesTokenCount',0),usage.get('thoughtsTokenCount',0)]
        cached=usage.get('cachedContentTokenCount',0)
        if any(type(n) is not int or n < 0 for n in counts+[cached]) or counts[0]==0 or cached>counts[0]: raise ValueError()
    except (KeyError,IndexError,TypeError,ValueError):
        raise PlannerError('No usable suggestion was returned. Your original description is unchanged.') from None
    # Only the validated suggestion and usage counts are retained, not raw
    # responses or provider thought signatures. Charge is capped by consent.
    return {'prompt':prompt.strip(),'model':MODEL,'usage':{'input':counts[0],'output':sum(counts[1:]),'cachedInput':cached},
            **cost(counts[0],sum(counts[1:]),prices,cached)}
