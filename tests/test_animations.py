import unittest
from unittest.mock import patch
from fastapi import HTTPException

from server import cloud_animation_provider as provider
from server import firebase_animations as animations
from server import firebase_creations as creations
from server.firebase_animations import AnimationRequest, CloudAnimations
from server.firebase_studio import BUCKET
from server.pricing import animation_quote, animation_usage as _usage
from tests.fixtures import OWNER, UID, ProjectFixture, Studio, image


def request(**kw):
    return AnimationRequest(**{'idempotencyKey': 'anim-request-1', 'maxTokens': 200, **kw})


class QuoteTests(unittest.TestCase):
    def test_price_follows_the_pixel_budget_not_the_shape(self):
        square = animation_quote('480p', 4, '1:1')
        wide = animation_quote('480p', 4, '16:9')
        hd = animation_quote('720p', 4, '1:1')
        self.assertEqual(square['usageWithServiceFee']['credits'], 98)
        # A resolution is a pixel budget, so shape does not change the price.
        self.assertAlmostEqual(square['totalUsd'], wide['totalUsd'], places=2)
        self.assertLess(square['totalUsd'], hd['totalUsd'])
        self.assertEqual((square['width'], square['height'], square['seconds']), (640, 640, 4))

    def test_longer_costs_proportionally_more(self):
        four = animation_quote('480p', 4, '1:1')['totalUsd']
        six = animation_quote('480p', 6, '1:1')['totalUsd']
        self.assertAlmostEqual(six / four, 1.5, places=5)

    def test_an_unpriced_combination_never_invents_a_number(self):
        unknown = animation_quote('1080p', 4, '1:1')
        self.assertIsNone(unknown['totalUsd'])
        self.assertIsNone(unknown['usageWithServiceFee']['credits'])


class ProviderTests(unittest.TestCase):
    def test_loop_settings_match_the_mascot_recipe(self):
        args = provider.arguments('https://fal.media/in.jpg', 'it waves', '480p', '4', '1:1')
        self.assertEqual(args['image_url'], args['end_image_url'])   # ends where it starts
        self.assertFalse(args['generate_audio'])
        self.assertEqual((args['resolution'], args['duration'], args['aspect_ratio']), ('480p', '4', '1:1'))
        self.assertIn('it waves', args['prompt'])
        self.assertIn('loops seamlessly', args['prompt'])

    def test_empty_motion_gets_a_gentle_default(self):
        self.assertIn('blinks', provider.arguments('https://fal.media/i.jpg', '   ', '480p', '4', '1:1')['prompt'])

    def test_unsupported_settings_are_refused(self):
        with self.assertRaises(HTTPException):
            provider.arguments('https://fal.media/i.jpg', None, '1080p', '4', '1:1')
        with self.assertRaises(HTTPException):
            provider.arguments('https://fal.media/i.jpg', None, '480p', '12', '1:1')

    def test_only_fal_cdn_urls_are_downloaded(self):
        with self.assertRaises(ValueError):
            provider.download_video({'video': {'url': 'https://evil.example.com/x.mp4'}}, '/tmp/x.mp4')
        with self.assertRaises(ValueError):
            provider.download_video({}, '/tmp/x.mp4')

    def test_a_non_mp4_is_refused_before_it_is_stored(self):
        import tempfile, pathlib
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'fake.mp4'
            path.write_bytes(b'<html>not a video</html>')
            with self.assertRaises(ValueError):
                provider.validate_mp4(str(path))


class JobTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        self.wallet = self.studio.db.collection('users').document(UID).collection('private').document('wallet')
        self.wallet.set({'available': 500, 'subscriptionAvailable': 0, 'environment': 'PRODUCTION'})
        self.service = CloudAnimations(self.studio, clock=lambda: 1_000_000.0)
        self.patches = [patch.object(animations, 'enqueue'),
                        patch.object(provider, 'headers', return_value={'Authorization': 'Key test'}),
                        patch('server.firebase_animations.firestore.transactional', side_effect=lambda fn: fn)]
        for p in self.patches: p.start()

    def tearDown(self):
        for p in self.patches: p.stop()

    def create(self, **kw):
        return self.service.create(OWNER, 'mc-1', request(**kw))

    def test_creating_reserves_tokens_and_records_the_job(self):
        job = self.create()
        self.assertEqual((job['kind'], job['status'], job['cost']), ('animation', 'queued', 98))
        self.assertEqual(job['selectedImageUrl'], image('mc-1'))
        self.assertEqual(self.wallet.get().to_dict()['available'], 500 - 98)
        self.assertEqual(self.wallet.get().to_dict()['reserved'], 98)

    def test_replaying_the_same_key_never_charges_twice(self):
        first = self.create()
        again = self.create()
        self.assertEqual(first['id'], again['id'])
        self.assertEqual(self.wallet.get().to_dict()['available'], 500 - 98)

    def test_the_same_key_cannot_be_reused_for_different_work(self):
        self.create()
        with self.assertRaises(HTTPException) as caught:
            self.service.create(OWNER, 'mc-1', request(motion='completely different motion'))
        self.assertEqual(caught.exception.status_code, 409)

    def test_a_cap_below_the_price_stops_before_reserving(self):
        with self.assertRaises(HTTPException) as caught:
            self.create(maxTokens=10)
        self.assertEqual(caught.exception.status_code, 409)
        self.assertEqual(self.wallet.get().to_dict()['available'], 500)

    def test_an_empty_wallet_is_refused(self):
        self.wallet.set({'available': 3, 'subscriptionAvailable': 0, 'environment': 'PRODUCTION'})
        with self.assertRaises(HTTPException) as caught:
            self.create()
        self.assertEqual(caught.exception.status_code, 402)

    def test_someone_elses_image_is_not_found(self):
        with self.assertRaises(HTTPException) as caught:
            self.service.create('firebase:user_bob', 'mc-1', request())
        self.assertEqual(caught.exception.status_code, 404)

    def test_finishing_charges_once_and_publishes_the_character(self):
        job = self.create()
        _, private = self.service.refs(UID, job['id'])
        token, _ = self.service.claim(UID, job['id'])
        asset = dict(id=job['id'], name='Dragon', kind='animation',
                     animationUrl=f"gs://{BUCKET}/users/{UID}/animations/{job['id']}.mp4",
                     thumbUrl=image('mc-1'), isExample=False)
        self.assertEqual(self.service.finish(UID, job['id'], token, asset=asset), 'done')
        wallet = self.wallet.get().to_dict()
        self.assertEqual((wallet['available'], wallet['reserved']), (500 - 98, 0))
        record = self.studio.doc('mobileCreations', 'animation:' + job['id'])
        self.assertEqual(record['kind'], 'Animated character')
        self.assertEqual(record['animationStoragePath'], f"users/{UID}/animations/{job['id']}.mp4")
        self.assertEqual(record['previewStoragePath'], f'users/{UID}/images/mc-1.jpg')  # the character image
        self.assertEqual(self.studio.doc('studioJobs', job['id'])['status'], 'done')

    def test_a_failure_returns_every_reserved_token(self):
        job = self.create()
        token, _ = self.service.claim(UID, job['id'])
        self.assertEqual(self.service.finish(UID, job['id'], token, error='The animation could not be saved.'), 'failed')
        wallet = self.wallet.get().to_dict()
        self.assertEqual((wallet['available'], wallet['reserved']), (500, 0))
        self.assertIsNone(self.studio.doc('mobileCreations', 'animation:' + job['id']))
        self.assertEqual(self.studio.doc('studioJobs', job['id'])['charged'], 0)


