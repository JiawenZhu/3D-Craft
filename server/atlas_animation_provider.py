"""AtlasCloud image-to-video adapter. No paid generation is retried on ambiguity."""
from pathlib import Path
from urllib.parse import urlsplit

import requests
from fastapi import HTTPException

from . import atlas_model_provider as atlas
from .cloud_animation_provider import describe, measure, validate_mp4

GENERATE_URL = atlas.API_BASE + '/api/v1/model/generateVideo'
MAX_VIDEO_BYTES = 80 * 1024 * 1024
MODELS = {
    'atlas-seedance-2.0-mini': 'bytedance/seedance-2.0-mini/image-to-video',
    'atlas-seedance-2.0': 'bytedance/seedance-2.0/image-to-video',
    'atlas-seedance-2.5': 'bytedance/seedance-2.5/image-to-video',
    'atlas-minimax-h3': 'minimax/h3/image-to-video',
    'atlas-wan-3.0-prime': 'alibaba/wan-3.0-prime/image-to-video',
}


def is_atlas_animation(model: str) -> bool:
    return model in MODELS


def arguments(image_url: str, motion: str | None, resolution: str, duration: str,
              aspect: str, model: str) -> dict:
    if model not in MODELS:
        raise HTTPException(422, 'Choose a supported animation model.')
    if aspect != '1:1' or int(duration) not in (4, 6):
        raise HTTPException(422, 'Choose a supported Atlas animation length and aspect ratio.')
    prompt = describe(motion)
    payload = {'model': MODELS[model], 'image': image_url, 'prompt': prompt,
               'duration': int(duration)}
    if model == 'atlas-minimax-h3':
        if resolution not in ('768p', '2K'):
            raise HTTPException(422, 'Choose a supported MiniMax quality.')
        payload.update(resolution='768P' if resolution == '768p' else '2K',
                       end_image=image_url, ratio='adaptive', prompt_expansion=False)
    elif model == 'atlas-wan-3.0-prime':
        if resolution not in ('480p', '720p'):
            raise HTTPException(422, 'Choose a supported Wan quality.')
        payload.update(resolution=resolution, last_image=image_url, audio=False)
    else:
        if resolution not in ('480p', '720p'):
            raise HTTPException(422, 'Choose a supported Seedance quality.')
        payload.update(resolution=resolution, last_image=image_url,
                       ratio='adaptive' if model == 'atlas-seedance-2.5' else '1:1',
                       generate_audio=False)
    return payload


def submit(payload: dict, callback: str) -> str:
    response = requests.post(GENERATE_URL, headers=atlas.headers(),
                             json={**payload, 'webhook_url': callback}, timeout=45)
    response.raise_for_status()
    body = response.json()
    data = body.get('data') if isinstance(body.get('data'), dict) else body
    prediction_id = data.get('id') if isinstance(data, dict) else None
    if not isinstance(prediction_id, str) or not prediction_id:
        raise ValueError('Atlas video submission returned no prediction ID')
    return prediction_id


def status(prediction_id: str) -> dict | None:
    return atlas.status(prediction_id)


def download_video(result: dict, destination: str) -> None:
    data = result.get('data') if isinstance(result.get('data'), dict) else result
    outputs = data.get('outputs') or []
    url = next((value for value in outputs if isinstance(value, str)
                and urlsplit(value).path.lower().endswith('.mp4')), None)
    if not url:
        raise ValueError('Atlas video result contained no MP4')
    for _ in range(4):
        if not atlas.is_safe_cdn_url(url):
            raise ValueError('Unexpected video download location')
        with requests.get(url, stream=True, allow_redirects=False, timeout=120) as response:
            if response.is_redirect:
                url = response.headers.get('Location', '')
                continue
            response.raise_for_status()
            size = 0
            with Path(destination).open('wb') as output:
                for chunk in response.iter_content(65536):
                    size += len(chunk)
                    if size > MAX_VIDEO_BYTES:
                        raise ValueError('Animation exceeds file limit')
                    output.write(chunk)
            validate_mp4(destination)
            return
    raise ValueError('Animation download redirected too many times')
