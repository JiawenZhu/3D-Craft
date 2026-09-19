"""Bounded Vertex planning using the Cloud Run service identity, never app keys."""
import base64
import io
import json
import logging
from decimal import Decimal, ROUND_CEILING

import google.auth
from google.auth.transport.requests import Request
import requests
from PIL import Image

MODEL = 'gemini-3.5-flash-lite'
PROJECT = 'forma-studio-2026'
URL = f'https://aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/global/publishers/google/models/{MODEL}'
MAX_INPUT = 16000
MAX_OUTPUT = 1024
CHAT_MAX_INPUT = 32000
CHAT_MAX_OUTPUT = 2048
PRICE_CHANGE = 1798761600  # 2027-01-01 UTC, published introductory-price expiry.
from .creative_prompts import SYSTEM, CHAT_SYSTEM, CHAT_SCHEMA
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


def quote(now, kind='prompt'):
    max_input,max_output = (CHAT_MAX_INPUT,CHAT_MAX_OUTPUT) if kind=='chat' else (MAX_INPUT,MAX_OUTPUT)
    return {'model': MODEL, 'kind':kind,'maxTokens': cost(max_input, max_output, rates(now))['tokens'],
            'maxInput':max_input,'maxOutput':max_output,
            'expiresAt': min(now+3600, PRICE_CHANGE) if now < PRICE_CHANGE else now+3600,
            'rates': rates(now)}


def image_parts(image):
    if image is None: return []
    # A bounded preview leaves the original reference unchanged for 3D.
    with Image.open(io.BytesIO(image)) as source:
        if source.width*source.height > 40000000:
            raise PlannerError('This image is too large to plan from.')
        source.thumbnail((1024,1024))
        output=io.BytesIO(); source.convert('RGB').save(output,format='JPEG',quality=90)
    return [{'inlineData':{'mimeType':'image/jpeg','data':base64.b64encode(output.getvalue()).decode()}}]


def structured_body(system, schema, text, image, effort, maximum):
    return {'systemInstruction': {'parts':[{'text': system}]},
        'contents':[{'role':'user','parts':image_parts(image)+[{'text':text}]}],
        'generationConfig': {'maxOutputTokens':maximum,'thinkingConfig':{'thinkingLevel':effort.upper()},
            'responseMimeType':'application/json','responseSchema':schema}}


def body(words, image, effort='low'):
    schema={'type':'OBJECT','properties':{'prompt':{'type':'STRING'}},'required':['prompt']}
    return structured_body(SYSTEM,schema,'User asset description:\n'+words,image,effort,MAX_OUTPUT)


def chat_body(history, brief, style, image, effort='low'):
    schema={k:v for k,v in CHAT_SCHEMA.items() if k!='additionalProperties'}
    text=json.dumps({'selectedStyle':style,'currentBrief':brief,'conversation':history},ensure_ascii=False)
    return structured_body(CHAT_SYSTEM,schema,text,image,effort,CHAT_MAX_OUTPUT)


def call(method, payload, model=MODEL):
    credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
    headers={'Content-Type':'application/json'}
    credentials.before_request(Request(), 'POST', URL+':'+method, headers)
    try:
        # A plain POST is deliberately not retried, including 401, 429 and 5xx.
        url=URL if model==MODEL else URL.rsplit('/',1)[0]+'/'+model
        response=requests.post(url+':'+method,headers=headers,json=payload,timeout=(15,180))
        if response.status_code != 200:
            # Keep diagnostics useful without recording references, prompts,
            # credentials, or the provider's potentially sensitive response body.
            logging.getLogger(__name__).warning('Vertex request failed: model=%s method=%s status=%s', model, method, response.status_code)
            service = 'planning' if model == MODEL else 'image generation'
            reason = 'is temporarily busy' if response.status_code in (429, 500, 502, 503, 504) else 'could not finish'
            raise PlannerError(f'The {service} service {reason}. Unused reserved Tokens will be returned. Please try again.')
        result=response.json()
        if not isinstance(result,dict): raise ValueError("Invalid response")
        return result
    except (requests.RequestException, ValueError):
        raise PlannerError('The planning response could not be confirmed. Reserved Tokens will be released.') from None


def preflight(payload, maximum=MAX_INPUT):
    result=call('countTokens',{k:v for k,v in payload.items() if k!='generationConfig'})
    total=result.get('totalTokens')
    if type(total) is not int or not 0 < total <= maximum:
        raise PlannerError('This reference and description are too large to improve together.')
    return total


def generate(payload, prices, kind='prompt'):
    result=call('generateContent',payload)
    candidates=result.get('candidates') or []
    if not candidates or candidates[0].get('finishReason')!='STOP':
        raise PlannerError('No complete suggestion was returned. Your original description is unchanged.')
    try:
        parts=candidates[0]['content']['parts']
        text=''.join(p.get('text','') for p in parts if not p.get('thought'))
        parsed=json.loads(text)
        answer=validate_answer(parsed,kind)
        usage=result['usageMetadata']
        counts=[usage['promptTokenCount'],usage.get('candidatesTokenCount',0),usage.get('thoughtsTokenCount',0)]
        cached=usage.get('cachedContentTokenCount',0)
        if any(type(n) is not int or n < 0 for n in counts+[cached]) or counts[0]==0 or cached>counts[0]: raise ValueError()
    except (KeyError,IndexError,TypeError,ValueError):
        raise PlannerError('No usable suggestion was returned. Your original description is unchanged.') from None
    # Only the validated suggestion and usage counts are retained, not raw
    # responses or provider thought signatures. Charge is capped by consent.
    return {**answer,'model':MODEL,'usage':{'input':counts[0],'output':sum(counts[1:]),'cachedInput':cached},
            **cost(counts[0],sum(counts[1:]),prices,cached)}


def validate_answer(parsed, kind):
    if not isinstance(parsed,dict): raise ValueError('Invalid response')
    if kind=='prompt':
        prompt=parsed.get('prompt')
        if not isinstance(prompt,str) or not 1<=len(prompt.strip())<=800: raise ValueError('Invalid prompt')
        return {'prompt':prompt.strip()}
    if kind!='chat': raise ValueError('Unsupported planning operation')
    reply,brief=parsed.get('reply'),parsed.get('brief')
    suggestions=parsed.get('suggestions')
    if (any(not isinstance(value,str) or not 1<=len(value.strip())<=4000 for value in (reply,brief))
            or type(parsed.get('ready')) is not bool or not isinstance(suggestions,list)
            or len(suggestions)>3 or any(not isinstance(s,str) or not 1<=len(s.strip())<=120 for s in suggestions)):
        raise ValueError('Invalid creative reply')
    return {'reply':reply.strip(),'brief':brief.strip(),'ready':parsed['ready'],
            'suggestions':list(dict.fromkeys(s.strip() for s in suggestions))}
