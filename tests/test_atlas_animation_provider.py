"""Offline checks for Atlas video choices, output safety, and pricing."""
import base64
import json
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi import HTTPException

from server import atlas_animation_provider as video
from server import atlas_model_provider as atlas
from server.pricing import ATLAS_ANIMATION_RATES, animation_quote, animation_usage


class AtlasVideoTests(unittest.TestCase):
    def test_all_compared_models_have_verified_native_quotes(self):
        self.assertEqual(set(video.MODELS), set(ATLAS_ANIMATION_RATES))
        for model, tiers in ATLAS_ANIMATION_RATES.items():
            for resolution, rate in tiers.items():
                quote = animation_quote(resolution, 4, '1:1', model)
                self.assertGreater(quote['usageWithServiceFee']['credits'], 0)
                self.assertAlmostEqual(quote['ratePerSecondUsd'], rate)
                actual = animation_usage(640, 640, 4.04, model, resolution)
                self.assertLessEqual(actual['usageWithServiceFee']['credits'], quote['usageWithServiceFee']['credits'])
            self.assertIsNone(animation_quote('unsupported', 4, '1:1', model)['totalUsd'])

    def test_payloads_match_provider_families(self):
        image = 'https://cdn.atlascloud.ai/input.jpg'
        for model in ('atlas-seedance-2.0-mini', 'atlas-seedance-2.0', 'atlas-seedance-2.5'):
            args = video.arguments(image, 'waves', '480p', '4', '1:1', model)
            self.assertEqual(args['model'], video.MODELS[model])
            self.assertEqual(args['image'], args['last_image'])
            self.assertFalse(args['generate_audio'])
        h3 = video.arguments(image, None, '768p', '4', '1:1', 'atlas-minimax-h3')
        self.assertEqual(h3['resolution'], '768P')
        self.assertEqual(h3['image'], h3['end_image'])
        wan = video.arguments(image, None, '720p', '6', '1:1', 'atlas-wan-3.0-prime')
        self.assertFalse(wan['audio'])
        with self.assertRaises(HTTPException):
            video.arguments(image, None, '480p', '4', '1:1', 'atlas-minimax-h3')

    def test_paid_post_is_only_attempted_once_and_includes_callback(self):
        with patch.dict('os.environ', {'ATLAS_API_KEY': 'test'}), patch('requests.post', side_effect=TimeoutError) as post:
            with self.assertRaises(TimeoutError):
                video.submit({'model': video.MODELS['atlas-seedance-2.5']}, 'https://example.com/hook')
            post.assert_called_once()
            self.assertEqual(post.call_args.kwargs['json']['webhook_url'], 'https://example.com/hook')

    def test_ed25519_callback_verification_rejects_tampering(self):
        private = Ed25519PrivateKey.generate()
        public = private.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        kid = 'test-kid'
        body = json.dumps({'session_id': 'abc123', 'status': 'OK'}).encode()
        timestamp = str(int(time.time()))
        signature = private.sign(timestamp.encode() + b'.' + body)
        headers = {'X-AtlasCloud-Webhook-Timestamp': timestamp,
                   'X-AtlasCloud-Webhook-Key-Id': kid,
                   'X-AtlasCloud-Webhook-Signature-Ed25519': base64.urlsafe_b64encode(signature).decode().rstrip('=')}
        jwk = {'kid': kid, 'kty': 'OKP', 'crv': 'Ed25519', 'x': base64.urlsafe_b64encode(public).decode().rstrip('=')}
        response = Mock()
        response.json.return_value = {'keys': [jwk]}
        with patch('requests.get', return_value=response):
            atlas._jwks = (0, {})
            self.assertEqual(atlas.verify_callback(headers, body), 'abc123')
            with self.assertRaises(HTTPException):
                atlas.verify_callback(headers, body + b' ')

    def test_only_trusted_video_cdn_is_fetched(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):
                video.download_video({'outputs': ['https://evil.example/clip.mp4']}, str(Path(folder) / 'clip.mp4'))


if __name__ == '__main__':
    unittest.main()
