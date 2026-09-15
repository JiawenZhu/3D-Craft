"""Stateless fal queue adapter; job ownership and retries live in Firestore."""
import base64
import hashlib
import json
import os
import time
from pathlib import Path
from urllib.parse import urlsplit
import requests
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from fastapi import HTTPException
from .config import FAL_ENDPOINTS, TRELLIS_RESOLUTIONS

ENGINES = {'rodin': 'Rodin (Ultra)', 'trellis-2': 'TRELLIS.2',
           'hunyuan3d-2.1': 'Hunyuan 3D 2', 'hunyuan3d-2-white': 'Hunyuan 3D 2 · White mesh'}
EFFORTS = ('extreme-low','low','medium','high','extreme-high')
_keys = (0, [])


def arguments(engine, urls, directions, effort, quality, prompt):
    level = EFFORTS.index(effort)
    if engine == 'rodin':
        return FAL_ENDPOINTS['rodin'], dict(input_image_urls=urls, prompt=prompt,
            condition_mode='concat', seed=0, geometry_file_format='glb', material='PBR',
            quality=('extra-low','low','medium','high','high')[level],
            tier='Sketch' if quality == 'speedy' else 'Regular', use_hyper=False, TAPose=False)
    if engine == 'trellis-2':
        steps = (6,10,12,18,25)[level]
        if quality == 'speedy': steps = max(4, int(steps * .6))
        return FAL_ENDPOINTS['trellis-multi' if len(urls)>1 else 'trellis-2'], {
            **({'image_urls':urls} if len(urls)>1 else {'image_url':urls[0]}),
            'seed':0, 'resolution':1024 if len(urls)>1 else TRELLIS_RESOLUTIONS[effort],
            'ss_guidance_strength':7.5, 'ss_sampling_steps':steps,
            'shape_slat_guidance_strength':7.5, 'shape_slat_sampling_steps':steps,
            'tex_slat_sampling_steps':steps, 'decimation_target':40000, 'texture_size':2048}
    if engine not in ENGINES: raise ValueError('Unsupported model')
    steps = (12,20,30,40,60)[level]
    if quality == 'speedy': steps = max(8,int(steps*.6))
    inputs = {'input_image_url': urls[0]}
    if len(urls)>1:
        if len(directions)!=3 or set(directions)!={'front','back','left'}:
            raise ValueError('Hunyuan requires front, back and left views')
        inputs = {direction+'_image_url':url for direction,url in zip(directions,urls)}
    return FAL_ENDPOINTS['hunyuan3d-2.1-mv' if len(urls)>1 else 'hunyuan3d-2.1'], {
        **inputs, 'seed':0, 'num_inference_steps':steps, 'guidance_scale':7.5,
        'octree_resolution':(192,256,256,320,384)[level],
        'textured_mesh':engine!='hunyuan3d-2-white'}


def headers():
    key = os.getenv('FAL_KEY', '')
    if not key: raise HTTPException(503,'Model service is temporarily unavailable.')
    return {'Authorization':'Key '+key}


def submit(endpoint, payload, callback):
    # No automatic retry of a paid POST. A lost response is recovered from the
    # signed callback, rather than submitting and billing a second generation.
    response = requests.post('https://queue.fal.run/'+endpoint,
        params={'fal_webhook': callback}, headers={**headers(),'X-Fal-Request-Timeout':'900'},
        json=payload, timeout=45)
    response.raise_for_status()
    return response.json()['request_id']


def status(endpoint, request_id):
    import fal_client
    handle = fal_client.SyncClient(key=os.environ['FAL_KEY'], default_timeout=30).get_handle(endpoint, request_id)
    state = handle.status(with_logs=False)
    if type(state).__name__ == 'Completed': return handle.get()
    return None


def verify_callback(headers_, raw):
    global _keys
    names = ('x-fal-webhook-request-id','x-fal-webhook-user-id','x-fal-webhook-timestamp','x-fal-webhook-signature')
    rid, user, stamp, signature = [headers_.get(name, '') for name in names]
    try:
        if not all((rid,user,stamp,signature)) or abs(time.time()-int(stamp))>300: raise ValueError()
        signature = bytes.fromhex(signature)
    except ValueError: raise HTTPException(401,'Invalid model notification.') from None
    if time.time()-_keys[0] > 3600:
        response=requests.get('https://rest.fal.ai/.well-known/jwks.json',timeout=10)
        response.raise_for_status(); _keys=(time.time(),response.json()['keys'])
    message='\n'.join([rid,user,stamp,hashlib.sha256(raw).hexdigest()]).encode()
    for key in _keys[1]:
        try:
            Ed25519PublicKey.from_public_bytes(base64.urlsafe_b64decode(key['x']+'===')).verify(signature,message)
            return rid
        except (ValueError, KeyError, InvalidSignature): pass
    raise HTTPException(401,'Invalid model notification signature.')


def download_mesh(result, destination):
    url=None
    for name in ('model_glb_pbr','model_glb','model_mesh','model_meshes'):
        value=result.get(name)
        if isinstance(value,list):value=value[0] if value else None
        candidate=value.get('url') if isinstance(value,dict) else value
        if isinstance(candidate,str):url=candidate;break
    if not url:raise ValueError('No model returned')
    # Only provider-owned CDN output, with no credential forwarded to downloads.
    for _ in range(4):
        parsed=urlsplit(url);host=parsed.hostname or ''
        if parsed.scheme!='https' or not (host=='fal.media' or host.endswith('.fal.media')) or parsed.username or parsed.port not in (None,443):
            raise ValueError('Unexpected model download location')
        with requests.get(url,stream=True,allow_redirects=False,timeout=90) as response:
            if response.is_redirect:
                url=response.headers.get('Location','');continue
            response.raise_for_status(); size=0
            with Path(destination).open('wb') as output:
                for chunk in response.iter_content(65536):
                    size+=len(chunk)
                    if size>100*1024*1024:raise ValueError('Model exceeds file limit')
                    output.write(chunk)
            validate_glb(destination)
            return
    raise ValueError('Model download redirected too many times')


def validate_glb(path):
    import struct
    with Path(path).open('rb') as source:
        header=source.read(20)
        if len(header)!=20:raise ValueError('Incomplete GLB')
        magic,version,total,length,kind=struct.unpack('<4sIIII',header)
        if magic!=b'glTF' or version!=2 or total!=Path(path).stat().st_size or kind!=0x4E4F534A or not 0<length<=min(10*1024*1024,total-20) or length%4:
            raise ValueError('Invalid GLB model')
        doc=json.loads(source.read(length))
        if not isinstance(doc,dict) or not doc.get('meshes') or doc.get('asset',{}).get('version')!='2.0':raise ValueError('Model contains no mesh')
        for entry in doc.get('buffers',[])+doc.get('images',[]):
            if entry.get('uri') and not entry['uri'].startswith('data:'):
                raise ValueError('Model requires an external file')