class RealUsageBillingTests(unittest.TestCase):
    """Tokens follow the money: fal's own pixel formula, on the Rodin scale."""

    def test_the_token_scale_is_anchored_on_rodin(self):
        from server.pricing import model_quote
        rodin = model_quote('rodin')
        self.assertEqual((rodin['totalUsd'], rodin['usageWithServiceFee']['credits']), (0.40, 46))
        # Every creation converts provider dollars at the same rate.
        per_token = rodin['totalUsd'] / rodin['usageWithServiceFee']['credits']
        animation = _usage(480, 480, 4)
        self.assertAlmostEqual(animation['totalUsd'] / animation['usageWithServiceFee']['credits'],
                               per_token, places=3)

    def test_cost_scales_with_real_pixels_and_seconds(self):
        small = _usage(480, 480, 4)
        longer = _usage(480, 480, 8)
        bigger = _usage(720, 720, 4)
        self.assertEqual(small['providerTokens'], round(480 * 480 * 4 * 24 / 1024))
        self.assertAlmostEqual(longer['totalUsd'] / small['totalUsd'], 2.0, places=6)
        self.assertAlmostEqual(bigger['totalUsd'] / small['totalUsd'], (720 / 480) ** 2, places=6)

    def test_a_smaller_result_than_quoted_costs_less(self):
        studio = Studio()
        ProjectFixture().build(studio)
        wallet = studio.db.collection('users').document(UID).collection('private').document('wallet')
        wallet.set({'available': 500, 'subscriptionAvailable': 0, 'environment': 'PRODUCTION'})
        service = CloudAnimations(studio, clock=lambda: 1_000_000.0)
        with patch.object(animations, 'enqueue'), \
             patch.object(provider, 'headers', return_value={'Authorization': 'Key test'}), \
             patch('server.firebase_animations.firestore.transactional', side_effect=lambda fn: fn):
            job = service.create(OWNER, 'mc-1', request())
            token, _ = service.claim(UID, job['id'])
            # Reserved for 4 s; the provider returned 2.5 s.
            usage = _usage(480, 480, 2.5)
            asset = dict(id=job['id'], name='Dragon', kind='animation')
            service.finish(UID, job['id'], token, asset=asset, usage=usage)
        charged = studio.doc('studioJobs', job['id'])['charged']
        self.assertEqual(charged, usage['usageWithServiceFee']['credits'])
        self.assertLess(charged, 98)
        self.assertEqual(wallet.get().to_dict()['available'], 500 - charged)
        self.assertEqual(studio.doc('studioJobs', job['id'])['providerUsage']['seconds'], 2.5)

    def test_a_larger_result_never_charges_more_than_authorized(self):
        studio = Studio()
        ProjectFixture().build(studio)
        wallet = studio.db.collection('users').document(UID).collection('private').document('wallet')
        wallet.set({'available': 500, 'subscriptionAvailable': 0, 'environment': 'PRODUCTION'})
        service = CloudAnimations(studio, clock=lambda: 1_000_000.0)
        with patch.object(animations, 'enqueue'), \
             patch.object(provider, 'headers', return_value={'Authorization': 'Key test'}), \
             patch('server.firebase_animations.firestore.transactional', side_effect=lambda fn: fn):
            job = service.create(OWNER, 'mc-1', request())
            token, _ = service.claim(UID, job['id'])
            service.finish(UID, job['id'], token, asset=dict(id=job['id'], name='Dragon'),
                           usage=_usage(1280, 720, 6))  # far larger than asked for
        self.assertEqual(studio.doc('studioJobs', job['id'])['charged'], 98)
        self.assertEqual(wallet.get().to_dict()['available'], 500 - 98)

    def test_an_unreadable_file_falls_back_to_the_authorized_quote(self):
        studio = Studio()
        ProjectFixture().build(studio)
        studio.db.collection('users').document(UID).collection('private').document('wallet').set(
            {'available': 500, 'subscriptionAvailable': 0, 'environment': 'PRODUCTION'})
        service = CloudAnimations(studio, clock=lambda: 1_000_000.0)
        with patch.object(animations, 'enqueue'), \
             patch.object(provider, 'headers', return_value={'Authorization': 'Key test'}), \
             patch('server.firebase_animations.firestore.transactional', side_effect=lambda fn: fn):
            job = service.create(OWNER, 'mc-1', request())
            token, _ = service.claim(UID, job['id'])
            service.finish(UID, job['id'], token, asset=dict(id=job['id'], name='Dragon'), usage=None)
        self.assertEqual(studio.doc('studioJobs', job['id'])['charged'], 98)


class MeasureTests(unittest.TestCase):
    def test_a_real_clip_reports_its_own_size_and_length(self):
        width, height, seconds = provider.measure('docs/design/mascot-animations/raw/dragon-model.mp4')
        self.assertEqual((width, height), (640, 640))
        self.assertAlmostEqual(seconds, 4.04, places=1)

    def test_a_file_that_is_not_a_video_is_refused(self):
        import tempfile, pathlib
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'x.mp4'
            path.write_bytes(b'\x00\x00\x00\x18ftypmp42' + b'\x00' * 64)
            with self.assertRaises(ValueError):
                provider.measure(str(path))


class DeleteTests(unittest.TestCase):
    """An animated character deletes like a 3D object: its own file only."""
    def setUp(self):
        self.studio = Studio()
        ProjectFixture().build(self.studio)
        self.studio.put('mobileCreations', 'animation:an-1', projectId='mp-1', kind='Animated character',
                        conceptIds=['mc-1'], previewStoragePath=f'users/{UID}/images/mc-1.jpg',
                        animationStoragePath=f'users/{UID}/animations/an-1.mp4', createdAt=4)
        self.studio.put('studioJobs', 'an-1', projectId='mp-1', kind='animation', status='done', createdAt=4)
        self.studio.blobs[f'users/{UID}/animations/an-1.mp4'] = b'mp4'
        self.service = creations.CloudCreations(self.studio)

    def test_deleting_the_character_keeps_its_source_image(self):
        self.assertEqual(self.service.delete_asset(OWNER, 'an-1')['id'], 'an-1')
        self.assertIsNone(self.studio.doc('mobileCreations', 'animation:an-1'))
        self.assertIsNone(self.studio.doc('studioJobs', 'an-1'))
        self.assertNotIn(f'users/{UID}/animations/an-1.mp4', self.studio.blobs)
        self.assertIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)

    def test_deleting_the_image_keeps_a_file_the_animation_still_previews(self):
        self.service.delete_concept(OWNER, 'mc-1')
        self.assertIn(f'users/{UID}/images/mc-1.jpg', self.studio.blobs)

    def test_deleting_the_project_takes_the_animation_with_it(self):
        result = self.service.delete_project(OWNER, 'mp-1')
        self.assertEqual((result['models'], result['animations']), (1, 1))
        self.assertNotIn(f'users/{UID}/animations/an-1.mp4', self.studio.blobs)
        self.assertIsNone(self.studio.doc('mobileCreations', 'animation:an-1'))


if __name__ == '__main__':
    unittest.main()
