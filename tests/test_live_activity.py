import unittest
from unittest.mock import patch
from fastapi import HTTPException

from server import live_activity
from tests.test_api_creations import Studio, UID

KEY_ENV = {'APNS_PRIVATE_KEY': '-----BEGIN PRIVATE KEY-----\nnot-a-real-key\n-----END PRIVATE KEY-----',
           'APNS_KEY_ID': 'ABC1234567', 'APNS_TEAM_ID': 'C265XC3RH7'}
TOKEN = 'a' * 64


def job(status='running', progress=40, kind='model', jid='mj-1'):
    return {'id': jid, 'status': status, 'progress': progress, 'kind': kind}


class RegisterTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()

    def test_token_is_stored_for_the_owner(self):
        result = live_activity.register(self.studio.db, UID, 'mj-1', TOKEN)
        self.assertTrue(result['registered'])
        self.assertEqual(live_activity.ref(self.studio.db, UID, 'mj-1').get().to_dict()['token'], TOKEN)

    def test_junk_is_refused(self):
        for jid, token in [('mj-1', 'not-hex!'), ('mj-1', 'ab'), ('../escape', TOKEN), ('other-1', TOKEN)]:
            with self.assertRaises(HTTPException, msg=f'{jid} {token}'):
                live_activity.register(self.studio.db, UID, jid, token)


class StateTests(unittest.TestCase):
    def test_states_match_the_app(self):
        queued = live_activity.content_state(job(status='queued', progress=0), 1)
        self.assertEqual((queued['phase'], queued['progress'], queued['finished']), ('thinking', 0.0, False))
        running = live_activity.content_state(job(), 3)
        self.assertEqual((running['phase'], running['progress'], running['frame']), ('model', 0.4, 3))
        concepts = live_activity.content_state(job(kind='concepts'), 1)
        self.assertEqual(concepts['phase'], 'concept')
        done = live_activity.content_state(job(status='done', progress=100), 1)
        self.assertEqual((done['finished'], done['failed'], done['progress']), (True, False, 1.0))
        failed = live_activity.content_state(job(status='failed', progress=0), 1)
        self.assertEqual((failed['finished'], failed['failed']), (False, True))

    def test_frames_stay_in_range(self):
        self.assertEqual(live_activity.content_state(job(), 9)['frame'], 6)
        self.assertEqual(live_activity.content_state(job(), 0)['frame'], 1)

    def test_payload_events(self):
        update = live_activity.payload(live_activity.content_state(job(), 1), 'update')['aps']
        self.assertEqual(update['event'], 'update')
        self.assertIn('stale-date', update)
        end = live_activity.payload(live_activity.content_state(job(status='done'), 1), 'end')['aps']
        self.assertEqual(end['event'], 'end')
        self.assertIn('dismissal-date', end)


class NotifyTests(unittest.TestCase):
    def setUp(self):
        self.studio = Studio()
        live_activity.register(self.studio.db, UID, 'mj-1', TOKEN)

    def test_running_job_pushes_an_update_and_advances_the_frame(self):
        with patch.dict('os.environ', KEY_ENV), patch.object(live_activity, 'send', return_value=200) as send:
            self.assertEqual(live_activity.notify(self.studio.db, UID, job()), 'update:200')
        body = send.call_args.args[1]['aps']
        self.assertEqual(body['event'], 'update')
        self.assertEqual(body['content-state']['frame'], 2)
        self.assertEqual(live_activity.ref(self.studio.db, UID, 'mj-1').get().to_dict()['frame'], 2)

    def test_finished_job_ends_the_activity_and_stops_tracking(self):
        with patch.dict('os.environ', KEY_ENV), patch.object(live_activity, 'send', return_value=200) as send:
            self.assertEqual(live_activity.notify(self.studio.db, UID, job(status='done', progress=100)), 'end:200')
        self.assertEqual(send.call_args.args[1]['aps']['event'], 'end')
        self.assertFalse(live_activity.ref(self.studio.db, UID, 'mj-1').get().exists)

    def test_dead_token_is_dropped(self):
        with patch.dict('os.environ', KEY_ENV), patch.object(live_activity, 'send', return_value=410):
            live_activity.notify(self.studio.db, UID, job())
        self.assertFalse(live_activity.ref(self.studio.db, UID, 'mj-1').get().exists)

    def test_push_failure_never_reaches_the_caller(self):
        with patch.dict('os.environ', KEY_ENV), patch.object(live_activity, 'send', side_effect=OSError('APNs down')):
            self.assertIsNone(live_activity.notify(self.studio.db, UID, job()))
        # The token is kept so the next job update can try again.
        self.assertTrue(live_activity.ref(self.studio.db, UID, 'mj-1').get().exists)

    def test_nothing_is_sent_without_keys_or_without_a_registered_activity(self):
        with patch.dict('os.environ', {'APNS_PRIVATE_KEY': '', 'APNS_KEY_ID': '', 'APNS_TEAM_ID': ''}), \
             patch.object(live_activity, 'send') as send:
            self.assertIsNone(live_activity.notify(self.studio.db, UID, job()))
            send.assert_not_called()
        with patch.dict('os.environ', KEY_ENV), patch.object(live_activity, 'send') as send:
            self.assertIsNone(live_activity.notify(self.studio.db, UID, job(jid='mj-unknown')))
            send.assert_not_called()


if __name__ == '__main__':
    unittest.main()
