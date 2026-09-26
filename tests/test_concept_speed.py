"""End-to-end concept jobs against in-memory Firestore and Storage.

These pin down the latency work: a whole job finishes inside one worker
delivery, the turnaround views after the front view render concurrently, and a
view that fails or is interrupted is skipped rather than paid for twice.
"""
import copy, io, json, threading, time, unittest
from unittest.mock import patch
from fastapi import HTTPException
from google.api_core.exceptions import NotFound, PreconditionFailed
from PIL import Image
from server import cloud_concept_provider as provider
from server import firebase_concepts as fc
from server.firebase_usage import reserve


def png():
    out = io.BytesIO(); Image.new('RGB', (64, 64), (90, 140, 220)).save(out, format='JPEG'); return out.getvalue()
PIXELS = png()


class Snap:
    def __init__(self, data): self._d = copy.deepcopy(data)
    @property
    def exists(self): return self._d is not None
    def to_dict(self): return copy.deepcopy(self._d)


class Doc:
    def __init__(self, db, path): self.db, self.path = db, path
    def collection(self, name): return Col(self.db, self.path + '/' + name)
    def get(self, transaction=None): return Snap(self.db.docs.get(self.path))


class Col:
    def __init__(self, db, path): self.db, self.path = db, path
    def document(self, ident): return Doc(self.db, self.path + '/' + ident)


class Tx:
    def __init__(self, db): self.db = db
    def update(self, ref, data):
        if ref.path not in self.db.docs: raise NotFound('missing ' + ref.path)
        self.db.docs[ref.path].update(copy.deepcopy(data))
    def create(self, ref, data):
        if ref.path in self.db.docs: raise AssertionError('already exists ' + ref.path)
        self.db.docs[ref.path] = copy.deepcopy(data)
    def set(self, ref, data, merge=False):
        self.db.docs[ref.path] = {**(self.db.docs.get(ref.path) or {}), **copy.deepcopy(data)} if merge else copy.deepcopy(data)


class DB:
    def __init__(self): self.docs, self.lock = {}, threading.Lock()
    def collection(self, name): return Col(self, name)


class Blob:
    def __init__(self, bucket, name): self.bucket, self.name = bucket, name; self.metadata = None; self.cache_control = None
    def reload(self, timeout=None):
        stored = self.bucket.store.get(self.name)
        if not stored: raise NotFound(self.name)
        self.metadata = stored['metadata']; self.size = len(stored['bytes']); self.generation = 1
    def upload_from_string(self, raw, content_type=None, if_generation_match=None, timeout=None, retry=None):
        with self.bucket.lock:
            if self.name in self.bucket.store: raise PreconditionFailed(self.name)
            self.bucket.store[self.name] = {'bytes': raw, 'metadata': dict(self.metadata or {})}
    def download_as_bytes(self, if_generation_match=None, timeout=None): return self.bucket.store[self.name]['bytes']


class Bucket:
    def __init__(self): self.store, self.lock = {}, threading.Lock()
    def blob(self, name): return Blob(self, name)


class Studio:
    def __init__(self): self.db, self.bucket = DB(), Bucket()


class FakeProvider:
    """Records concurrency and every paid render call."""
    def __init__(self, delay=0.3, fail=()):
        self.delay, self.fail = delay, set(fail)
        self.calls, self.active, self.peak, self.lock = [], 0, 0, threading.Lock()
    def render(self, payload, rates, model=None):
        text = payload['contents'][0]['parts'][-1]['text']
        index = next(i for i, v in enumerate(provider.VIEWS) if v[2] in text)
        with self.lock:
            self.calls.append(index); self.active += 1; self.peak = max(self.peak, self.active)
        try:
            time.sleep(self.delay)
            if index in self.fail: raise provider.planner.PlannerError('No complete concept was returned.')
            return {'bytes': PIXELS, 'width': 1024, 'height': 1024, 'model': provider.MODEL, 'usage': {}, 'providerUsd': '0.1', 'tokens': 6}
        finally:
            with self.lock: self.active -= 1


class Clock:
    def __init__(self): self.t = 1_000_000.0
    def __call__(self): return self.t


def seed(studio, clock, count=4, **private):
    uid, jid, pid = 'u1', 'cj-test', 'p1'
    db = studio.db
    db.docs[f'users/{uid}/studioProjects/{pid}'] = {'ownerId': uid, 'name': 'Cloud Dragon', 'prompt': 'a blue dragon'}
    estimate = provider.quote(clock(), count)
    wallet = {'available': 500, 'environment': 'PRODUCTION'}
    after, allocation = reserve(wallet, estimate['maxTokens'], clock())
    db.docs[f'users/{uid}/private/wallet'] = after
    ids = [f'mc-{i}' for i in range(count)]
    db.docs[f'users/{uid}/studioJobs/{jid}'] = dict(id=jid, ownerId=uid, projectId=pid, status='queued', concepts=[], assets=[])
    db.docs[f'users/{uid}/private/conceptJobs/items/{jid}'] = dict(
        phase='plan_ready', options={}, estimate=estimate, allocation=allocation, walletName='wallet', projectId=pid,
        source=None, selected=None, mode='angles', words='a tiny blue dragon', style='Stylized', name='Cloud Dragon',
        ids=ids, index=0, outputs=[], createdAt=clock(), deadline=clock() + 1800, leaseUntil=0, **private)
    return uid, jid


