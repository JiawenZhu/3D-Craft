import hashlib
import time
import unittest
from unittest.mock import Mock, patch
from fastapi.testclient import TestClient

from server import api_keys
from server import firebase_api as api
from server.identity import require_claims
from firebase_admin import auth


class MockDocRef:
    def __init__(self, data=None, parent_collection=None, doc_id=None):
        self._data = dict(data) if data is not None else {}
        self._exists = data is not None
        self._parent = parent_collection
        self._subcollections = {}
        self.id = doc_id or "mock_id"

    def get(self, transaction=None):
        if transaction is not None and getattr(transaction, "_has_written", False):
            raise RuntimeError("Firestore transactions do not allow reads after writes. All reads must precede all writes.")
        m = Mock()
        m.exists = self._exists
        m.to_dict.return_value = dict(self._data) if self._exists else None
        m.reference = self
        m.id = self.id
        return m

    def create(self, data):
        if self._exists:
            from google.api_core.exceptions import AlreadyExists
            raise AlreadyExists("Document already exists")
        self._data = dict(data)
        self._exists = True
        if self._parent is not None:
            self._parent._docs[self.id] = self

    def set(self, data, merge=False):
        if merge and self._exists:
            def merge_map(target, changes):
                for key, value in changes.items():
                    if isinstance(value, dict) and value and isinstance(target.get(key), dict):
                        merge_map(target[key], value)
                    else:
                        target[key] = value
            merge_map(self._data, data)
        else:
            self._data = dict(data)
        self._exists = True
        if self._parent is not None:
            self._parent._docs[self.id] = self

    def update(self, data):
        if not self._exists:
            from google.api_core.exceptions import NotFound
            raise NotFound("Document does not exist")
        for k, v in data.items():
            if v is None or getattr(v, '__class__', None).__name__ == '_Sentinel' or 'Sentinel' in str(type(v)) or str(v).startswith('Sentinel'):
                self._data.pop(k, None)
            else:
                self._data[k] = v

    def delete(self):
        self._data = {}
        self._exists = False
        if self._parent is not None:
            self._parent._docs.pop(self.id, None)

    def collection(self, name):
        if name not in self._subcollections:
            self._subcollections[name] = MockCollection(name)
        return self._subcollections[name]


class MockCollection:
    def __init__(self, name):
        self.name = name
        self._docs = {}

    def document(self, doc_id):
        if doc_id not in self._docs:
            self._docs[doc_id] = MockDocRef(parent_collection=self, doc_id=doc_id)
        return self._docs[doc_id]

    def where(self, filter=None):
        filtered = MockQuery(self._docs)
        if filter:
            filtered = filtered.where(filter)
        return filtered

    def order_by(self, field, direction=None):
        return MockQuery(self._docs).order_by(field, direction)

    def limit(self, count):
        return MockQuery(self._docs).limit(count)

    def stream(self):
        return MockQuery(self._docs).stream()


class MockQuery:
    def __init__(self, docs_dict):
        self.docs_dict = docs_dict
        self.filters = []

    def where(self, filter):
        q = MockQuery(self.docs_dict)
        q.filters = list(self.filters)
        q.filters.append(filter)
        return q

    def order_by(self, field, direction=None):
        return self

    def limit(self, count):
        return self

    def stream(self):
        results = []
        for doc in self.docs_dict.values():
            if not doc._exists:
                continue
            match = True
            for f in self.filters:
                field = getattr(f, "field_path", None)
                val = getattr(f, "value", None)
                op = getattr(f, "op_string", "==")
                if op == "==" and doc._data.get(field) != val:
                    match = False
                    break
            if match:
                results.append(doc.get())
        return results

    def get(self, transaction=None):
        if transaction is not None and getattr(transaction, "_has_written", False):
            raise RuntimeError("Firestore transactions do not allow reads after writes. All reads must precede all writes.")
        return self.stream()


class MockTransaction:
    _read_only = False
    _max_attempts = 1
    _id = b"mock_tx"

    def __init__(self):
        self._has_written = False

    def get(self, ref_or_query):
        if self._has_written:
            raise RuntimeError("Firestore transactions do not allow reads after writes. All reads must precede all writes.")
        return ref_or_query.get(transaction=self)

    def set(self, ref, data, merge=False):
        self._has_written = True
        ref.set(data, merge=merge)

    def update(self, ref, data):
        self._has_written = True
        ref.update(data)

    def create(self, ref, data):
        self._has_written = True
        ref.create(data)

    def delete(self, ref):
        self._has_written = True
        ref.delete()

    def _clean_up(self):
        pass

    def _rollback(self):
        pass


