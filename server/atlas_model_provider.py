"""AtlasCloud image-to-3D provider integration.

Stateless provider adapter for AtlasCloud image-to-3D endpoints.
Handles media upload, task submission, prediction polling, safe GLB download
and validation. Paid submissions never retry automatically to prevent duplicate
billing. All credentials must come from ATLAS_API_KEY env.
"""
import json
import os
import struct
import base64
import binascii
import time
import zipfile
from pathlib import Path
from urllib.parse import urlsplit
import requests
from fastapi import HTTPException
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

API_BASE = "https://api.atlascloud.ai"
UPLOAD_URL = f"{API_BASE}/api/v1/model/uploadMedia"
GENERATE_URL = f"{API_BASE}/api/v1/model/generateImage"
PREDICTION_URL = f"{API_BASE}/api/v1/model/prediction"
JWKS_URL = f"{API_BASE}/api/v1/webhooks/jwks.json"
_jwks = (0.0, {})

ATLAS_MODELS = {
    'tripo': 'tripo-h3.1/image-to-3d',
    'seed3d': 'bytedance/seed3d-v2.0/image-to-3d',
    'hunyuan-rapid': 'tencent/hunyuan3d-rapid/image-to-3d',
    'hunyuan-pro': 'tencent/hunyuan3d-pro/image-to-3d',
    'hi3d-fast': 'hi3d/v2.1-fast/image-to-3d',
    'hi3d-pro': 'hi3d/v2.1-pro/image-to-3d',
    'hi3d-quality': 'hi3d/v3.0-quality/image-to-3d',
    'hi3d-master': 'hi3d/v3.0-master/image-to-3d',
    'meshy-single': 'meshy-v7/image-to-3d',
    'meshy-multi': 'meshy-v7/multi-image-to-3d',
}

ENGINES = {
    'tripo': 'Tripo H3.1',
    'seed3d': 'Seed3D 2.0',
    'hunyuan-rapid': 'Hunyuan Rapid',
    'hunyuan-pro': 'Hunyuan Pro',
    'hi3d-fast': 'HI3D v2.1 Fast',
    'hi3d-pro': 'HI3D v2.1 Pro',
    'hi3d-quality': 'HI3D v3.0 Quality',
    'hi3d-master': 'HI3D v3.0 Master',
    'meshy-single': 'Meshy v7',
    'meshy-multi': 'Meshy v7 Multi',
}

# Maximum allowed downloaded GLB size (150MB accommodates largest tested HI3D Master at 115MB)
MAX_GLB_BYTES = 150 * 1024 * 1024


def is_atlas_engine(engine: str) -> bool:
    return engine in ATLAS_MODELS


def is_atlas_result(result: dict) -> bool:
    if not isinstance(result, dict):
        return False
    data = result.get('data') if isinstance(result.get('data'), dict) else result
    return bool(data.get('outputs') or data.get('files') or ('status' in data and 'id' in data))


def headers() -> dict:
    key = os.getenv('ATLAS_API_KEY', '')
    if not key:
        raise HTTPException(503, 'Atlas model service is temporarily unavailable.')
    return {
        'Authorization': f'Bearer {key}',
        'Content-Type': 'application/json',
    }


def upload_media(file_path: Path | str) -> str:
    """Upload reference image to AtlasCloud storage via uploadMedia."""
    key = os.getenv('ATLAS_API_KEY', '')
    if not key:
        raise HTTPException(503, 'Atlas model service is temporarily unavailable.')
    path = Path(file_path)
    if not path.exists():
        raise ValueError(f'Reference image not found: {path}')
    if path.stat().st_size > 20 * 1024 * 1024:
        raise ValueError('Reference image exceeds 20MB limit')

    with path.open('rb') as f:
        signature = f.read(12)
        f.seek(0)
        if signature.startswith(b'\x89PNG\r\n\x1a\n'):
            filename, mime = 'reference.png', 'image/png'
        elif signature.startswith(b'\xff\xd8\xff'):
            filename, mime = 'reference.jpg', 'image/jpeg'
        elif signature.startswith(b'RIFF') and signature[8:12] == b'WEBP':
            filename, mime = 'reference.webp', 'image/webp'
        else:
            raise ValueError('Reference image must be JPEG, PNG, or WebP')
        response = requests.post(
            UPLOAD_URL,
            headers={'Authorization': f'Bearer {key}'},
            files={'file': (filename, f, mime)},
            timeout=60
        )
    response.raise_for_status()
    res = response.json()
    data = res.get('data') if isinstance(res.get('data'), dict) else res
    url = (data.get('url') or data.get('download_url')) if isinstance(data, dict) else None
    if not url or not isinstance(url, str):
        raise ValueError('Atlas uploadMedia did not return a valid URL')
    return url


