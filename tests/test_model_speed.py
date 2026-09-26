"""Concept image -> 3D latency: the finished model is collected within seconds.

Before, a submitted job returned 503 and waited for Cloud Tasks' growing retry
backoff to check the provider again, and the provider's own "finished" webhook
only recorded the event. Now the worker keeps polling inside its delivery and
the webhook wakes it immediately.
"""
import unittest
from pathlib import Path
from unittest.mock import patch, Mock
from fastapi import HTTPException
from fastapi.testclient import TestClient
from server import atlas_model_provider as atlas, firebase_model_jobs as mj, firebase_api as api


class Clock:
    def __init__(self): self.t = 5_000.0
    def __call__(self): return self.t
    def sleep(self, seconds): self.sleep_calls.append(seconds); self.t += seconds
    sleep_calls = None


def worker(clock):
    clock.sleep_calls = []
    w = object.__new__(mj.CloudModelJobs)
    w.now, w.sleep = clock, clock.sleep
    w.studio = Mock(); w.db = Mock()
    w.advance = Mock(return_value=True)
    w.finish = Mock(side_effect=lambda uid, jid, token, asset=None, error=None: {'status': 'done' if asset else 'failed', 'error': error})
    data = dict(phase='submitted', deadline=clock() + 3600, options={'engine': 'tripo'}, requestId='pred-1',
                endpoint='tripo-h3.1/image-to-3d', name='Cloud Dragon', views=[{'imageUrl': 'gs://b/users/u/images/c.jpg'}])
    w.claim = Mock(return_value=('lease', data))
    return w


class ModelSpeedTests(unittest.TestCase):
    def test_finished_model_is_collected_in_the_same_delivery(self):
        clock = Clock(); w = worker(clock)
        answers = iter([None, None, {'status': 'completed', 'outputs': ['https://cdn/model.glb']}])
        with patch.object(atlas, 'status', side_effect=lambda rid: next(answers)), \
             patch.object(atlas, 'download_mesh', side_effect=lambda result, target: Path(target).write_bytes(b'glTF')), \
             patch.object(mj, 'enqueue'):
            result = w.run('u', 'mj-1')
        self.assertEqual(result['status']['status'], 'done', 'no 503 hand-back while the provider finishes')
        self.assertEqual(clock.sleep_calls, [mj.POLL_INTERVAL] * 2)
        w.studio.bucket.blob.return_value.upload_from_filename.assert_called_once()

    def test_still_running_hands_back_after_a_bounded_window(self):
        clock = Clock(); w = worker(clock)
        status = Mock(return_value=None)
        with patch.object(atlas, 'status', status):
            with self.assertRaises(HTTPException) as raised:
                w.run('u', 'mj-1')
        self.assertEqual(raised.exception.status_code, 503)
        self.assertLessEqual(sum(clock.sleep_calls), mj.POLL_WINDOW)
        self.assertEqual(status.call_count, mj.POLL_WINDOW // mj.POLL_INTERVAL + 1, "checks at t=0,4,...,60")
        self.assertEqual(w.advance.call_args_list[-1].args[4], {'leaseUntil': 0}, 'the next delivery can claim at once')

    def test_stalled_clock_cannot_spin_the_worker_forever(self):
        clock = Clock(); w = worker(clock)
        w.sleep = lambda seconds: None          # time never advances
        status = Mock(return_value=None)
        with patch.object(atlas, 'status', status):
            with self.assertRaises(HTTPException):
                w.run('u', 'mj-1')
        self.assertEqual(status.call_count, mj.POLL_WINDOW // mj.POLL_INTERVAL + 1)

    def test_provider_failure_during_polling_releases_tokens(self):
        clock = Clock(); w = worker(clock)
        answers = iter([None, RuntimeError('failed')])
        def status(rid):
            a = next(answers)
            if isinstance(a, Exception): raise a
            return a
        with patch.object(atlas, 'status', side_effect=status):
            result = w.run('u', 'mj-1')
        self.assertEqual(result['status']['status'], 'failed')
        self.assertIn('Tokens have been released', w.finish.call_args.kwargs['error'])

    def test_finished_webhook_wakes_the_worker_and_survives_enqueue_failure(self):
        client = TestClient(api.app)
        body = {'session_id': 'pred-1', 'status': 'OK', 'event_type': 'image.task.terminal'}
        headers = {'X-AtlasCloud-Webhook-Key-Id': 'k'}
        with patch.object(api.cloud_model_provider.atlas_model_provider, 'verify_callback', return_value='pred-1'), \
             patch.object(api.CloudModelJobs, 'request_received'), patch.object(api, 'studio'), \
             patch.object(api.model_jobs, 'enqueue') as enqueue:
            self.assertEqual(client.post('/api/models/callback/u/mj-1/token', json=body, headers=headers).status_code, 200)
            enqueue.assert_called_once_with('u', 'mj-1')
            enqueue.side_effect = RuntimeError('tasks unavailable')
            self.assertEqual(client.post('/api/models/callback/u/mj-1/token', json=body, headers=headers).status_code, 200)

    def test_tripo_output_is_capped_for_phones(self):
        _, payload = atlas.arguments('tripo', ['https://atlas/media/c.jpg'])
        self.assertEqual(payload['face_limit'], 100_000)
        self.assertTrue(1_000 <= atlas.TRIPO_FACE_LIMIT <= 2_000_000, 'within the documented Tripo H3.1 range')


if __name__ == '__main__':
    unittest.main()
