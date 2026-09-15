"""Publish private display previews, using the owner's verified Firebase identity.
No public URLs, provider credentials, original uploads or balances are published.
"""
import base64
import hashlib
import io
import json
import time
from urllib.parse import quote, unquote, urlsplit
import requests
from PIL import Image, ImageOps
from fastapi import APIRouter, Depends, Header, HTTPException
from .identity import require_account
from . import mobile
from .showcase import items, local_media
from .config import STORAGE, RUNS
router=APIRouter(prefix='/api/mobile/cloud-library', tags=['private cloud library'])

def preview_data(raw):
    if not raw: return ''
    url=urlsplit(raw)
    raw=unquote(url.path)
    root=STORAGE if raw.startswith('/files/') else RUNS if raw.startswith('/runs/') else None
    if root is None: return ''
    path=(root/raw.split('/',2)[2]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file(): return ''
    with Image.open(path) as source:
        image=ImageOps.exif_transpose(source).convert('RGB')
        image.thumbnail((1000,1000))
        output=io.BytesIO();image.save(output,format='JPEG',quality=78)
    data=output.getvalue()
    if len(data)>450000: return ''
    return 'data:image/jpeg;base64,'+base64.b64encode(data).decode()

BUCKET = 'forma-studio-2026.firebasestorage.app'

def model_object(item, uid):
    path = local_media(item.get('model'), ('.glb',))
    if not path: return None, ''
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    return path, f'users/{uid}/models/{digest}.glb'

def cloud_document(item, uid):
    try: preview = preview_data(item.get('image'))
    except (OSError, ValueError): preview = ''
    path, object_name = model_object(item, uid)
    return {
        'name':item['name'], 'kind':item['kind'], 'createdAt':float(item.get('createdAt') or 0),
        'preview':preview, 'source':'ios', 'ownerId':uid,
        'projectId':item.get('projectId',''), 'conceptIds':item.get('conceptIds',[]),
        'selectionKnown':item.get('selectionKnown',False), 'prompt':item.get('prompt','')[:12000],
        'modelStoragePath':object_name,
    }, path

def firestore_value(value):
    if isinstance(value, bool): return {'booleanValue':value}
    if isinstance(value, (int,float)): return {'doubleValue':value}
    if isinstance(value, list): return {'arrayValue':{'values':[firestore_value(x) for x in value]}}
    return {'stringValue':value}

@router.post('/sync')
def sync(owner=Depends(require_account), authorization: str=Header(default='')):
    uid=owner.removeprefix('firebase:')
    collection=f'https://firestore.googleapis.com/v1/projects/forma-studio-2026/databases/(default)/documents/users/{quote(uid,safe="")}/mobileCreations'
    synced=0
    with mobile.connect() as c:
        c.execute('CREATE TABLE IF NOT EXISTS cloud_library_sync (owner TEXT, item TEXT, digest TEXT, PRIMARY KEY(owner,item))')
    for item in items(owner):
        # A migrated Firebase record is authoritative. Old preview sync must not
        # overwrite its Storage references or newer cloud edits.
        document_url = collection+'/'+quote(item['id'],safe='')
        try:
            current = requests.get(document_url, headers={'Authorization':authorization}, timeout=10)
            if current.status_code == 200:
                version = current.json().get('fields', {}).get('storageVersion', {})
                if int(version.get('integerValue', version.get('doubleValue', 0))) >= 2:
                    continue
            elif current.status_code != 404:
                raise HTTPException(503, 'Cloud library could not be checked. Please try again.')
        except (requests.RequestException, ValueError):
            raise HTTPException(503, 'Cloud library is temporarily unavailable.') from None
        data, model = cloud_document(item, uid)
        digest=hashlib.sha256(json.dumps(data,sort_keys=True).encode()).hexdigest()
        with mobile.connect() as c:
            prior=c.execute('SELECT digest FROM cloud_library_sync WHERE owner=? AND item=?',(owner,item['id'])).fetchone()
        if prior and prior[0]==digest: continue
        try:
            if model:
                # Owner-authenticated Firebase Storage upload. No public download
                # token is created; reads require this same Firebase account.
                endpoint=f'https://firebasestorage.googleapis.com/v0/b/{BUCKET}/o'
                token=authorization.removeprefix('Bearer ')
                headers={'Authorization':'Firebase '+token}
                existing=requests.get(endpoint+'/'+quote(data['modelStoragePath'],safe=''),headers=headers,timeout=10)
                if existing.status_code == 404:
                    with model.open('rb') as content:
                        response=requests.post(endpoint,params={'name':data['modelStoragePath'],'uploadType':'media'},
                            headers={**headers,'Content-Type':'model/gltf-binary'},data=content,timeout=60)
                    if response.status_code not in (200,201): raise HTTPException(503,'Your 3D file could not sync yet. It remains saved in your studio.')
                elif existing.status_code != 200:
                    raise HTTPException(503,'Your private model storage is temporarily unavailable.')
            response=requests.patch(collection+'/'+quote(item['id'],safe=''),headers={'Authorization':authorization},
                json={'fields':{k:firestore_value(v) for k,v in data.items()}},timeout=10)
        except requests.RequestException:
            raise HTTPException(503,'Cloud library is temporarily unavailable. Your local creations are safe.') from None
        if response.status_code not in (200,201):
            raise HTTPException(503,'Cloud library could not sync. Please sign in again or contact support.')
        with mobile.connect() as c:
            c.execute('INSERT OR REPLACE INTO cloud_library_sync VALUES(?,?,?)',(owner,item['id'],digest))
        synced+=1
        if synced>=2: break
    return {'synced':synced}

from pydantic import BaseModel, Field

class DeviceLibraryClaim(BaseModel):
    deviceToken: str = Field(min_length=30,max_length=200)

@router.post('/claim-device')
def claim_device(body: DeviceLibraryClaim, owner=Depends(require_account)):
    """A device can attach its existing creations once, proving its old credential.
    Review balances and purchase history are never migrated as real credits.
    """
    digest=hashlib.sha256(body.deviceToken.encode()).hexdigest()
    with mobile.connect() as c:
        c.execute('BEGIN IMMEDIATE')
        c.execute('CREATE TABLE IF NOT EXISTS device_library_claims (device_owner TEXT PRIMARY KEY, account_owner TEXT NOT NULL, created REAL NOT NULL)')
        old=c.execute('SELECT id FROM users WHERE token=?',(digest,)).fetchone()
        if not old or old['id'].startswith('firebase:'): raise HTTPException(404,'No device library was found.')
        old=old['id']
        claimed=c.execute('SELECT account_owner FROM device_library_claims WHERE device_owner=?',(old,)).fetchone()
        if claimed:
            if claimed[0]!=owner: raise HTTPException(409,'This device library already belongs to another account.')
            return {'claimed':True}
        for row in c.execute('SELECT data FROM work WHERE owner=?',(old,)):
            if json.loads(row[0]).get('status') in ('queued','running'): raise HTTPException(409,'Wait for your current creation to finish before syncing your library.')
        for table in ('projects','concepts','work','chat_turns'):
            c.execute(f'UPDATE {table} SET owner=? WHERE owner=?',(owner,old))
        c.execute('INSERT INTO device_library_claims VALUES(?,?,?)',(old,owner,time.time()))
    return {'claimed':True}