def arguments(engine: str, urls: list[str], prompt: str | None = None, quality: str = 'default', effort: str = 'high') -> tuple[str, dict]:
    """Build the model endpoint and request payload matching official docs and tested settings."""
    if engine not in ATLAS_MODELS:
        raise ValueError(f'Unsupported Atlas model: {engine}')
    if not urls or (engine != 'meshy-multi' and len(urls) != 1):
        raise ValueError('Choose the supported number of reference images for this Atlas model')

    model_id = ATLAS_MODELS[engine]
    primary_url = urls[0]

    if engine == 'tripo':
        return model_id, {
            'model': model_id,
            'image_url': primary_url,
            'texture': True,
            'pbr': True,
            'texture_quality': 'standard',
            'geometry_quality': 'standard',
        }
    if engine == 'seed3d':
        return model_id, {
            'model': model_id,
            'image': primary_url,
            'subdivision_level': 'high',
            'file_format': 'glb',
        }
    if engine == 'hunyuan-rapid':
        return model_id, {
            'model': model_id,
            'image': primary_url,
            'enable_pbr': True,
            'format': 'GLB',
        }
    if engine == 'hunyuan-pro':
        return model_id, {
            'model': model_id,
            'image': primary_url,
            'generate_type': 'Normal',
            'enable_pbr': True,
        }
    if engine in ('hi3d-fast', 'hi3d-pro', 'hi3d-quality', 'hi3d-master'):
        return model_id, {
            'model': model_id,
            'image': primary_url,
            'should_texture': True,
            'enable_pbr': True,
            'output_format': 'glb',
        }
    if engine == 'meshy-single':
        return model_id, {
            'model': model_id,
            'image': primary_url,
            'should_texture': True,
            'enable_pbr': True,
            'texture_resolution': '2k',
            'target_formats': ['glb'],
        }
    if engine == 'meshy-multi':
        return model_id, {
            'model': model_id,
            'reference_images': urls,
            'should_texture': True,
            'enable_pbr': True,
            'texture_resolution': '2k',
            'target_formats': ['glb'],
        }
    raise ValueError(f'Unsupported Atlas model: {engine}')


def submit(endpoint: str, payload: dict, callback: str | None = None) -> str:
    """Submit 3D generation request to AtlasCloud generateImage.

    No automatic client retry of a paid POST. A signed webhook can recover a
    lost response without risking duplicate provider charges.
    """
    if callback:
        payload = {**payload, 'webhook_url': callback}
    response = requests.post(
        GENERATE_URL,
        headers=headers(),
        json=payload,
        timeout=45
    )
    response.raise_for_status()
    res = response.json()
    data = res.get('data') if isinstance(res.get('data'), dict) else res
    prediction_id = data.get('id') if isinstance(data, dict) else None
    if not prediction_id or not isinstance(prediction_id, str):
        raise ValueError(f'Atlas generateImage failed to return prediction ID: {res}')
    return prediction_id


def verify_callback(headers_: dict, raw: bytes) -> str:
    """Verify Atlas's Ed25519 signature over the timestamp and exact raw body."""
    timestamp = headers_.get('X-AtlasCloud-Webhook-Timestamp', '')
    kid = headers_.get('X-AtlasCloud-Webhook-Key-Id', '')
    signature = (headers_.get('X-AtlasCloud-Webhook-Signature-Ed25519')
                 or headers_.get('X-AtlasCloud-Webhook-Signature', ''))
    try:
        if not timestamp.isdecimal() or abs(time.time() - int(timestamp)) > 300:
            raise ValueError('Stale Atlas notification')
        if not kid or not signature or len(raw) > 1024 * 1024:
            raise ValueError('Incomplete Atlas notification')
        global _jwks
        expires, keys = _jwks
        if time.time() >= expires or kid not in keys:
            response = requests.get(JWKS_URL, timeout=10)
            response.raise_for_status()
            keys = {key['kid']: key for key in response.json()['keys']
                    if key.get('kty') == 'OKP' and key.get('crv') == 'Ed25519' and key.get('kid')}
            _jwks = (time.time() + 300, keys)
        key = keys.get(kid)
        if not key:
            raise ValueError('Unknown Atlas signing key')
        def decode(value):
            return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))
        public = Ed25519PublicKey.from_public_bytes(decode(key['x']))
        public.verify(decode(signature), timestamp.encode() + b'.' + raw)
        body = json.loads(raw)
        prediction_id = body.get('session_id')
        if not isinstance(prediction_id, str) or not prediction_id:
            raise ValueError('Missing Atlas prediction ID')
        return prediction_id
    except (ValueError, KeyError, TypeError, binascii.Error, InvalidSignature) as exc:
        raise HTTPException(401, 'Invalid Atlas notification signature.') from exc


def status(prediction_id: str) -> dict | None:
    """Poll prediction result from AtlasCloud prediction/{id}.

    Returns data dictionary when completed, None when still processing,
    or raises RuntimeError on provider failure.
    """
    key = os.getenv('ATLAS_API_KEY', '')
    if not key:
        raise HTTPException(503, 'Atlas model service is temporarily unavailable.')
    url = f"{PREDICTION_URL}/{prediction_id}"
    response = requests.get(
        url,
        headers={'Authorization': f'Bearer {key}'},
        timeout=30
    )
    response.raise_for_status()
    res = response.json()
    data = res.get('data') if isinstance(res.get('data'), dict) else res
    if not isinstance(data, dict):
        raise ValueError(f'Invalid response from prediction status: {res}')

    state = (data.get('status') or '').lower()
    if state in ('completed', 'done', 'succeeded'):
        return data
    if state in ('failed', 'error'):
        err_msg = data.get('error') or 'Generation failed on AtlasCloud'
        raise RuntimeError(f'Provider error: {err_msg}')
    # Still in progress ('created', 'processing', 'pending', etc.)
    return None