class MockFirestore:
    def __init__(self):
        self._collections = {}

    def collection(self, name):
        if name not in self._collections:
            self._collections[name] = MockCollection(name)
        return self._collections[name]

    def transaction(self):
        return MockTransaction()


class ApiKeysSecurityTests(unittest.TestCase):
    def setUp(self):
        self.tx_patches = [
            patch('server.api_keys.firestore.transactional', side_effect=lambda fn: fn),
            patch('server.firebase_planning.firestore.transactional', side_effect=lambda fn: fn),
            patch('server.firebase_billing.firestore.transactional', side_effect=lambda fn: fn),
        ]
        for p in self.tx_patches:
            p.start()
        self.client = TestClient(api.app)
        self.mock_db = MockFirestore()
        self.mock_studio = Mock()
        self.mock_studio.db = self.mock_db
        self.mock_bucket = Mock()
        self.mock_studio.bucket = self.mock_bucket

    def tearDown(self):
        api.app.dependency_overrides.clear()
        for p in self.tx_patches:
            p.stop()

    def test_one_time_issuance_and_hashed_storage(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False
            created = api_keys.create_api_key(
                self.mock_db, uid="user_alice", name="Claude Agent Key", scopes=["*"]
            )

        raw_key = created["key"]
        self.assertTrue(raw_key.startswith("craft_live_"))
        self.assertEqual(created["name"], "Claude Agent Key")
        self.assertIn("craft_live_", created["prefix"])
        self.assertIn("...", created["prefix"])
        self.assertIn("warning", created)

        # Check stored document in firestore mock
        expected_hash = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()
        stored_doc = self.mock_db.collection("apiKeys").document(expected_hash).get()
        self.assertTrue(stored_doc.exists)
        stored_data = stored_doc.to_dict()

        # Plaintext key MUST NEVER be stored
        self.assertNotIn(raw_key, str(stored_data))
        self.assertEqual(stored_data["keyHash"], expected_hash)
        self.assertEqual(stored_data["ownerId"], "user_alice")
        self.assertFalse(stored_data["revoked"])

    def test_list_keys_metadata_never_leaks_hash_or_plaintext(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False
            api_keys.create_api_key(self.mock_db, "user_alice", "Key 1")
            api_keys.create_api_key(self.mock_db, "user_alice", "Key 2")

            listed = api_keys.list_api_keys(self.mock_db, "user_alice")
            self.assertEqual(len(listed), 2)
            for item in listed:
                self.assertNotIn("key", item)
                self.assertNotIn("keyHash", item)
                self.assertIn("prefix", item)
                self.assertIn("id", item)
                self.assertIn("name", item)

    def test_active_key_limit_atomic_bounded_to_five(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False

            # Create 5 active keys
            keys = []
            for i in range(5):
                k = api_keys.create_api_key(self.mock_db, "user_alice", f"Key {i}")
                keys.append(k)

            # 6th key should fail atomically
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                api_keys.create_api_key(self.mock_db, "user_alice", "Key 6")
            self.assertEqual(ctx.exception.status_code, 400)
            self.assertIn("limit reached", ctx.exception.detail)

            # Revoke one key, creating 6th should succeed
            api_keys.revoke_api_key(self.mock_db, "user_alice", keys[0]["id"])
            k6 = api_keys.create_api_key(self.mock_db, "user_alice", "Key 6")
            self.assertIsNotNone(k6["key"])

    def test_unauthorized_key_management(self):
        # API keys cannot call /api/keys
        api.app.dependency_overrides[require_claims] = lambda: {"uid": "alice"}
        with patch.object(api, "studio", return_value=self.mock_studio), patch("firebase_admin.auth.verify_id_token", return_value={"uid": "alice"}), patch("firebase_admin.auth.get_user", return_value=Mock(disabled=False)):
            # Normal user with Firebase ID token can access
            res = self.client.get("/api/keys", headers={"Authorization": "Bearer fake_firebase_token"})
            self.assertEqual(res.status_code, 200)

            # API key bearer cannot access /api/keys
            res_forbidden = self.client.get("/api/keys", headers={"Authorization": "Bearer craft_live_sometoken"})
            self.assertEqual(res_forbidden.status_code, 403)

            # API key bearer cannot create key
            res_create = self.client.post("/api/keys", json={"name": "SubKey"},
                                          headers={"Authorization": "Bearer craft_live_sometoken"})
            self.assertEqual(res_create.status_code, 403)

    def test_key_management_auth_errors_fail_closed(self):
        api.app.dependency_overrides[require_claims] = lambda: {"uid": "alice"}
        for error in (ValueError("bad auth"), RuntimeError("service unavailable")):
            with self.subTest(error=type(error).__name__), patch("firebase_admin.auth.verify_id_token", side_effect=error), patch.object(api, "studio") as cloud:
                result = self.client.get("/api/keys", headers={"Authorization": "Bearer fixture"})
                self.assertEqual(result.status_code, 503)
                cloud.assert_not_called()
        with patch("firebase_admin.auth.verify_id_token", return_value={"uid": "alice"}), patch("firebase_admin.auth.get_user", side_effect=RuntimeError("unavailable")), patch.object(api, "studio") as cloud:
            result = self.client.get("/api/keys", headers={"Authorization": "Bearer fixture"})
            self.assertEqual(result.status_code, 503)
            cloud.assert_not_called()

    def test_api_keys_forbidden_on_mobile_and_sensitive_routes(self):
        # API keys are rejected on all /api/mobile/... and non-v1 routes
        with patch.object(api, "studio", return_value=self.mock_studio):
            res_mobile_wallet = self.client.get(
                "/api/mobile/wallet",
                headers={"Authorization": "Bearer craft_live_validtoken"},
            )
            self.assertEqual(res_mobile_wallet.status_code, 403)

            res_del = self.client.post(
                "/api/mobile/account/delete",
                json={"confirm": True},
                headers={"Authorization": "Bearer craft_live_validtoken"},
            )
            self.assertEqual(res_del.status_code, 403)

            res_purchase = self.client.post(
                "/api/mobile/purchases/revenuecat",
                json={"productId": "prod", "transactionId": "tx"},
                headers={"Authorization": "Bearer craft_live_validtoken"},
            )
            self.assertEqual(res_purchase.status_code, 403)

    def test_production_billing_cannot_be_spoofed(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user, \
             patch.object(api, "CloudBilling") as mock_billing_cls:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            created = api_keys.create_api_key(self.mock_db, "user_alice", "Wallet Key")
            raw_key = created["key"]

            mock_billing_inst = Mock()
            mock_billing_inst.wallet.return_value = {"available": 500, "environment": "PRODUCTION"}
            mock_billing_cls.return_value = mock_billing_inst

            # Access v1 wallet with API key
            res = self.client.get(
                "/api/v1/wallet",
                headers={"Authorization": f"Bearer {raw_key}"},
            )
            self.assertEqual(res.status_code, 200)
            self.assertEqual(res.json()["note"], api.V1_BILLING_NOTE)
            # Environment must be strictly PRODUCTION
            mock_billing_inst.wallet.assert_called_once_with("user_alice", environment="PRODUCTION")

    def test_revoked_key_rejected(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            created = api_keys.create_api_key(self.mock_db, "user_alice", "Test Key")
            raw_key = created["key"]
            key_id = created["id"]

            # Key verifies before revocation
            uid, _ = api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(uid, "user_alice")

            # Revoke
            api_keys.revoke_api_key(self.mock_db, "user_alice", key_id)

            # Key fails after revocation
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertIn("revoked", ctx.exception.detail)

    def test_expired_key_rejected(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            raw_key, key_hash, key_id, meta = api_keys.generate_key_pair("Expired Key")
            meta["expiresAt"] = time.time() - 100  # Past
            doc_data = dict(meta)
            doc_data["ownerId"] = "user_alice"
            doc_data["keyHash"] = key_hash
            self.mock_db.collection("apiKeys").document(key_hash).set(doc_data)

            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertIn("expired", ctx.exception.detail)

    def test_disabled_or_deleted_uid_fails_closed(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            created = api_keys.create_api_key(self.mock_db, "user_alice", "Key")
            raw_key = created["key"]

            from fastapi import HTTPException

            # 1. Disabled account in Firebase Auth
            mock_user.disabled = True
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertIn("disabled", ctx.exception.detail)

            # 2. Deleted user in Firebase Auth
            mock_get_user.side_effect = auth.UserNotFoundError("User deleted")
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 401)
            self.assertIn("no longer exists", ctx.exception.detail)

            # 3. Account deletion scheduled in Firestore
            mock_get_user.side_effect = None
            mock_user.disabled = False
            mock_req.return_value.get.return_value.exists = True
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertIn("deleted or requested deletion", ctx.exception.detail)

    def test_scope_enforcement(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            created = api_keys.create_api_key(
                self.mock_db, "user_alice", "Wallet Only", scopes=["wallet:read"]
            )
            raw_key = created["key"]

            # wallet:read passes
            uid, _ = api_keys.verify_api_key(self.mock_db, raw_key, required_scope="wallet:read")
            self.assertEqual(uid, "user_alice")

            # models:write fails
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key, required_scope="models:write")
            self.assertEqual(ctx.exception.status_code, 403)

    def test_distributed_rate_quota_in_firestore(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock()
            mock_user.disabled = False
            mock_get_user.return_value = mock_user

            created = api_keys.create_api_key(self.mock_db, "user_alice", "Burst Key")
            raw_key = created["key"]

            # 60 requests pass
            for _ in range(60):
                api_keys.verify_api_key(self.mock_db, raw_key)

            # 61st fails with 429
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                api_keys.verify_api_key(self.mock_db, raw_key)
            self.assertEqual(ctx.exception.status_code, 429)
            self.assertEqual(ctx.exception.headers.get("Retry-After"), "60")

    def test_account_deletion_cleans_up_api_keys(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False
            api_keys.create_api_key(self.mock_db, "user_alice", "Key 1")
            api_keys.create_api_key(self.mock_db, "user_alice", "Key 2")
            api_keys.create_api_key(self.mock_db, "user_bob", "Bob Key")

            self.assertEqual(len(api_keys.list_api_keys(self.mock_db, "user_alice")), 2)
            self.assertEqual(len(api_keys.list_api_keys(self.mock_db, "user_bob")), 1)

            deleted_count = api_keys.delete_keys_for_user(self.mock_db, "user_alice")
            self.assertEqual(deleted_count, 2)
            self.assertEqual(len(api_keys.list_api_keys(self.mock_db, "user_alice")), 0)
            self.assertEqual(len(api_keys.list_api_keys(self.mock_db, "user_bob")), 1)

    def test_openapi_v1_spec_has_complete_schemas(self):
        res = self.client.get("/api/v1/openapi.json")
        self.assertEqual(res.status_code, 200)
        spec = res.json()
        self.assertEqual(spec["openapi"], "3.1.0")
        schemas = spec["components"]["schemas"]
        self.assertIn("ConceptRequest", schemas)
        self.assertIn("ModelRequest", schemas)
        self.assertIn("PromptRequest", schemas)
        self.assertIn("ChatRequest", schemas)
        self.assertIn("WalletResponse", schemas)
        self.assertIn("/api/v1/wallet", spec["paths"])
        self.assertIn("/api/v1/concepts/{concept_id}/model", spec["paths"])
        self.assertIn("/api/v1/planning/prompt", spec["paths"])
        self.assertIn("/api/v1/assets/{asset_id}/download", spec["paths"])

    def test_scope_precedence_model_requires_models_write_not_concepts_write(self):
        # Verify route scope mapping directly
        self.assertEqual(api.required_scope_for_path("/api/v1/concepts/c123/model", "POST"), "models:write")
        self.assertEqual(api.required_scope_for_path("/api/v1/concepts/c123/refine", "POST"), "concepts:write")
        self.assertEqual(api.required_scope_for_path("/api/v1/projects/p123/concepts", "POST"), "concepts:write")

        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock(disabled=False)
            mock_get_user.return_value = mock_user

            # 1. Key with only concepts:write should be REJECTED on /model
            concept_key = api_keys.create_api_key(
                self.mock_db, "user_alice", "Concept Only Key", scopes=["concepts:write"]
            )["key"]
            res_concept_on_model = self.client.post(
                "/api/v1/concepts/c123/model",
                json={"idempotencyKey": "key_concept_001", "maxTokens": 100},
                headers={"Authorization": f"Bearer {concept_key}"},
            )
            self.assertEqual(res_concept_on_model.status_code, 403)
            self.assertIn("models:write", res_concept_on_model.json().get("detail", ""))

            # 2. Key with only models:write should be ALLOWED on /model (passes auth, hits generation check)
            model_key = api_keys.create_api_key(
                self.mock_db, "user_alice", "Model Only Key", scopes=["models:write"]
            )["key"]
            res_model_on_model = self.client.post(
                "/api/v1/concepts/c123/model",
                json={"idempotencyKey": "key_model_002", "maxTokens": 100},
                headers={"Authorization": f"Bearer {model_key}"},
            )
            # Should NOT be 403 scope forbidden! Since generation is not enabled in test env, 503 is expected
            self.assertNotEqual(res_model_on_model.status_code, 403)
            self.assertEqual(res_model_on_model.status_code, 503)

            # 3. Key with only models:write should be REJECTED on /concepts
            res_model_on_concept = self.client.post(
                "/api/v1/projects/p123/concepts",
                json={"idempotencyKey": "key_concept_003", "maxTokens": 10, "prompt": "test"},
                headers={"Authorization": f"Bearer {model_key}"},
            )
            self.assertEqual(res_model_on_concept.status_code, 403)
            self.assertIn("concepts:write", res_model_on_concept.json().get("detail", ""))

    def test_actual_ledger_reservation_forces_production_wallet_and_preserves_sandbox(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user, \
             patch("server.firebase_planning.enqueue") as mock_enqueue, \
             patch.dict("os.environ", {"CRAFT_PLANNING_ENABLED": "1", "CRAFT_REVENUECAT_SANDBOX": "1"}):
            mock_req.return_value.get.return_value.exists = False
            mock_user = Mock(disabled=False)
            mock_get_user.return_value = mock_user

            uid = "user_alice"
            # Set up user's shared billingContext as SANDBOX
            self.mock_db.collection("users").document(uid).collection("private").document("billingContext").set({
                "environment": "SANDBOX"
            })
            # Set up sandboxWallet with 500 tokens
            self.mock_db.collection("users").document(uid).collection("private").document("sandboxWallet").set({
                "available": 500,
                "subscriptionAvailable": 0,
                "purchasedAvailable": 500,
                "environment": "SANDBOX",
            })
            # Set up production wallet with 1000 tokens
            self.mock_db.collection("users").document(uid).collection("private").document("wallet").set({
                "available": 1000,
                "subscriptionAvailable": 0,
                "purchasedAvailable": 1000,
                "environment": "PRODUCTION",
            })

            # Create API key for user
            api_key = api_keys.create_api_key(self.mock_db, uid, "Pipeline Key", scopes=["prompt:write"])["key"]

            # 1. First request through /api/v1/planning/prompt
            payload = {
                "idempotencyKey": "test-idem-key-100",
                "maxTokens": 10,
                "prompt": "Design a low-poly medieval lighthouse",
            }
            res = self.client.post(
                "/api/v1/planning/prompt",
                json=payload,
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res.status_code, 200, res.text)
            job = res.json()
            self.assertIn("id", job)
            self.assertEqual(job["status"], "queued")
            job_id = job["id"]

            # Assert PRODUCTION wallet was decremented transactionally
            prod_wallet = self.mock_db.collection("users").document(uid).collection("private").document("wallet").get().to_dict()
            self.assertEqual(prod_wallet["available"], 998)
            self.assertEqual(prod_wallet["reserved"], 2)

            # Assert ledger entry exists in PRODUCTION wallet
            prod_entries = self.mock_db.collection("users").document(uid).collection("private").document("wallet").collection("entries").stream()
            self.assertEqual(len(prod_entries), 1)
            self.assertEqual(prod_entries[0].to_dict()["id"], f"{job_id}:reserve")
            self.assertEqual(prod_entries[0].to_dict()["amount"], -2)

            # Assert SANDBOX wallet is COMPLETELY UNTOUCHED
            sb_wallet = self.mock_db.collection("users").document(uid).collection("private").document("sandboxWallet").get().to_dict()
            self.assertEqual(sb_wallet["available"], 500)
            self.assertEqual(sb_wallet["subscriptionAvailable"], 0)
            self.assertNotIn("reserved", sb_wallet)
            sb_entries = self.mock_db.collection("users").document(uid).collection("private").document("sandboxWallet").collection("entries").stream()
            self.assertEqual(len(sb_entries), 0)

            # Assert shared billingContext is UNTOUCHED
            b_context = self.mock_db.collection("users").document(uid).collection("private").document("billingContext").get().to_dict()
            self.assertEqual(b_context["environment"], "SANDBOX")

            # 2. Duplicate request with identical idempotencyKey: charged once, no re-decrement
            res_dup = self.client.post(
                "/api/v1/planning/prompt",
                json=payload,
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res_dup.status_code, 200)
            self.assertEqual(res_dup.json()["id"], job_id)

            prod_wallet_after = self.mock_db.collection("users").document(uid).collection("private").document("wallet").get().to_dict()
            self.assertEqual(prod_wallet_after["available"], 998)  # Still 998, NOT 996
            prod_entries_after = self.mock_db.collection("users").document(uid).collection("private").document("wallet").collection("entries").stream()
            self.assertEqual(len(prod_entries_after), 1)  # Still only 1 entry

    def test_empty_production_wallet_explains_sandbox_tokens_are_not_spendable(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user, \
             patch("server.firebase_planning.enqueue"), \
             patch.dict("os.environ", {"CRAFT_PLANNING_ENABLED": "1", "CRAFT_REVENUECAT_SANDBOX": "1"}):
            mock_req.return_value.get.return_value.exists = False
            mock_get_user.return_value = Mock(disabled=False)

            uid = "user_alice"
            private = self.mock_db.collection("users").document(uid).collection("private")
            private.document("billingContext").set({"environment": "SANDBOX"})
            private.document("sandboxWallet").set({"available": 500, "subscriptionAvailable": 0, "environment": "SANDBOX"})

            api_key = api_keys.create_api_key(self.mock_db, uid, "Pipeline Key", scopes=["prompt:write"])["key"]
            res = self.client.post(
                "/api/v1/planning/prompt",
                json={"idempotencyKey": "test-idem-key-402", "maxTokens": 10, "prompt": "A lighthouse"},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res.status_code, 402, res.text)
            self.assertIn("Not enough Tokens", res.json()["detail"])
            self.assertIn(api.V1_BILLING_NOTE, res.json()["detail"])
            self.assertEqual(private.document("sandboxWallet").get().to_dict()["available"], 500)

    def test_allowlisted_account_spends_sandbox_tokens_through_api(self):
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user, \
             patch("server.firebase_planning.enqueue"), \
             patch.dict("os.environ", {"CRAFT_PLANNING_ENABLED": "1", "CRAFT_REVENUECAT_SANDBOX": "1",
                                       "CRAFT_API_SANDBOX_UIDS": "someone_else, user_alice"}):
            mock_req.return_value.get.return_value.exists = False
            mock_get_user.return_value = Mock(disabled=False)

            uid = "user_alice"
            private = self.mock_db.collection("users").document(uid).collection("private")
            private.document("billingContext").set({"environment": "SANDBOX"})
            private.document("sandboxWallet").set({"available": 500, "subscriptionAvailable": 0, "environment": "SANDBOX"})
            private.document("wallet").set({"available": 1000, "subscriptionAvailable": 0, "environment": "PRODUCTION"})

            api_key = api_keys.create_api_key(self.mock_db, uid, "Pipeline Key", scopes=["prompt:write"])["key"]
            res = self.client.post(
                "/api/v1/planning/prompt",
                json={"idempotencyKey": "test-idem-key-allow", "maxTokens": 10, "prompt": "A lighthouse"},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res.status_code, 200, res.text)
            self.assertEqual(private.document("sandboxWallet").get().to_dict()["available"], 498)
            self.assertEqual(private.document("wallet").get().to_dict()["available"], 1000)

        # The same account without the allowlist bills production again.
        self.assertEqual(api.v1_environment("firebase:user_alice"), "PRODUCTION")

    def test_key_management_rejects_revoked_id_token_and_disabled_deleted_user(self):
        uid = "user_alice"
        claims_mock = {"uid": uid, "sub": uid, "firebase": {"sign_in_provider": "password"}}
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False

            # Create an existing key for revocation tests
            k = api_keys.create_api_key(self.mock_db, uid, "Existing Key")
            key_id = k["id"]

            # Scenario A: Revoked ID Token
            with patch("firebase_admin.auth.verify_id_token", side_effect=auth.RevokedIdTokenError("Token revoked")), \
                 patch("server.identity.verify_token", return_value=claims_mock):
                headers = {"Authorization": "Bearer fake_revoked_firebase_token"}

                res_list = self.client.get("/api/keys", headers=headers)
                self.assertEqual(res_list.status_code, 401)
                self.assertIn("revoked", res_list.json().get("detail", ""))

                res_create = self.client.post("/api/keys", json={"name": "New"}, headers=headers)
                self.assertEqual(res_create.status_code, 401)
                self.assertIn("revoked", res_create.json().get("detail", ""))

                res_revoke = self.client.post(f"/api/keys/{key_id}/revoke", headers=headers)
                self.assertEqual(res_revoke.status_code, 401)
                self.assertIn("revoked", res_revoke.json().get("detail", ""))

            # Scenario B: Disabled User in Firebase Auth
            disabled_user = Mock(disabled=True)
            with patch("firebase_admin.auth.verify_id_token", return_value=claims_mock), \
                 patch("server.identity.verify_token", return_value=claims_mock), \
                 patch("firebase_admin.auth.get_user", return_value=disabled_user):
                headers = {"Authorization": "Bearer valid_firebase_token"}

                res_list = self.client.get("/api/keys", headers=headers)
                self.assertEqual(res_list.status_code, 401)
                self.assertIn("disabled", res_list.json().get("detail", ""))

                res_create = self.client.post("/api/keys", json={"name": "New"}, headers=headers)
                self.assertEqual(res_create.status_code, 401)
                self.assertIn("disabled", res_create.json().get("detail", ""))

                res_revoke = self.client.post(f"/api/keys/{key_id}/revoke", headers=headers)
                self.assertEqual(res_revoke.status_code, 401)
                self.assertIn("disabled", res_revoke.json().get("detail", ""))

            # Scenario C: Deleted User in Firebase Auth (UserNotFoundError)
            with patch("firebase_admin.auth.verify_id_token", return_value=claims_mock), \
                 patch("server.identity.verify_token", return_value=claims_mock), \
                 patch("firebase_admin.auth.get_user", side_effect=auth.UserNotFoundError("User missing")):
                headers = {"Authorization": "Bearer valid_firebase_token"}

                res_list = self.client.get("/api/keys", headers=headers)
                self.assertEqual(res_list.status_code, 401)
                self.assertIn("no longer exists", res_list.json().get("detail", ""))

                res_create = self.client.post("/api/keys", json={"name": "New"}, headers=headers)
                self.assertEqual(res_create.status_code, 401)
                self.assertIn("no longer exists", res_create.json().get("detail", ""))

    def test_scoped_asset_download_with_api_key(self):
        uid = "user_alice"
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user:
            mock_req.return_value.get.return_value.exists = False
            mock_get_user.return_value = Mock(disabled=False)

            # Store asset in user's mobileCreations collection
            asset_data = {
                "ownerId": uid,
                "name": "SciFi Chair",
                "modelStoragePath": f"users/{uid}/models/chair.glb",
                "previewStoragePath": f"users/{uid}/previews/chair.png",
            }
            self.mock_db.collection("users").document(uid).collection("mobileCreations").document("model:chair_asset").set(asset_data)

            # Configure mock storage bucket
            def mock_blob(path):
                b = Mock()
                if path == f"users/{uid}/models/chair.glb":
                    b.download_as_bytes.return_value = b"GLTF_BINARY_PAYLOAD"
                elif path == f"users/{uid}/previews/chair.png":
                    b.download_as_bytes.return_value = b"PNG_IMAGE_PAYLOAD"
                else:
                    b.download_as_bytes.side_effect = Exception("Blob not found")
                return b
            self.mock_bucket.blob.side_effect = mock_blob

            # 1. Download model with valid asset key
            asset_key = api_keys.create_api_key(self.mock_db, uid, "Asset Key", scopes=["assets:read"])["key"]
            res = self.client.get(
                "/api/v1/assets/chair_asset/download",
                headers={"Authorization": f"Bearer {asset_key}"},
            )
            self.assertEqual(res.status_code, 200)
            self.assertEqual(res.content, b"GLTF_BINARY_PAYLOAD")
            self.assertEqual(res.headers.get("content-type"), "model/gltf-binary")
            self.assertIn("attachment", res.headers.get("content-disposition", ""))
            self.assertIn("chair_asset.glb", res.headers.get("content-disposition", ""))

            # 2. Download preview
            res_prev = self.client.get(
                "/api/v1/assets/chair_asset/download?kind=preview",
                headers={"Authorization": f"Bearer {asset_key}"},
            )
            self.assertEqual(res_prev.status_code, 200)
            self.assertEqual(res_prev.content, b"PNG_IMAGE_PAYLOAD")
            self.assertEqual(res_prev.headers.get("content-type"), "image/png")

            # 3. Reject download if key lacks assets:read scope
            no_asset_key = api_keys.create_api_key(self.mock_db, uid, "Wallet Only", scopes=["wallet:read"])["key"]
            res_forbidden = self.client.get(
                "/api/v1/assets/chair_asset/download",
                headers={"Authorization": f"Bearer {no_asset_key}"},
            )
            self.assertEqual(res_forbidden.status_code, 403)
            self.assertIn("assets:read", res_forbidden.json().get("detail", ""))

            # 4. Reject download of other user's asset (foreign user isolation)
            bob_uid = "user_bob"
            self.mock_db.collection("users").document(bob_uid).collection("mobileCreations").document("model:bob_asset").set({
                "ownerId": bob_uid,
                "name": "Bob's Asset",
                "modelStoragePath": f"users/{bob_uid}/models/bob.glb",
            })
            res_foreign = self.client.get(
                "/api/v1/assets/bob_asset/download",
                headers={"Authorization": f"Bearer {asset_key}"},  # Alice's key requesting Bob's asset
            )
            self.assertEqual(res_foreign.status_code, 404)

            # 5. Reject path traversal
            self.mock_db.collection("users").document(uid).collection("mobileCreations").document("model:traversal_asset").set({
                "ownerId": uid,
                "name": "Traversal Asset",
                "modelStoragePath": f"users/{uid}/../other/secret.glb",
            })
            res_traversal = self.client.get(
                "/api/v1/assets/traversal_asset/download",
                headers={"Authorization": f"Bearer {asset_key}"},
            )
            self.assertEqual(res_traversal.status_code, 404)

    def test_standalone_prompt_planning_endpoints(self):
        uid = "user_alice"
        with patch.object(api, "studio", return_value=self.mock_studio), \
             patch.object(api_keys, "request_ref") as mock_req, \
             patch("firebase_admin.auth.get_user") as mock_get_user, \
             patch("server.firebase_planning.enqueue") as mock_enqueue, \
             patch.dict("os.environ", {"CRAFT_PLANNING_ENABLED": "1"}):
            mock_req.return_value.get.return_value.exists = False
            mock_get_user.return_value = Mock(disabled=False)

            self.mock_db.collection("users").document(uid).collection("private").document("wallet").set({
                "available": 100,
                "subscriptionAvailable": 0,
                "purchasedAvailable": 100,
                "environment": "PRODUCTION",
            })

            api_key = api_keys.create_api_key(self.mock_db, uid, "Planning Key", scopes=["prompt:write"])["key"]

            # 1. POST /api/v1/planning/prompt succeeds with standalone text
            res = self.client.post(
                "/api/v1/planning/prompt",
                json={"idempotencyKey": "stand-001", "maxTokens": 10, "prompt": "A cyber dragon figurine"},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res.status_code, 200, res.text)
            self.assertTrue(res.json()["id"].startswith("pj-"))
            self.assertEqual(res.json()["status"], "queued")
            self.assertEqual(res.json()["maxTokens"], 2)

            # 2. Empty prompt rejected
            res_empty = self.client.post(
                "/api/v1/planning/prompt",
                json={"idempotencyKey": "stand-002", "maxTokens": 10, "prompt": "   "},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res_empty.status_code, 422)
            self.assertIn("standalone", res_empty.json().get("detail", ""))

            # 3. POST /api/v1/concepts/standalone/model-prompt also works
            res_concept_standalone = self.client.post(
                "/api/v1/concepts/standalone/model-prompt",
                json={"idempotencyKey": "stand-003", "maxTokens": 10, "prompt": "A crystal lamp"},
                headers={"Authorization": f"Bearer {api_key}"},
            )
            self.assertEqual(res_concept_standalone.status_code, 200, res_concept_standalone.text)
            self.assertTrue(res_concept_standalone.json()["id"].startswith("pj-"))
            self.assertEqual(res_concept_standalone.json()["status"], "queued")

    def test_transaction_ordering_verified_on_key_revocation(self):
        # 1. Verify that MockTransaction strictly prevents reads after writes
        tx = self.mock_db.transaction()
        dummy_ref = self.mock_db.collection("test").document("doc1")
        tx.set(dummy_ref, {"val": 1})
        with self.assertRaises(RuntimeError) as ctx:
            tx.get(dummy_ref)
        self.assertIn("reads after writes", str(ctx.exception))

        # 2. Verify that api_keys.revoke_api_key executes all reads before writes without raising RuntimeError
        with patch.object(api_keys, "request_ref") as mock_req:
            mock_req.return_value.get.return_value.exists = False
            created = api_keys.create_api_key(self.mock_db, "user_alice", "Order Test Key")
            key_id = created["id"]
            raw_key = created["key"]

            # Key starts active
            self.assertEqual(len(api_keys.list_api_keys(self.mock_db, "user_alice")), 1)

            # Revoke key - uses revoke_tx with strict MockTransaction
            revoked_res = api_keys.revoke_api_key(self.mock_db, "user_alice", key_id)
            self.assertEqual(revoked_res["status"], "revoked")

            # Verify key is marked revoked in Firestore and index is updated
            stored_doc = self.mock_db.collection("apiKeys").document(hashlib.sha256(raw_key.encode()).hexdigest()).get()
            self.assertTrue(stored_doc.to_dict()["revoked"])

            # Key appears in list with revoked=True
            keys = api_keys.list_api_keys(self.mock_db, "user_alice")
            self.assertEqual(len(keys), 1)
            self.assertTrue(keys[0]["revoked"])

            # Active keys index has 0 active keys
            index_doc = self.mock_db.collection("users").document("user_alice").collection("private").document("apiKeysIndex").get()
            self.assertEqual(len(index_doc.to_dict().get("activeKeys", {})), 0)


if __name__ == "__main__":
    unittest.main()
