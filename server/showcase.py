"""Read-only website library backed by the same owner records as the iOS app."""
import json
from pathlib import Path
from urllib.parse import urlsplit, unquote
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from .identity import require_account
from . import mobile
from .config import STORAGE, RUNS

router = APIRouter(prefix='/api/showcase', tags=['showcase'])

def local_media(raw, extensions):
    """Resolve a recorded studio file, never an arbitrary URL or filesystem path."""
    if not raw: return None
    raw = unquote(urlsplit(raw).path)
    root = STORAGE if raw.startswith('/files/') else RUNS if raw.startswith('/runs/') else None
    if root is None: return None
    path = (root / raw.split('/', 2)[2]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file() or path.suffix.lower() not in extensions: return None
    return path


def items(owner):
    with mobile.connect() as c:
        work = [json.loads(r[0]) for r in c.execute('SELECT data FROM work WHERE owner=?', (owner,))]
        concepts = [dict(json.loads(r[0]), projectId=r[1]) for r in c.execute('SELECT data, project FROM concepts WHERE owner=?', (owner,))]
    by_id = {x['id']: x for x in concepts}
    result = {}
    for job in work:
        # Persisted selection is authoritative. Older jobs retain project links;
        # show their related concepts without inventing selected-view provenance.
        ids = job.get('selectedConceptIds') or ([job['selectedConceptId']] if job.get('selectedConceptId') else [])
        exact = bool(ids)
        if not ids:
            related = [x for x in concepts if x.get('projectId') == job.get('projectId') and not x.get('isOriginal')]
            ids = [x['id'] for x in sorted(related, key=lambda x:x.get('createdAt',0))[-4:]]
        refs = ['concept:'+cid for cid in ids if cid in by_id and not by_id[cid].get('isOriginal')][:4]
        for asset in job.get('assets', []):
            result['model:'+asset['id']] = {
                'id':'model:'+asset['id'], 'name':asset.get('name') or 'Untitled creation',
                'kind':'3D object', 'createdAt':asset.get('createdAt',job.get('createdAt',0)),
                'image':asset.get('thumbUrl'), 'model':asset.get('modelUrl'),
                'projectId':job.get('projectId',''), 'conceptIds':refs,
                'selectionKnown':exact, 'prompt':job.get('sourcePrompt') or '',
            }
    for concept in concepts:
        if concept.get('isOriginal'): continue
        result['concept:'+concept['id']] = {
            'id':'concept:'+concept['id'], 'name':concept.get('name') or concept.get('label') or 'Concept image',
            'kind':'Concept image', 'createdAt':concept.get('createdAt',0), 'image':concept.get('imageUrl'),
            'projectId':concept.get('projectId',''), 'conceptIds':[], 'selectionKnown':False,
            'prompt':concept.get('prompt',''),
        }
    return sorted(result.values(), key=lambda x:x['createdAt'] or 0, reverse=True)

@router.get('/library')
def library(owner=Depends(require_account)):
    return [{'id':x['id'],'name':x['name'],'kind':x['kind'],'createdAt':x['createdAt'], 'hasImage':bool(x.get('image')), 'hasModel':bool(x.get('model'))} for x in items(owner)]

@router.get('/library/{item_id}/{part}')
def media(item_id: str, part: str, owner=Depends(require_account)):
    if part not in ('image','model'): raise HTTPException(404)
    item = next((x for x in items(owner) if x['id']==item_id), None)
    if not item or not item.get(part): raise HTTPException(404)
    url = urlsplit(item[part])
    raw = unquote(url.path)
    root = STORAGE if raw.startswith('/files/') else RUNS if raw.startswith('/runs/') else None
    if root is None: raise HTTPException(404)
    path = (root / raw.split('/',2)[2]).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file(): raise HTTPException(404)
    if part == 'image' and path.suffix.lower() not in ('.png','.jpg','.jpeg','.webp'): raise HTTPException(404)
    if part == 'model' and path.suffix.lower() not in ('.glb','.usdz'): raise HTTPException(404)
    return FileResponse(path, headers={'Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff'})