def extract_model_url(result: dict) -> str:
    """Extract output GLB URL safely from prediction result."""
    data = result.get('data') if isinstance(result.get('data'), dict) else result
    # Check files list first if available
    files = data.get('files') or []
    for item in files:
        if isinstance(item, dict):
            url = item.get('url')
            fname = (item.get('file_name') or '').lower()
            ftype = (item.get('type') or '').lower()
            if (ftype == 'glb' or fname.endswith('.glb')) and url:
                return url
    for item in files:
        if isinstance(item, dict) and item.get('url'):
            clean = urlsplit(item['url']).path.lower()
            if clean.endswith('.zip'):
                return item['url']
    for item in files:
        if isinstance(item, dict) and item.get('url'):
            clean = urlsplit(item['url']).path.lower()
            if not clean.endswith(('.png', '.jpg', '.jpeg', '.webp', '.json')):
                return item['url']

    # Check outputs list
    outputs = data.get('outputs') or []
    for url in outputs:
        if isinstance(url, str):
            clean = urlsplit(url).path.lower()
            if clean.endswith('.glb'):
                return url
    for url in outputs:
        if isinstance(url, str):
            clean = urlsplit(url).path.lower()
            if not any(clean.endswith(ext) for ext in ('.png', '.jpg', '.jpeg', '.webp', '.json')):
                return url
    if outputs and isinstance(outputs[0], str):
        return outputs[0]
    raise ValueError('No model output URL found in Atlas prediction result')


def is_safe_cdn_url(url: str) -> bool:
    try:
        parsed = urlsplit(url)
        port = parsed.port
    except ValueError:
        return False
    if parsed.scheme != 'https':
        return False
    if parsed.username or parsed.password:
        return False
    if port not in (None, 443):
        return False
    host = (parsed.hostname or '').lower()
    if not host:
        return False
    return any(host == suffix or host.endswith('.' + suffix)
               for suffix in ('atlascloud.ai', 'aliyuncs.com', 'amazonaws.com',
                              'cloudfront.net', 'storage.googleapis.com'))


def download_mesh(result: dict, destination: Path | str) -> None:
    """Safely stream download the finished GLB model from CDN with limits and validation."""
    url = extract_model_url(result)
    for _ in range(4):
        if not is_safe_cdn_url(url):
            raise ValueError('Unexpected model download location')
        with requests.get(url, stream=True, allow_redirects=False, timeout=90) as response:
            if response.is_redirect:
                url = response.headers.get('Location', '')
                continue
            response.raise_for_status()
            size = 0
            with Path(destination).open('wb') as output:
                for chunk in response.iter_content(65536):
                    size += len(chunk)
                    if size > MAX_GLB_BYTES:
                        raise ValueError('Model exceeds file limit')
                    output.write(chunk)
            target = Path(destination)
            with target.open('rb') as source:
                signature = source.read(4)
            if signature == b'PK\x03\x04':
                archive = target.with_suffix('.zip')
                target.replace(archive)
                try:
                    with zipfile.ZipFile(archive) as package:
                        entries = package.infolist()
                        meshes = [entry for entry in entries if entry.filename.lower().endswith('.glb') and not entry.is_dir()]
                        if len(entries) > 32 or len(meshes) != 1 or meshes[0].file_size > MAX_GLB_BYTES:
                            raise ValueError('Unexpected model archive contents')
                        with package.open(meshes[0]) as source, target.open('wb') as output:
                            extracted = 0
                            for chunk in iter(lambda: source.read(65536), b''):
                                extracted += len(chunk)
                                if extracted > MAX_GLB_BYTES:
                                    raise ValueError('Model exceeds file limit')
                                output.write(chunk)
                finally:
                    archive.unlink(missing_ok=True)
            validate_glb(target)
            return
    raise ValueError('Model download redirected too many times')


def validate_glb(path: Path | str) -> None:
    """Validate binary glTF (GLB) file format, structure, and ensure self-contained assets."""
    target = Path(path)
    with target.open('rb') as source:
        header = source.read(20)
        if len(header) != 20:
            raise ValueError('Incomplete GLB')
        magic, version, total, length, kind = struct.unpack('<4sIIII', header)
        if magic != b'glTF' or version != 2 or total != target.stat().st_size or kind != 0x4E4F534A or not 0 < length <= min(10 * 1024 * 1024, total - 20) or length % 4:
            raise ValueError('Invalid GLB model')
        doc = json.loads(source.read(length))
        if not isinstance(doc, dict) or not doc.get('meshes') or doc.get('asset', {}).get('version') != '2.0':
            raise ValueError('Model contains no mesh')
        for entry in doc.get('buffers', []) + doc.get('images', []):
            if entry.get('uri') and not entry['uri'].startswith('data:'):
                raise ValueError('Model requires an external file')