class ConceptSpeedTests(unittest.TestCase):
    def setUp(self):
        self.studio, self.clock = Studio(), Clock()
        self.worker = fc.CloudConcepts(self.studio, clock=self.clock)
        self.plans, self.audits = [], []
        def plan(payload, rates):
            audit = 'turnaround views' in payload['systemInstruction']['parts'][0]['text']
            (self.audits if audit else self.plans).append(1)
            return {'prompt': 'PASS' if audit else 'A tiny blue dragon, clean 3D reference', 'tokens': 1}
        self.patches = [
            patch.object(fc, 'transact', side_effect=lambda db, fn: fn(Tx(db))),
            patch.object(fc, 'uid_for', side_effect=lambda owner: owner.removeprefix('firebase:')),
            patch.object(provider.planner, 'preflight', return_value=10),
            patch.object(provider.planner, 'generate', side_effect=plan),
            patch.object(provider, 'preflight', return_value=10),
            patch('server.live_activity.notify'),
        ]
        for p in self.patches: p.start()
    def tearDown(self):
        for p in self.patches: p.stop()

    def job(self, uid, jid):
        return (self.studio.db.docs[f'users/{uid}/studioJobs/{jid}'],
                self.studio.db.docs[f'users/{uid}/private/conceptJobs/items/{jid}'])

    def test_four_views_finish_in_one_delivery_with_parallel_turnaround(self):
        uid, jid = seed(self.studio, self.clock)
        fake = FakeProvider(delay=0.35)
        with patch.object(provider, 'generate', side_effect=fake.render):
            started = time.time(); result = self.worker.run(uid, jid); elapsed = time.time() - started
        public, private = self.job(uid, jid)
        self.assertEqual(result['status'], 'done')
        self.assertEqual(public['status'], 'done')
        self.assertEqual(sorted(fake.calls), [0, 1, 2, 3], 'each view is paid for exactly once')
        self.assertEqual(fake.calls[0], 0, 'the front view renders first; the others need it as reference')
        self.assertEqual(fake.peak, 3, 'back, left and right render concurrently')
        self.assertLess(elapsed, 0.35 * 2 + 0.3, 'two render rounds, not four')
        self.assertEqual([c['direction'] for c in public['concepts']], ['front', 'back', 'left', 'right'])
        self.assertEqual(len(self.plans), 1); self.assertEqual(len(self.audits), 1)
        self.assertEqual(public['charged'], 4 * 6 + 1 + 1)

    def test_failed_view_is_skipped_not_repaid_and_labels_stay_true(self):
        uid, jid = seed(self.studio, self.clock)
        fake = FakeProvider(delay=0.05, fail={2})
        captured = {}
        real_audit = provider.audit_body
        def audit(images, directions): captured['directions'] = directions; return real_audit(images, directions)
        with patch.object(provider, 'generate', side_effect=fake.render), patch.object(provider, 'audit_body', side_effect=audit):
            result = self.worker.run(uid, jid)
        public, _ = self.job(uid, jid)
        self.assertEqual(result['status'], 'partial')
        self.assertEqual(sorted(fake.calls), [0, 1, 2, 3], 'the failed view is not retried')
        self.assertEqual([c['direction'] for c in public['concepts']], ['front', 'back', 'right'])
        self.assertEqual(captured['directions'], ['front', 'back', 'right'], 'audit labels follow the real views')
        self.assertEqual(public['charged'], 3 * 6 + 1 + 1, 'the failed view is not charged')

    def test_interrupted_batch_publishes_saved_views_without_new_calls(self):
        uid, jid = seed(self.studio, self.clock)
        # The front view was published; the worker then died during the batch.
        _, private = self.job(uid, jid)
        private.update(phase='batch_calling', index=1, batch=[1, 2, 3], brief='A tiny blue dragon',
                       outputs=[{'id': 'mc-0', 'path': f'users/{uid}/images/mc-0.jpg', 'width': 1024, 'height': 1024, 'tokens': 6, 'index': 0}])
        for i in (0, 1, 3):  # view 2 never came back
            made = {'width': 1024, 'height': 1024, 'model': provider.MODEL, 'usage': {}, 'providerUsd': '0.1', 'tokens': 6}
            self.studio.bucket.store[f'users/{uid}/images/mc-{i}.jpg'] = {'bytes': PIXELS, 'metadata': {'ownerId': uid, 'jobId': jid, 'index': str(i), 'result': json.dumps(made)}}
        fake = FakeProvider()
        with patch.object(provider, 'generate', side_effect=fake.render):
            result = self.worker.run(uid, jid)
        public, _ = self.job(uid, jid)
        self.assertEqual(fake.calls, [], 'recovery never issues another paid render')
        self.assertEqual(result['status'], 'partial')
        self.assertEqual([c['direction'] for c in public['concepts']], ['back', 'right'])

    def test_long_delivery_hands_back_to_cloud_tasks_and_resumes(self):
        uid, jid = seed(self.studio, self.clock)
        fake = FakeProvider(delay=0.01)
        def slow(payload, rates, model=None):
            self.clock.t += fc.STAGE_BUDGET + 1  # every render looks slow on the wall clock
            return fake.render(payload, rates)
        with patch.object(provider, 'generate', side_effect=slow):
            with self.assertRaises(HTTPException) as raised:
                self.worker.run(uid, jid)
            self.assertEqual(raised.exception.status_code, 503)
            _, private = self.job(uid, jid)
            self.assertEqual(private['leaseUntil'], 0, 'the next delivery can claim immediately')
            for _ in range(5):
                try: result = self.worker.run(uid, jid); break
                except HTTPException as e: self.assertEqual(e.status_code, 503)
        self.assertEqual(result['status'], 'done')
        self.assertEqual(sorted(fake.calls), [0, 1, 2, 3])

    def test_single_concept_still_one_render(self):
        uid, jid = seed(self.studio, self.clock, count=1)
        fake = FakeProvider(delay=0.01)
        with patch.object(provider, 'generate', side_effect=fake.render):
            result = self.worker.run(uid, jid)
        self.assertEqual(result['status'], 'done'); self.assertEqual(fake.calls, [0]); self.assertEqual(self.audits, [])


    def test_fast_model_job_renders_with_it_and_labels_it(self):
        uid, jid = seed(self.studio, self.clock)
        _, private = self.job(uid, jid)
        private['estimate'] = provider.quote(self.clock(), 4, provider.FAST_MODEL)
        seen = []
        fake = FakeProvider(delay=0.01)
        def render(payload, rates, model=provider.MODEL):
            seen.append((model, payload['generationConfig']['imageConfig']['imageSize'])); return fake.render(payload, rates)
        with patch.object(provider, 'generate', side_effect=render):
            self.worker.run(uid, jid)
        public, _ = self.job(uid, jid)
        self.assertEqual(set(seen), {(provider.FAST_MODEL, '1K')})
        self.assertEqual({c['imageModel'] for c in public['concepts']}, {provider.FAST_MODEL})


