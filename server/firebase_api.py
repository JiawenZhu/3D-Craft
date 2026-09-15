"""Cloud-only studio API. No SQLite databases, laptop paths or local sessions.

Keep generation unavailable until durable worker and billing acceptance pass.
An API returning library data is not evidence of generation readiness.
"""
from functools import lru_cache
from urllib.parse import quote
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from .identity import require_claims
from .firebase_studio import FirebaseStudio, BUCKET
from .firebase_billing import CloudBilling
from pydantic import BaseModel, Field

app = FastAPI(title='3D Craft Cloud API')
app.add_middleware(CORSMiddleware, allow_origins=['https://3d-craft.web.app'], allow_methods=['GET','POST'], allow_headers=['Authorization','Content-Type'])

@lru_cache
def studio(): return FirebaseStudio()

def owner(claims=Depends(require_claims)):
    return 'firebase:' + (claims.get('uid') or claims['sub'])


def public_shape(data, account):
    uid = account.removeprefix('firebase:')
    if isinstance(data, dict): return {k: public_shape(v,account) for k,v in data.items()}
    if isinstance(data, list): return [public_shape(v,account) for v in data]
    prefix = f'gs://{BUCKET}/users/{uid}/'
    if isinstance(data,str) and data.startswith('gs://'):
        if not data.startswith(prefix): raise HTTPException(500,'A cloud file could not be resolved for this account.')
        path = data.removeprefix(f'gs://{BUCKET}/')
        return f'https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o/{quote(path,safe="")}?alt=media'
    return data


@app.get('/api/health')
def health():
    return {'status':'ok','storage':'firebase','apiOrigin':'https://3d-craft.web.app','generationReady':False}


@app.get('/api/mobile/projects')
def projects(account=Depends(owner)):
    records = studio().records(account,'studioProjects')
    concepts = studio().records(account,'studioConcepts')
    turns = studio().records(account,'studioConversations')
    for project in records:
        project['concepts'] = sorted([c for c in concepts if c.get('projectId') == project['id']],key=lambda c:c.get('createdAt',0))
        project['conversation'] = sorted([t for t in turns if t.get('projectId') == project['id']],key=lambda t:t.get('createdAt',0))
    return public_shape(sorted(records,key=lambda p:p.get('createdAt',0),reverse=True),account)


@app.get('/api/mobile/jobs')
def jobs(account=Depends(owner)):
    return public_shape(sorted(studio().records(account,'studioJobs'),key=lambda j:j.get('createdAt',0),reverse=True),account)


@app.get('/api/mobile/jobs/{ident}')
def job(ident: str, account=Depends(owner)):
    item = next((j for j in studio().records(account,'studioJobs') if j['id']==ident),None)
    if item is None: raise HTTPException(404,'Creation not found in your account.')
    return public_shape(item,account)


@app.get('/api/mobile/assets')
def assets(account=Depends(owner)):
    uid = account.removeprefix('firebase:')
    result = []
    for item in studio().records(account,'mobileCreations'):
        if item.get('kind') != '3D object': continue
        def media(field):
            path = item.get(field,'')
            return public_shape('gs://'+BUCKET+'/'+path,account) if path.startswith(f'users/{uid}/') else None
        result.append({'id':item['id'].removeprefix('model:'),'name':item.get('name','Untitled creation'),
                       'modelUrl':media('modelStoragePath'),'thumbUrl':media('previewStoragePath') or item.get('preview'),
                       'isExample':False})
    return {'owned':result,'examples':[]}


@app.post('/api/mobile/cloud-library/sync')
def sync(account=Depends(owner)):
    return {'synced':0,'storage':'firebase'}


@app.get('/api/mobile/wallet')
def wallet(account=Depends(owner)):
    return CloudBilling(studio().db).wallet(account.removeprefix('firebase:'))


class PurchaseClaim(BaseModel):
    productId: str = Field(min_length=1, max_length=150)
    transactionId: str = Field(min_length=1, max_length=150)


@app.post('/api/mobile/purchases/revenuecat')
def verify_purchase(body: PurchaseClaim, account=Depends(owner)):
    return CloudBilling(studio().db).sync(account.removeprefix('firebase:'), (body.productId, body.transactionId))


@app.post('/api/mobile/purchases/revenuecat/sync')
def sync_purchases(account=Depends(owner)):
    return CloudBilling(studio().db).sync(account.removeprefix('firebase:'))


@app.get('/api/mobile/bootstrap')
def bootstrap(account=Depends(owner)):
    return {'mode':'cloud','wallet':wallet(account),'products':[], 'engines':[], 'engineCatalog':[],
            'generationReady':False}


@app.api_route('/api/{path:path}',methods=['GET','POST','DELETE','PATCH'])
def unavailable(path: str, account=Depends(owner)):
    raise HTTPException(503,'Cloud generation and purchase delivery are being prepared. No Tokens were charged.')
