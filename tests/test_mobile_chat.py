"""Conversation persistence, isolation, retries and provider dispatch; no paid calls."""
import unittest
from unittest.mock import patch
from tests.test_mobile import MobileTests, Queue
from server import mobile, mobile_chat

class ConversationTests(unittest.TestCase):
    setUp = MobileTests.setUp
    release_lease = MobileTests.release_lease
    login = MobileTests.login
    balance = MobileTests.balance
    image = MobileTests.image
    def send(self, **fields):
        return self.client.post(f"/api/mobile/projects/{self.project['id']}/chat", headers=self.auth,
            json={"clientId": "message-0001", "text": "A cat riding a bicycle", **fields})
    def test_turn_saved_once_and_brief_persists_without_charge(self):
        queue = Queue(); before = self.balance()
        answer = {"reply": "What kind of game?", "brief": "A full-body cat on a bicycle", "ready": False, "suggestions": ["Cozy adventure", "Racing"]}
        with patch.object(mobile_chat, "_pool", queue), patch.object(mobile_chat, "plan_turn", return_value=answer) as planner:
            first = self.send(); self.assertEqual(first.status_code, 200)
            self.assertEqual(self.send().json()["id"], first.json()["id"])
            self.assertEqual(len(queue.calls), 1)
            self.assertEqual(self.send(clientId="message-0002", text="Racing").status_code, 409)
            self.assertEqual(self.send(text="different request").status_code, 409)
            queue.flush()
            self.assertEqual(planner.call_count, 1)
            rows = self.client.get("/api/mobile/projects", headers=self.auth).json()[0]["conversation"]
            self.assertEqual(rows[0]["brief"], answer["brief"])
            self.assertEqual(rows[0]["status"], "done")
            self.assertEqual(self.send().json()["status"], "done")
            self.send(clientId="message-0002", text="Cozy adventure"); queue.flush()
            history = planner.call_args.args[3]
            self.assertEqual([x["role"] for x in history], ["user", "assistant", "user"])
        self.assertEqual(self.balance(), before)
        self.assertEqual(self.q.calls, [])
    def test_owner_and_reference_isolation(self):
        stranger = self.login()
        url = f"/api/mobile/projects/{self.project['id']}/chat"
        self.assertEqual(self.client.post(url, headers=stranger, json={"clientId":"message-0001", "text":"hi"}).status_code, 404)
        self.assertEqual(self.client.post(url, json={"clientId":"message-0001", "text":"hi"}).status_code, 401)
        photo = self.client.post("/api/mobile/projects", headers=self.auth, data={"prompt":"another"}, files={"image":("ref.png", self.image(64)["bytes"], "image/png")}).json()
        self.assertEqual(self.send(conceptId=photo["concepts"][0]["id"]).status_code, 422)
        r = self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts", headers=self.auth, json={"idempotencyKey":"reference-test-001", "count":1, "referenceId":photo["concepts"][0]["id"]})
        self.assertEqual(r.status_code, 422)
        self.assertEqual(self.q.calls, [])
    def test_failure_saved_and_does_not_leak_provider_error(self):
        queue = Queue()
        with patch.object(mobile_chat, "_pool", queue), patch.object(mobile_chat, "plan_turn", side_effect=RuntimeError("secret key in provider URL")):
            self.send(); queue.flush()
        row = self.client.get("/api/mobile/projects", headers=self.auth).json()[0]["conversation"][0]
        self.assertEqual(row["status"], "failed")
        self.assertNotIn("secret key", str(row))
        self.assertEqual(row["text"], "A cat riding a bicycle")
    def test_reference_upload_stays_in_conversation(self):
        url = f"/api/mobile/projects/{self.project['id']}/references"
        r = self.client.post(url, headers=self.auth, files={"image":("ref.png", self.image(64)["bytes"], "image/png")})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["projectId"], self.project["id"])
        self.assertTrue(r.json()["isOriginal"])
        rows = self.client.get("/api/mobile/projects", headers=self.auth).json()
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["concepts"][0]["id"], r.json()["id"])
    def test_selected_chat_planner_receives_reference_and_schema(self):
        answer = {"reply":"Ready!", "brief":"A blue toy racing cat", "ready":True, "suggestions":[]}
        with patch("server.codex_bridge.plan", return_value=answer) as plan:
            result = mobile_chat.plan_turn("owner", "account-model", "low", [{"role":"user", "text":"cat"}], None, "Toy")
            self.assertEqual(result, answer)
            self.assertEqual(plan.call_args.args[1], "account-model")
            self.assertIn("ONE useful question", plan.call_args.args[2])
            self.assertEqual(plan.call_args.args[4], mobile_chat.SCHEMA)

    def test_current_brief_and_reference_reach_image_workflow(self):
        reference = self.client.post(f"/api/mobile/projects/{self.project['id']}/references", headers=self.auth,
            files={"image":("ref.png", self.image(64)["bytes"], "image/png")}).json()
        body = {"idempotencyKey":"chat-generate-001", "count":1, "prompt":"Updated brief: blue racing cat", "referenceId":reference["id"], "style":"Toy"}
        response = self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts", headers=self.auth, json=body)
        self.assertEqual(response.status_code, 200)
        with patch.object(mobile.gemini, "make_concept_set", return_value={}) as render:
            self.q.flush()
        self.assertEqual(render.call_args.args[0], "Updated brief: blue racing cat\nStyle: Toy")
        self.assertEqual(render.call_args.args[1], mobile.image_path(reference["imageUrl"]))
    def test_gemini_receives_compatible_structured_schema(self):
        import json
        answer = {"reply":"What game?", "brief":"A racing cat", "ready":False, "suggestions":["Racing", "Adventure"]}
        response = {"candidates":[{"content":{"parts":[{"text":json.dumps(answer)}]}}]}
        with patch.object(mobile_chat.gemini, "_call", return_value=response) as api:
            self.assertEqual(mobile_chat.plan_turn("owner", mobile.planning.DEFAULT_MODEL, "low", [], None, "Toy"), answer)
        schema = api.call_args.args[1]["generationConfig"]["responseSchema"]
        self.assertNotIn("additionalProperties", schema)
        self.assertEqual(schema["required"], ["reply", "brief", "ready", "suggestions"])

    def test_image_input_bypasses_planner_preserves_reference_and_count(self):
        reference = self.client.post(f"/api/mobile/projects/{self.project['id']}/references", headers=self.auth,
            files={"image":("ref.png", self.image(64)["bytes"], "image/png")}).json()
        url = f"/api/mobile/projects/{self.project['id']}/concepts"
        body = {"idempotencyKey":"direct-photo-001", "count":3, "prompt":"Give the rider a blue jacket", "referenceId":reference["id"], "preserveReference":True, "style":"Toy"}
        with patch.object(mobile.planning, "require_available", side_effect=AssertionError("No planner required")), \
             patch.object(mobile.gemini, "write_prompt", side_effect=AssertionError("Do not rewrite image instructions")), \
             patch.object(mobile.gemini, "make_image", return_value=self.image()) as render, \
             patch.object(mobile.gemini, "assess_turnaround", side_effect=AssertionError("Not a turnaround")):
            r = self.client.post(url, headers=self.auth, json=body)
            self.assertEqual(r.status_code, 200, r.text)
            self.assertEqual(self.client.post(url, headers=self.auth, json=body).json()["id"], r.json()["id"])
            self.q.flush()
        self.assertEqual(render.call_count, 3)
        for call in render.call_args_list:
            self.assertEqual(call.kwargs["refs"], [mobile.image_path(reference["imageUrl"])])
            self.assertIn("Give the rider a blue jacket", call.args[0])
            self.assertNotIn("Style: Toy", call.args[0])
        job = self.client.get("/api/mobile/jobs", headers=self.auth).json()[0]
        self.assertEqual(job["status"], "done")
        self.assertEqual(job["charged"], 45)
        self.assertEqual(len(job["concepts"]), 3)
        self.assertEqual(job["sourcePrompt"], body["prompt"])
        project = self.client.get("/api/mobile/projects", headers=self.auth).json()[0]
        self.assertEqual(project["conversation"], [])
        self.assertEqual(self.client.post(url, headers=self.auth, json={**body, "preserveReference":False}).status_code, 409)

    def test_reference_mode_requires_image_and_does_not_reuse_old_brief(self):
        url = f"/api/mobile/projects/{self.project['id']}/concepts"
        self.assertEqual(self.client.post(url, headers=self.auth, json={"idempotencyKey":"missing-photo-001", "preserveReference":True}).status_code, 422)
        reference = self.client.post(f"/api/mobile/projects/{self.project['id']}/references", headers=self.auth,
            files={"image":("ref.png", self.image(64)["bytes"], "image/png")}).json()
        with patch.object(mobile.gemini, "make_concept_set", return_value={}) as render:
            self.client.post(url, headers=self.auth, json={"idempotencyKey":"image-only-001", "count":1, "referenceId":reference["id"], "preserveReference":True})
            self.q.flush()
        self.assertEqual(render.call_args.args[0], "")
        self.assertEqual(render.call_args.kwargs["mode"], "reference")