class FastModelContractTests(unittest.TestCase):
    def result(self, side, tokens=1120):
        raw = io.BytesIO(); Image.new('RGB', (side, side)).save(raw, format='PNG')
        import base64
        return {'candidates': [{'finishReason': 'STOP', 'content': {'parts': [{'inlineData': {'mimeType': 'image/png', 'data': base64.b64encode(raw.getvalue()).decode()}}]}}],
                'usageMetadata': {'promptTokenCount': 19, 'candidatesTokenCount': 1550, 'candidatesTokensDetails': [{'modality': 'IMAGE', 'tokenCount': tokens}]}}

    def test_fast_decode_verifies_1k_usage_and_bills_nano_banana_2_rates(self):
        from decimal import Decimal
        decoded = provider.decode(self.result(1024), provider.SPECS[provider.FAST_MODEL]['rates'], provider.FAST_MODEL)
        self.assertEqual((decoded['width'], decoded['model']), (1024, provider.FAST_MODEL))
        # 19 input x $0.50 + 430 text x $3 + 1,120 image x $60, per million — measured 2026-09-26.
        self.assertEqual(Decimal(decoded['providerUsd']), Decimal('.0684995'))
        with self.assertRaises(provider.planner.PlannerError):   # a 2K image is not what the user was quoted for
            provider.decode(self.result(2048), provider.SPECS[provider.FAST_MODEL]['rates'], provider.FAST_MODEL)

    def test_fast_quote_is_cheaper_and_pro_quote_unchanged(self):
        fast, pro = provider.quote(0, 4, provider.FAST_MODEL), provider.quote(0, 4)
        self.assertEqual(pro['maxTokens'], 128, 'released apps approved this exact Pro price')
        self.assertLess(fast['maxTokens'], pro['maxTokens'])
        self.assertEqual((fast['imageSize'], pro['imageSize']), ('1K', '2K'))
        self.assertEqual(provider.body('x', None, provider.FAST_MODEL)['generationConfig']['imageConfig']['imageSize'], '1K')
        from server.firebase_concepts import ConceptRequest
        self.assertEqual(ConceptRequest(idempotencyKey='request-1', maxTokens=40, imageModel=provider.FAST_MODEL).imageModel, provider.FAST_MODEL)

    def test_catalog_offers_fast_without_moving_released_app_fields(self):
        from server import firebase_api as api
        with patch.object(api, 'concepts_ready', return_value=True):
            cat = api.image_model_catalog()
        self.assertEqual(cat['defaultModel'], provider.MODEL)
        self.assertEqual(cat['maxTokensByCount'], cat['maxTokensByModel'][provider.MODEL])
        self.assertEqual([m['id'] for m in cat['models']], [provider.FAST_MODEL, provider.MODEL])
        self.assertEqual(cat['models'][0]['imageSize'], '1K')


if __name__ == '__main__':
    unittest.main()
