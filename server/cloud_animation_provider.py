"""Stateless fal Seedance 2.5 adapter for looping character animations.

Same queue, signature and download rules as the 3D adapter
(`cloud_model_provider`); only the endpoint and payload differ. The loop
settings are the ones proven for the app's own mascot clips in
`scripts/mascot/generate_seedance_loops.py`: the character image is passed as
both the first and the last frame, audio is off, and the camera is asked to
stay still so the clip returns to where it started.
"""
import os
from pathlib import Path
from urllib.parse import urlsplit

import requests
from fastapi import HTTPException

from .cloud_model_provider import headers, status, submit, verify_callback  # noqa: F401 - shared queue plumbing

ENDPOINT = os.getenv('CRAFT_ANIMATION_ENDPOINT', 'bytedance/seedance-2.5/image-to-video')
RESOLUTIONS = ('480p', '720p')
DURATIONS = ('4', '6')
MAX_BYTES = 40 * 1024 * 1024

# Seedance keeps the character but drifts if the shot is not pinned down. These
# instructions are appended to whatever the person asks for.
LOOP_RULES = (' Locked-off static camera, no zoom, no pan, no cut. Keep the exact same character design, '
              'colors, proportions and background from the image. No text, no extra characters. '
              'Gentle, friendly motion. The character ends in exactly the same pose it started in so the '
              'clip loops seamlessly.')
DEFAULT_MOTION = ('The character performs a short friendly idle animation: it blinks, breathes gently and '
                  'shifts its weight a little.')


def describe(motion: str | None) -> str:
    text = (motion or '').strip() or DEFAULT_MOTION
    return text[:600] + LOOP_RULES


def arguments(image_url: str, motion: str | None, resolution: str, duration: str, aspect: str) -> dict:
    if resolution not in RESOLUTIONS:
        raise HTTPException(422, 'Choose a supported animation quality.')
    if duration not in DURATIONS:
        raise HTTPException(422, 'Choose a supported animation length.')
    return {'image_url': image_url, 'end_image_url': image_url, 'prompt': describe(motion),
            'resolution': resolution, 'duration': duration, 'aspect_ratio': aspect,
            'generate_audio': False}


def video_url(result: dict) -> str:
    value = (result or {}).get('video')
    url = value.get('url') if isinstance(value, dict) else value
    if not isinstance(url, str) or not url:
        raise ValueError('No animation returned')
    return url


def download_video(result: dict, destination: str) -> None:
    """Saves the provider's MP4, following only fal's own CDN."""
    url = video_url(result)
    for _ in range(4):
        parsed = urlsplit(url)
        host = parsed.hostname or ''
        if parsed.scheme != 'https' or not (host == 'fal.media' or host.endswith('.fal.media')) \
                or parsed.username or parsed.port not in (None, 443):
            raise ValueError('Unexpected animation download location')
        with requests.get(url, stream=True, allow_redirects=False, timeout=120) as response:
            if response.is_redirect:
                url = response.headers.get('Location', '')
                continue
            response.raise_for_status()
            size = 0
            with Path(destination).open('wb') as output:
                for chunk in response.iter_content(65536):
                    size += len(chunk)
                    if size > MAX_BYTES:
                        raise ValueError('Animation exceeds file limit')
                    output.write(chunk)
            validate_mp4(destination)
            return
    raise ValueError('Animation download redirected too many times')


def boxes(data: bytes, start: int, end: int):
    """Yields (type, payload start, payload end) for the MP4 boxes in a range."""
    import struct
    position = start
    while position + 8 <= end:
        size, kind = struct.unpack('>I4s', data[position:position + 8])
        header = 8
        if size == 1:                      # 64-bit size
            size = struct.unpack('>Q', data[position + 8:position + 16])[0]
            header = 16
        elif size == 0:                    # extends to the end
            size = end - position
        if size < header or position + size > end:
            return
        yield kind.decode('latin-1'), position + header, position + size
        position += size


def measure(path: str) -> tuple[int, int, float]:
    """The delivered clip's real pixels and seconds, read from its own header.

    fal bills on output pixels x seconds, so the charge is taken from what the
    provider actually returned rather than from what was requested.
    """
    import struct
    data = Path(path).read_bytes()
    width = height = 0
    seconds = 0.0

    def walk(start: int, end: int):
        nonlocal width, height, seconds
        for kind, body, stop in boxes(data, start, end):
            if kind in ('moov', 'trak', 'mdia'):
                walk(body, stop)
            elif kind == 'mvhd' and stop - body >= 20:
                version = data[body]
                offset = body + (20 if version == 1 else 12)
                if version == 1 and stop - body >= 32:
                    timescale = struct.unpack('>I', data[body + 20:body + 24])[0]
                    duration = struct.unpack('>Q', data[body + 24:body + 32])[0]
                else:
                    timescale = struct.unpack('>I', data[offset:offset + 4])[0]
                    duration = struct.unpack('>I', data[offset + 4:offset + 8])[0]
                if timescale:
                    seconds = max(seconds, duration / timescale)
            elif kind == 'tkhd':
                version = data[body]
                end_of_box = body + (96 if version == 1 else 84)
                if stop >= end_of_box:
                    w, h = struct.unpack('>II', data[end_of_box - 8:end_of_box])
                    width, height = max(width, w >> 16), max(height, h >> 16)

    walk(0, len(data))
    if not width or not height or seconds <= 0:
        raise ValueError('The animation file could not be measured')
    return width, height, seconds


def validate_mp4(path: str) -> None:
    """A real MP4 starts with an ftyp box; refuse anything else before storing."""
    with Path(path).open('rb') as source:
        header = source.read(12)
    if len(header) < 12 or header[4:8] != b'ftyp':
        raise ValueError('Provider returned a file that is not an MP4')
