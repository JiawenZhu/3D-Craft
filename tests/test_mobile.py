"""Real SQLite/API tests; every image and 3D provider is mocked."""
import io
import os
import tempfile
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from server import mobile, codex_bridge


class Queue:
    def __init__(self): self.calls = []
    def submit(self, fn, *args): self.calls.append((fn, args))
    def flush(self):
        while self.calls:
            fn, args = self.calls.pop(0); fn(*args)


class MobileTests(unittest.TestCase):
    def test_model_prompt_improvement_is_owned_and_does_not_generate_or_charge(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("swing.png",self.image(128)["bytes"],"image/png")}).json()
        concept=photo["concepts"][0];before=self.balance()
        url=f"/api/mobile/concepts/{concept['id']}/model-prompt"
        with patch.object(mobile.planning,"improve_model_prompt",return_value={"prompt":"Preserve the swing frame.","model":"selected-model"}) as planner:
            result=self.client.post(url,headers=self.auth,json={"prompt":"swing","plannerModel":"selected-model","plannerEffort":"medium"})
            self.assertEqual(result.status_code,200,result.text)
            self.assertEqual(planner.call_args.args[1:3],("selected-model","swing"))
            self.assertEqual(planner.call_args.args[3],mobile.image_path(concept["imageUrl"]))
            other=self.login()
            self.assertEqual(self.client.post(url,headers=other,json={"prompt":"swing"}).status_code,404)
            self.assertEqual(planner.call_count,1)
        self.assertEqual(self.balance(),before);self.assertEqual(self.q.calls,[])

    def test_explicit_model_prompt_reaches_provider_with_exact_selected_image(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("swing.png",self.image(128)["bytes"],"image/png")}).json()
        concept=photo["concepts"][0]
        url=f"/api/mobile/concepts/{concept['id']}/model"
        self.purchase()
        body={"idempotencyKey":"image-plus-prompt","engine":"rodin","modelPrompt":"保留秋千支架和顶棚。Size the seat for a game character."}
        response=self.client.post(url,headers=self.auth,json=body)
        self.assertEqual(response.status_code,200,response.text)
        self.assertEqual(self.client.post(url,headers=self.auth,json={**body,"modelPrompt":"Different shape"}).status_code,409)
        def submit(engine,request,name):
            self.assertEqual(engine,"rodin")
            self.assertIn(body["modelPrompt"],request.prompt)
            self.assertEqual(request.images,[mobile.image_path(concept["imageUrl"])])
            return "prompt-model"
        with patch.object(mobile.jobs,"submit",side_effect=submit),patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"prompt-asset"}]}):
            self.q.flush()
        done=self.client.get("/api/mobile/jobs/"+response.json()["id"],headers=self.auth).json()
        self.assertTrue(done["modelSettings"]["promptApplied"])
        self.assertIn(body["modelPrompt"],done["modelSettings"]["prompt"])
        self.assertEqual(done["charged"],46)

    def test_unsupported_or_oversized_model_prompt_never_reserves_tokens(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("swing.png",self.image(128)["bytes"],"image/png")}).json()
        url=f"/api/mobile/concepts/{photo['concepts'][0]['id']}/model"
        self.purchase();before=self.balance()
        for engine in ["trellis-2","hunyuan3d-2.1","hunyuan3d-2-white","hybrid"]:
            result=self.client.post(url,headers=self.auth,json={"idempotencyKey":"unsupported-"+engine,"engine":engine,"modelPrompt":"Add a swing"})
            self.assertEqual(result.status_code,422,result.text)
        result=self.client.post(url,headers=self.auth,json={"idempotencyKey":"prompt-too-long","engine":"rodin","modelPrompt":"字"*801})
        self.assertEqual(result.status_code,422)
        self.assertEqual(self.balance(),before);self.assertEqual(self.q.calls,[])

    def test_explicit_blank_model_prompt_does_not_restore_project_instructions(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,data={"prompt":"Add a dragon"},files={"image":("swing.png",self.image(128)["bytes"],"image/png")}).json()
        self.purchase()
        response=self.client.post(f"/api/mobile/concepts/{photo['concepts'][0]['id']}/model",headers=self.auth,json={"idempotencyKey":"blank-model-prompt","modelPrompt":""})
        self.assertEqual(response.status_code,200,response.text)
        def submit(engine,request,name):
            self.assertNotIn("dragon",request.prompt)
            return "blank-model"
        with patch.object(mobile.jobs,"submit",side_effect=submit),patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"blank-asset"}]}):self.q.flush()

    def test_model_price_snapshot_reservation_settlement_and_replay(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("cat.png",self.image(128)["bytes"],"image/png")}).json()
        url=f"/api/mobile/concepts/{photo['concepts'][0]['id']}/model"
        for engine, expected in [("rodin",46),("trellis-2",35),("hunyuan3d-2.1",56),("hybrid",90)]:
            with self.subTest(engine=engine):
                self.purchase("price-"+engine)
                before=self.balance()["available"]
                body={"engine":engine,"idempotencyKey":"cost-"+engine}
                response=self.client.post(url,headers=self.auth,json=body)
                self.assertEqual(response.status_code,200,response.text)
                job=response.json()
                self.assertEqual((job["cost"],job["reserved"]),(expected,expected))
                self.assertEqual(self.balance()["available"],before-expected)
                # Replays and completion keep the accepted price even if the catalog changes.
                with patch.object(mobile.pricing,"model_quote",side_effect=AssertionError("must use snapshot")):
                    self.assertEqual(self.client.post(url,headers=self.auth,json=body).json()["id"],job["id"])
                    with patch.object(mobile.jobs,"submit",return_value="model-price"),patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"asset-"+engine}]}):
                        self.q.flush()
                done=self.client.get("/api/mobile/jobs/"+job["id"],headers=self.auth).json()
                self.assertEqual(done["charged"],expected)
                self.assertEqual(self.balance()["available"],before-expected)

    def test_unverified_model_quote_does_not_reserve_or_run(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("cat.png",self.image(128)["bytes"],"image/png")}).json()
        self.purchase()
        before=self.balance()
        with patch.dict(mobile.pricing.FAL_ENDPOINTS,{"trellis-2":"fal-ai/unknown"}):
            result=self.client.post(f"/api/mobile/concepts/{photo['concepts'][0]['id']}/model",headers=self.auth,json={"engine":"trellis-2","idempotencyKey":"unknown-model-cost"})
        self.assertEqual(result.status_code,422)
        self.assertEqual(self.balance(),before)
        self.assertEqual(self.q.calls,[])

    def test_account_images_allow_zero_balance_and_partial_results_cost_zero(self):
        with mobile.connect() as c:
            c.execute('UPDATE users SET paid=0,trial=0')
        body = {"idempotencyKey":"account-zero-001", "count":2,
                "imageModel":"codex-gpt-image-2", "plannerModel":"gpt-5.6-sol"}
        with patch.object(mobile.planning, 'require_available'), patch.object(codex_bridge, 'account_status', return_value={"connected":True,"imageGenerationSupported":True}):
            response = self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts", headers=self.auth, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()['reserved'], 0)
        def partial(*args, **kwargs):
            kwargs['on_image']({**self.image(1024), 'label':'Front'}, {'prompt':'a cat'})
            return {'warnings':[]}
        with patch.object(mobile.gemini, 'make_concept_set', side_effect=partial): self.q.flush()
        done = self.client.get('/api/mobile/jobs/'+response.json()['id'], headers=self.auth).json()
        self.assertEqual((done['status'],done['charged']), ('partial',0))
        self.assertEqual((self.balance()['available'],self.balance()['freeConceptTokens']), (0,0))
        # Recovery uses the persisted per-image tariff, not the former flat 15.
        import json
        with mobile.connect() as c:
            pending={**response.json(), 'status':'running','concepts':[{'id':'saved'}]}
            c.execute('DELETE FROM settlements WHERE job_id=?',(pending['id'],))
            c.execute("DELETE FROM ledger WHERE kind='settle'")
            c.execute('UPDATE work SET data=? WHERE id=?',(json.dumps(pending),pending['id']))
        with patch.object(mobile, 'worker_alive', return_value=False): mobile.recover_abandoned()
        recovered=self.client.get('/api/mobile/jobs/'+pending['id'],headers=self.auth).json()
        self.assertEqual(recovered['charged'],0)
        self.assertEqual(self.balance()['available'],0)

    def test_unselected_model_defaults_to_rodin_and_keeps_explicit_choice(self):
        default = mobile.Generate(idempotencyKey="default-model-001")
        self.assertEqual((default.engine, default.effort, default.quality), ("rodin", "high", "default"))
        selected = mobile.Generate(idempotencyKey="selected-model-001", engine="trellis-2", effort="low")
        self.assertEqual((selected.engine, selected.effort), ("trellis-2", "low"))

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.q = Queue()
        for p in [patch.object(codex_bridge, "account_status", return_value={"available":True,"connected":False,"models":[],"imageGenerationSupported":False}), patch.object(mobile, "DB_PATH", Path(self.tmp.name)/"mobile.sqlite3"), patch.object(mobile, "STORAGE", Path(self.tmp.name)/"files"), patch.object(mobile, "_pool", self.q), patch.object(mobile.gemini,"assess_turnaround",return_value={"usable":True,"issues":[]}), patch.object(mobile.gemini, "GEMINI_API_KEY", "test-gemini-key"), patch.dict(os.environ, {"RODIN_MOBILE_DEVELOPMENT": "1"})]:
            p.start(); self.addCleanup(p.stop)
        app = FastAPI(); app.include_router(mobile.router)
        self.client = TestClient(app)
        self.addCleanup(self.release_lease)
        self.auth = self.login()
        self.project = self.client.post("/api/mobile/projects", data={"prompt": "little cat", "name": "My cat"}, headers=self.auth).json()

    def release_lease(self):
        lease=mobile._process_leases.pop(str(mobile.DB_PATH.resolve()),None)
        if lease: lease.close()

    def login(self):
        r = self.client.post("/api/mobile/session", json={"deviceId": "test-device-1"})
        self.assertEqual(r.status_code, 200)
        return {"Authorization": "Bearer " + r.json()["token"]}

    def balance(self): return self.client.get("/api/mobile/wallet", headers=self.auth).json()
    def image(self, size=2048):
        b=io.BytesIO(); Image.new("RGB", (size,size), "orange").save(b,format="PNG"); return {"bytes": b.getvalue(), "mime":"image/png"}
    def start(self, key="request-0001", count=3):
        return self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts", headers=self.auth, json={"idempotencyKey":key,"count":count})
    def purchase(self, transaction="purchase-0001"):
        return self.client.post("/api/mobile/development/purchase", headers=self.auth, json={"productId":"craft.starter100","transactionId":transaction})

    def test_selected_planner_routes_prompt_and_audit_and_binds_retry(self):
        route = f"/api/mobile/projects/{self.project['id']}/concepts"
        body = {"idempotencyKey": "planner-request-001", "count": 2, "plannerModel": "gpt-5.6-sol"}
        with patch.object(mobile.planning, "require_available") as available:
            response = self.client.post(route, headers=self.auth, json=body)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(available.call_args.args[1], "gpt-5.6-sol")
        with patch.object(mobile.planning, "write_prompt", return_value={"prompt": "One cat, clear details", "title": "Cat"}) as writer, patch.object(mobile.planning, "assess_turnaround", return_value={"usable": True, "issues": []}) as auditor, patch.object(mobile.gemini, "make_image", return_value=self.image()):
            self.q.flush()
        self.assertEqual(writer.call_args.args[1], "gpt-5.6-sol")
        self.assertEqual(auditor.call_args.args[1], "gpt-5.6-sol")
        result = self.client.get("/api/mobile/jobs/" + response.json()["id"], headers=self.auth).json()
        self.assertEqual(result["status"], "done")
        self.assertEqual(result["concepts"][0]["plannerModel"], "gpt-5.6-sol")
        with patch.object(mobile.planning, "require_available", side_effect=RuntimeError("signed out")) as offline:
            retry = self.client.post(route, headers=self.auth, json=body)
        self.assertEqual(retry.json()["id"], result["id"])
        offline.assert_not_called()
        changed = self.client.post(route, headers=self.auth, json={**body, "plannerModel": "gpt-6-astra"})
        self.assertEqual(changed.status_code, 409)

    def test_unavailable_planner_rejects_before_credit_reservation(self):
        before = self.balance()
        with patch.object(mobile.planning, "require_available", side_effect=RuntimeError("Connect ChatGPT")):
            response = self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts", headers=self.auth,
                json={"idempotencyKey": "planner-unavailable-001", "plannerModel": "gpt-6-astra"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.balance(), before)
        self.assertEqual(self.q.calls, [])

    def test_image_model_catalog_and_precharge_validation(self):
        self.assertEqual(self.client.get("/api/mobile/image-models").status_code, 401)
        catalog = self.client.get("/api/mobile/image-models", headers=self.auth).json()
        self.assertEqual(catalog["defaultModel"], "gemini-3-pro-image")
        self.assertEqual([m["available"] for m in catalog["models"]], [True, False])
        self.assertNotIn("test-gemini-key", str(catalog))
        before = self.balance()
        url = f"/api/mobile/projects/{self.project['id']}/concepts"
        for model, status in [("unknown-image-model", 422), ("gpt-image-2.5-sunburst", 422), ("codex-gpt-image-2", 503)]:
            response = self.client.post(url, headers=self.auth, json={"idempotencyKey":"model-unavailable", "imageModel":model})
            self.assertEqual(response.status_code, status)
        self.assertEqual(self.balance(), before)
        self.assertEqual(len(self.q.calls), 0)

    def test_image_selection_is_idempotent_and_saved_with_each_concept(self):
        before = self.balance()
        url = f"/api/mobile/projects/{self.project['id']}/concepts"
        body = {"idempotencyKey":"openai-image-choice", "count":2, "imageModel":"codex-gpt-image-2"}
        rendered = self.image(1024)
        rendered.update(model="gpt-image-2", provider="chatgpt")
        def render(owner, prompt, refs=None, **kwargs):
            references.append([p.read_bytes() for p in (refs or [])])
            return rendered
        references = []
        with patch.object(codex_bridge, "account_status", return_value={"connected":True,"imageGenerationSupported":True}):
            initial = self.client.post(url, headers=self.auth, json=body)
            self.assertEqual(initial.status_code, 200)
            job = initial.json()
            self.assertEqual(job["imageModel"], body["imageModel"])
            self.assertEqual(self.client.post(url, headers=self.auth, json=body).json()["id"], job["id"])
            conflict = self.client.post(url, headers=self.auth, json={**body,"imageModel":"gemini-3-pro-image"})
            self.assertEqual(conflict.status_code, 409)
            with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"same little cat"}), patch.object(codex_bridge,"generate_image",side_effect=render), patch.object(mobile.gemini,"make_image") as wrong_provider:
                self.q.flush()
            wrong_provider.assert_not_called()
        done = self.client.get("/api/mobile/jobs/"+job["id"],headers=self.auth).json()
        self.assertEqual(done["status"], "done")
        self.assertEqual(done["charged"], 0)
        self.assertEqual(job["cost"], 0)
        self.assertEqual(job["reserved"], 0)
        self.assertEqual(self.balance()["available"], before["available"])
        self.assertEqual(self.balance()["freeConceptTokens"], before["freeConceptTokens"])
        self.assertEqual(references, [[], [rendered["bytes"]]])
        for concept in done["concepts"]:
            self.assertEqual(concept["imageModel"], "gpt-image-2")
            self.assertEqual(concept["imageProvider"], "chatgpt")
        # Availability changes must not cause an already reserved request to be
        # charged or enqueued again on retry.
        with patch.object(codex_bridge,"account_status",return_value={"connected":False}):
            self.assertEqual(self.client.post(url,headers=self.auth,json=body).json()["id"],job["id"])

    def test_review_credit_needs_no_purchase_and_is_capped(self):
        self.client.get("/api/mobile/bootstrap",headers=self.auth)
        self.assertEqual(self.balance()["available"],1000)
        self.client.get("/api/mobile/bootstrap",headers=self.auth)
        self.assertEqual(self.balance()["available"],1000)
        for _ in range(2):
            response=self.client.post("/api/mobile/development/credits",headers=self.auth)
            self.assertEqual(response.status_code,200)
            self.assertEqual(response.json()["available"],1000)
        with mobile.connect() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM purchases").fetchone()[0],0)
        self.assertEqual(self.client.post("/api/mobile/development/credits").status_code,401)
        with patch.dict(os.environ,{"RODIN_MOBILE_DEVELOPMENT":"0"}):
            self.assertEqual(self.client.post("/api/mobile/development/credits",headers=self.auth).status_code,503)

    def test_auth_mode_and_account_isolation(self):
        self.assertEqual(self.client.get("/api/mobile/projects").status_code,401)
        other=self.login()
        self.assertEqual(self.client.get("/api/mobile/projects",headers=other).json(),[])
        r=self.client.post(f"/api/mobile/projects/{self.project['id']}/concepts",headers=other,json={"idempotencyKey":"other-request"})
        self.assertEqual(r.status_code,404)
        with patch.dict(os.environ,{"RODIN_MOBILE_DEVELOPMENT":"0"}):
            self.assertEqual(self.client.get("/api/mobile/wallet",headers=self.auth).status_code,503)

    def test_idempotent_reservation_and_conflict(self):
        a=self.start(); b=self.start()
        self.assertEqual(a.json()["id"],b.json()["id"])
        self.assertEqual(len(self.q.calls),1)
        self.assertEqual(self.balance()["reserved"],45)
        self.assertEqual(self.start(count=1).status_code,409)
        self.assertEqual(self.start(key="new-request-2").status_code,402)

    def test_partial_result_charges_only_saved_native_2k(self):
        j=self.start().json()
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"cat"}), patch.object(mobile.gemini,"make_image",side_effect=[self.image(),self.image(512),RuntimeError("provider down")]) as make:
            self.q.flush()
        done=self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()
        self.assertEqual(done["status"],"partial")
        self.assertEqual(done["charged"],15)
        self.assertEqual(done["concepts"][0]["width"],2048)
        self.assertEqual(self.balance()["freeConceptTokens"],30)
        self.assertEqual(make.call_args.kwargs["image_size"],"2K")
        self.assertEqual(len(self.client.get("/api/mobile/projects",headers=self.auth).json()[0]["concepts"]),1)

    def test_photo_four_views_share_website_pipeline_and_original_is_free(self):
        source=self.image(128)["bytes"]
        photo=self.client.post("/api/mobile/projects",headers=self.auth,data={"prompt":"A mossy waterfall cliff","name":"Waterfall","style":"Realistic"},files={"image":("waterfall.png",source,"image/png")}).json()
        original=photo["concepts"][0]
        self.assertTrue(original["isOriginal"])
        self.assertEqual(self.balance()["freeConceptTokens"],45)
        self.assertEqual(self.balance()["reserved"],0)
        self.purchase()
        request=self.client.post(f"/api/mobile/projects/{photo['id']}/concepts",headers=self.auth,json={"count":4,"idempotencyKey":"four-view-photo"})
        self.assertEqual(request.status_code,200)
        calls=[];stages=[];made=self.image()
        def render(prompt,refs,**kwargs):
            calls.append((prompt,[(str(p),p.read_bytes()) for p in refs],kwargs))
            return made
        save=mobile.save_job
        def record_stage(owner,data):
            stages.append(data.get("stage"));save(owner,data)
        written={"prompt":"A mossy waterfall cliff diorama","title":"Waterfall cliff","core_concept":"Waterfall environment","image_assessment":"One waterfall and cliffs","subject":"environment"}
        shared=mobile.gemini.make_concept_set
        with patch.object(mobile.gemini,"write_prompt",return_value=written) as planner,patch.object(mobile.gemini,"make_image",side_effect=render),patch.object(mobile.gemini,"make_concept_set",wraps=shared) as pipeline,patch.object(mobile,"save_job",side_effect=record_stage),patch.object(mobile.jobs,"submit") as model:
            self.q.flush()
        pipeline.assert_called_once()
        model.assert_not_called()  # creating/selecting candidates never makes 3D
        self.assertIn("A mossy waterfall cliff",planner.call_args.args[0])
        self.assertEqual(planner.call_args.args[1],mobile.image_path(original["imageUrl"]))
        self.assertEqual(calls[0][1][0][0],str(mobile.image_path(original["imageUrl"])))
        self.assertTrue(all(refs[0][1]==made["bytes"] for _,refs,_ in calls[1:]))
        self.assertTrue(all(options["image_size"]=="2K" for _,_,options in calls))
        self.assertTrue(all("TURNAROUND CAMERA CONTRACT" in prompt for prompt,_,_ in calls))
        done=self.client.get("/api/mobile/jobs/"+request.json()["id"],headers=self.auth).json()
        self.assertEqual(done["status"],"done");self.assertEqual(done["charged"],60)
        self.assertEqual([c["direction"] for c in done["concepts"]],["front","back","left","right"])
        self.assertEqual(done["coreConcept"],"Waterfall environment")
        self.assertEqual(done["validation"],{"usable":True,"issues":[]})
        for stage in ["analyzing_reference","rendering_canonical","rendering_views","validating_views"]:self.assertIn(stage,stages)
        project=next(p for p in self.client.get("/api/mobile/projects",headers=self.auth).json() if p["id"]==photo["id"])
        self.assertEqual(len(project["concepts"]),5)
        self.assertEqual(sum(c["isOriginal"] for c in project["concepts"]),1)
        # A non-first selected candidate, not the canonical or demo cat, is used.
        chosen=done["concepts"][2]
        job=self.client.post(f"/api/mobile/concepts/{chosen['id']}/model",headers=self.auth,json={"idempotencyKey":"selected-left"}).json()
        with patch.object(mobile.jobs,"submit",return_value="chosen-model") as submit,patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"waterfall-3d"}]}):self.q.flush()
        self.assertEqual(submit.call_args.args[1].images,[mobile.image_path(chosen["imageUrl"])])
        self.assertEqual(self.client.get("/api/mobile/jobs/"+job["id"],headers=self.auth).json()["selectedConceptId"],chosen["id"])

    def test_text_only_uses_user_intent_without_a_demo_reference(self):
        project=self.client.post("/api/mobile/projects",headers=self.auth,data={"prompt":"A red sailing ship with three sails","style":"Toy"}).json()
        self.assertEqual(project["concepts"],[])
        job=self.client.post(f"/api/mobile/projects/{project['id']}/concepts",headers=self.auth,json={"count":1,"idempotencyKey":"text-sailing-ship"}).json()
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"A toy red sailing ship","core_concept":"Sailing ship"}) as planner,patch.object(mobile.gemini,"make_image",return_value=self.image()) as renderer,patch.object(mobile.jobs,"submit") as models:self.q.flush()
        self.assertIn("A red sailing ship with three sails",planner.call_args.args[0])
        self.assertIsNone(planner.call_args.args[1])
        self.assertEqual(renderer.call_args.kwargs["refs"],[])
        models.assert_not_called()
        done=self.client.get("/api/mobile/jobs/"+job["id"],headers=self.auth).json()
        self.assertEqual(done["concepts"][0]["coreConcept"],"Sailing ship")
        self.assertFalse(done["concepts"][0]["isOriginal"])

    def four_views(self):
        self.purchase()
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"A little robot"}),patch.object(mobile.gemini,"make_image",return_value=self.image()):
            j=self.start(count=4).json();self.q.flush()
        return self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()

    def test_multiview_settings_and_replay_survive_provider_change(self):
        source=self.four_views();views=source["concepts"]
        primary=views[2]
        body={"idempotencyKey":"multiview-model","engine":"hunyuan3d-2.1","conceptIds":[v["id"] for v in views[:3]],"quality":"speedy","effort":"low"}
        url=f"/api/mobile/concepts/{primary['id']}/model"
        engine=mobile.engines.ENGINES["hunyuan3d-2.1"]
        with patch.object(engine,"status",return_value={"provider":"api"}), patch.object(mobile.pricing,"model_quote",return_value=mobile.pricing.model_quote("rodin")):
            accepted=self.client.post(url,headers=self.auth,json=body)
        self.assertEqual(accepted.status_code,200)
        with patch.object(engine,"status",return_value={"provider":"local"}):
            replay=self.client.post(url,headers=self.auth,json=body)
        self.assertEqual(replay.json()["id"],accepted.json()["id"])
        self.assertEqual(len(self.q.calls),1)
        changed=dict(body,effort="high")
        self.assertEqual(self.client.post(url,headers=self.auth,json=changed).status_code,409)
        with patch.object(mobile.jobs,"submit",return_value="multi-provider") as submit,patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"multi-robot"}]}):self.q.flush()
        req=submit.call_args.args[1]
        self.assertEqual(req.images,[mobile.image_path(v["imageUrl"]) for v in [views[2],views[0],views[1]]])
        self.assertEqual(req.directions,["left","front","back"])
        self.assertEqual((req.quality,req.effort,req.steps),("speedy","low",25))
        done=self.client.get("/api/mobile/jobs/"+accepted.json()["id"],headers=self.auth).json()
        self.assertEqual(done["charged"],46)
        self.assertEqual(done["modelSettings"],{"engine":"hunyuan3d-2.1","quality":"speedy","effort":"low","prompt":"","promptApplied":False})

    def test_multiview_prices_and_white_input_reach_worker(self):
        source=self.four_views(); views=source["concepts"]
        for engine_id, tokens in [("hunyuan3d-2-white",2),("hunyuan3d-2.1",6),("trellis-2",35),("hybrid",41)]:
            engine=mobile.engines.ENGINES[engine_id]
            body={"idempotencyKey":"priced-"+engine_id,"engine":engine_id,"conceptIds":[v["id"] for v in views[:3]]}
            with patch.object(engine,"status",return_value={"provider":"api+api" if engine_id=="hybrid" else "api"}):
                accepted=self.client.post(f"/api/mobile/concepts/{views[0]['id']}/model",headers=self.auth,json=body)
            self.assertEqual(accepted.status_code,200,accepted.text)
            with patch.object(mobile.jobs,"submit",return_value="priced-provider") as submit, patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"priced-model"}]}):
                self.q.flush()
            req=submit.call_args.args[1]
            self.assertEqual(len(req.images),3)
            self.assertEqual(req.directions,["front","back","left"])
            self.assertEqual(req.texture,engine_id!="hunyuan3d-2-white")
            done=self.client.get("/api/mobile/jobs/"+accepted.json()["id"],headers=self.auth).json()
            self.assertEqual(done["charged"],tokens)

    def test_multiview_rejects_invalid_sets_before_reserving(self):
        import json
        source=self.four_views();views=source["concepts"];primary=views[0]
        url=f"/api/mobile/concepts/{primary['id']}/model"
        base={"engine":"hunyuan3d-2.1","conceptIds":[v["id"] for v in views[:3]]}
        before=self.balance()["available"]
        invalid=[dict(base,conceptIds=[views[1]["id"],views[2]["id"]]),dict(base,conceptIds=[primary["id"],primary["id"]]),dict(base,conceptIds=[v["id"] for v in views]),dict(base,quality="ultra"),dict(base,effort="fastest")]
        for i,body in enumerate(invalid):
            self.assertEqual(self.client.post(url,headers=self.auth,json=dict(body,idempotencyKey=f"invalid-view-{i}")).status_code,422)
        with patch.object(mobile.engines.ENGINES["hunyuan3d-2.1"],"status",return_value={"provider":"local"}):
            self.assertEqual(self.client.post(url,headers=self.auth,json=dict(base,idempotencyKey="unsupported-provider")).status_code,422)
        with mobile.connect() as c:
            changed=dict(views[1],viewSetId="different-set")
            c.execute("UPDATE concepts SET data=? WHERE id=?",(json.dumps(changed),changed["id"]))
        self.assertEqual(self.client.post(url,headers=self.auth,json=dict(base,idempotencyKey="mixed-sibling-set")).status_code,422)
        with mobile.connect() as c:
            c.execute("UPDATE concepts SET data=? WHERE id=?",(json.dumps(views[1]),views[1]["id"]))
            source["validation"]={"usable":False,"issues":["pose changed"]}
            c.execute("UPDATE work SET data=? WHERE id=?",(json.dumps(source),source["id"]))
        self.assertEqual(self.client.post(url,headers=self.auth,json=dict(base,idempotencyKey="failed-validation")).status_code,422)
        self.assertEqual(self.balance()["available"],before)
        self.assertEqual(self.balance()["reserved"],0)
        self.assertEqual(self.q.calls,[])

    def test_default_settings_preserve_legacy_idempotent_signature(self):
        import json
        source=self.four_views();concept=source["concepts"][0]
        url=f"/api/mobile/concepts/{concept['id']}/model"
        body={"idempotencyKey":"legacy-default-model","engine":"rodin"}
        result=self.client.post(url,headers=self.auth,json=body)
        with mobile.connect() as c:
            signature=json.loads(c.execute("SELECT signature FROM work WHERE id=?",(result.json()["id"],)).fetchone()[0])
            self.assertNotIn("quality",signature[2]);self.assertNotIn("effort",signature[2]);self.assertNotIn("conceptIds",signature[2])
            signature[2]["count"]=4
            c.execute("UPDATE work SET signature=? WHERE id=?",(json.dumps(signature,sort_keys=True),result.json()["id"]))
        replay=self.client.post(url,headers=self.auth,json=dict(body,quality="default",effort="high"))
        self.assertEqual(replay.json()["id"],result.json()["id"])
        self.assertEqual(len(self.q.calls),1)

    def test_legacy_original_migration_is_free_stable_and_preserves_versions(self):
        import json
        from concurrent.futures import ThreadPoolExecutor
        photo=self.client.post("/api/mobile/projects",headers=self.auth,data={"prompt":"A small plant"},files={"image":("plant.png",self.image(128)["bytes"],"image/png")}).json()
        generated={"id":"existing-user-version","projectId":photo["id"],"name":"User concept","imageUrl":"/files/mobile/kept.png","prompt":"Keep this exact version","isOriginal":False}
        with mobile.connect() as c:
            owner=c.execute("SELECT owner FROM projects WHERE id=?",(photo["id"],)).fetchone()[0]
            c.execute("DELETE FROM concepts WHERE project=?",(photo["id"],))
            c.execute("INSERT INTO concepts VALUES(?,?,?,?)",(generated["id"],owner,photo["id"],json.dumps(generated)))
        before=self.balance()
        def read(_):return next(p for p in self.client.get("/api/mobile/projects",headers=self.auth).json() if p["id"]==photo["id"])
        with patch.object(mobile.gemini,"make_concept_set") as images,patch.object(mobile.jobs,"submit") as models,ThreadPoolExecutor(max_workers=3) as pool:
            results=list(pool.map(read,range(3)))
        images.assert_not_called();models.assert_not_called()
        ids=[]
        for result in results:
            self.assertIn(generated,result["concepts"])
            original=[c for c in result["concepts"] if c.get("isOriginal")]
            self.assertEqual(len(original),1)
            self.assertEqual(original[0]["imageUrl"],photo["imageUrl"])
            self.assertEqual((original[0]["width"],original[0]["height"]),(128,128))
            ids.append(original[0]["id"])
        self.assertEqual(len(set(ids)),1)
        self.assertTrue(ids[0].startswith("mc-original-"))
        self.assertEqual(self.balance(),before)
        self.assertEqual(self.q.calls,[])
        with mobile.connect() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM concepts WHERE project=?",(photo["id"],)).fetchone()[0],2)

    def test_legacy_missing_original_file_does_not_invent_a_reference(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("photo.png",self.image(128)["bytes"],"image/png")}).json()
        with mobile.connect() as c:c.execute("DELETE FROM concepts WHERE project=?",(photo["id"],))
        mobile.image_path(photo["imageUrl"]).unlink()
        before=self.balance()
        result=next(p for p in self.client.get("/api/mobile/projects",headers=self.auth).json() if p["id"]==photo["id"])
        self.assertEqual(result["concepts"],[])
        self.assertEqual(self.balance(),before)

    def test_original_direct_model_and_missing_reference_never_fall_back(self):
        photo=self.client.post("/api/mobile/projects",headers=self.auth,data={"prompt":"A red truck"},files={"image":("truck.png",self.image(128)["bytes"],"image/png")}).json()
        original=photo["concepts"][0]
        self.purchase()
        r=self.client.post(f"/api/mobile/concepts/{original['id']}/model",headers=self.auth,json={"idempotencyKey":"direct-original"})
        with patch.object(mobile.gemini,"make_concept_set") as generate,patch.object(mobile.jobs,"submit",return_value="truck") as submit,patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"truck-3d"}]}):self.q.flush()
        generate.assert_not_called();self.assertEqual(submit.call_args.args[1].images,[mobile.image_path(original["imageUrl"])])
        self.assertEqual(self.client.get("/api/mobile/jobs/"+r.json()["id"],headers=self.auth).json()["charged"],46)
        self.purchase("another-pack")
        mobile.image_path(original["imageUrl"]).unlink()
        before=self.balance()["available"]
        failed=self.client.post(f"/api/mobile/concepts/{original['id']}/model",headers=self.auth,json={"idempotencyKey":"missing-original"})
        with patch.object(mobile.jobs,"submit") as submit:self.q.flush()
        submit.assert_not_called()
        self.assertEqual(self.balance()["available"],before)
        self.assertEqual(self.client.get("/api/mobile/jobs/"+failed.json()["id"],headers=self.auth).json()["status"],"failed")

    def test_purchase_once_and_no_auto_generation(self):
        self.purchase(); self.purchase()
        self.assertEqual(self.balance()["available"],100)
        self.assertEqual(len(self.q.calls),0)
        # A new DB connection retains both credential and ledger.
        self.assertEqual(self.client.get("/api/mobile/wallet",headers=self.auth).json()["available"],100)

    def test_selected_concept_model_and_failure_refund(self):
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"cat"}),patch.object(mobile.gemini,"make_image",return_value=self.image()):
            j=self.start(count=1).json(); self.q.flush()
        cid=self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["concepts"][0]["id"]
        url=f"/api/mobile/concepts/{cid}/model"
        self.assertEqual(self.client.post(url,headers=self.auth,json={"idempotencyKey":"model-request"}).status_code,402)
        self.purchase()
        j=self.client.post(url,headers=self.auth,json={"idempotencyKey":"model-request"}).json()
        with patch.object(mobile.jobs,"submit",return_value="provider-one") as submit,patch.object(mobile.jobs,"get_job",return_value={"stage":"failed","progress":4,"message":"bad","error":"bad"}):
            self.q.flush()
        self.assertEqual(submit.call_args.args[1].images[0].name,cid+".png")
        self.assertEqual(self.balance()["available"],100)
        self.assertEqual(self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["charged"],0)

    def test_refine_preserves_parent_and_model_success_settles_once(self):
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":"cat"}),patch.object(mobile.gemini,"make_image",return_value=self.image()):
            j=self.start(count=1).json(); self.q.flush()
            original=self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["concepts"][0]
            r=self.client.post(f"/api/mobile/concepts/{original['id']}/refine",headers=self.auth,json={"idempotencyKey":"refine-request","prompt":"blue jacket"})
            self.q.flush()
        refined=self.client.get("/api/mobile/jobs/"+r.json()["id"],headers=self.auth).json()["concepts"][0]
        self.assertEqual(refined["parentId"],original["id"])
        self.assertNotEqual(refined["id"],original["id"])
        self.assertEqual(self.balance()["freeConceptTokens"],15)
        self.purchase()
        r=self.client.post(f"/api/mobile/concepts/{refined['id']}/model",headers=self.auth,json={"idempotencyKey":"model-success"})
        asset={"id":"asset-1","name":"My cat","modelUrl":"/files/asset-1/model.glb"}
        with patch.object(mobile.jobs,"submit",return_value="backend-success"),patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[asset]}):
            self.q.flush()
        done=self.client.get("/api/mobile/jobs/"+r.json()["id"],headers=self.auth).json()
        self.assertEqual(done["charged"],46)
        self.assertEqual(self.balance()["available"],54)
        # Repeated settlement with stale pre-settled data must not refund twice.
        with mobile.connect() as c:
            owner=c.execute("SELECT owner FROM work WHERE id=?",(done["id"],)).fetchone()[0]
            stale=dict(done,settled=False)
            mobile._settle(c,owner,stale,0)
        self.assertEqual(self.balance()["available"],54)
        with patch.object(mobile.jobs,"list_assets",return_value=[asset]):
            data=self.client.get("/api/mobile/assets",headers=self.auth).json()
        self.assertEqual(data["owned"],[asset]); self.assertEqual(data["examples"],[])

    def test_long_concept_uses_bounded_original_intent_and_selected_image(self):
        long_concept = "Detailed studio illumination and camera instructions. " * 100
        with patch.object(mobile.gemini,"write_prompt",return_value={"prompt":long_concept}),patch.object(mobile.gemini,"make_image",return_value=self.image()):
            j=self.start(count=1).json(); self.q.flush()
        concept=self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["concepts"][0]
        self.assertGreater(len(concept["prompt"]),1024)
        self.purchase()
        rodin=next(key for key in mobile.engines.ENGINES if "rodin" in key)
        r=self.client.post(f"/api/mobile/concepts/{concept['id']}/model",headers=self.auth,json={"idempotencyKey":"long-prompt-model","engine":rodin})
        self.assertEqual(r.status_code,200)
        def submit(engine, request, name):
            self.assertLessEqual(len(request.prompt),1024)
            self.assertIn("little cat",request.prompt)
            self.assertNotIn("studio illumination",request.prompt)
            self.assertEqual(request.images,[mobile.image_path(concept["imageUrl"])])
            return "bounded-model"
        with patch.object(mobile.jobs,"submit",side_effect=submit),patch.object(mobile.jobs,"get_job",return_value={"stage":"done","progress":100,"message":"Ready","assets":[{"id":"bounded-asset"}]}):
            self.q.flush()
        self.assertEqual(self.client.get("/api/mobile/jobs/"+r.json()["id"],headers=self.auth).json()["status"],"done")

    def test_restart_refunds_only_after_verified_dead_worker(self):
        j=self.start().json()
        # Reopening SQLite (including from a new importer) is never recovery.
        mobile._initialized.discard(str(mobile.DB_PATH))
        self.assertEqual(self.balance()["freeConceptTokens"],0)
        mobile.recover_abandoned()
        self.assertEqual(self.balance()["freeConceptTokens"],0)
        self.release_lease()  # represents OS releasing the lease on process exit
        mobile.recover_abandoned()
        mobile.recover_abandoned()
        self.assertEqual(self.balance()["freeConceptTokens"],45)
        self.assertEqual(self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["status"],"failed")
        with patch.object(mobile.gemini,"write_prompt") as provider:
            self.q.flush()
        provider.assert_not_called()  # a stale queued callback cannot restart it

    def test_separate_process_preserves_live_worker(self):
        j=self.start().json()
        code="from pathlib import Path; from server import mobile, codex_bridge; mobile.DB_PATH=Path("+repr(str(mobile.DB_PATH))+"); mobile.recover_abandoned()"
        subprocess.run([sys.executable,"-c",code],check=True,capture_output=True)
        self.assertEqual(self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["status"],"queued")
        self.assertEqual(self.balance()["freeConceptTokens"],0)

    def test_legacy_unknown_worker_and_stale_progress_are_preserved(self):
        j=self.start().json()
        with mobile.connect() as c:
            legacy=dict(j); legacy.pop("workerId"); legacy.pop("workerPid")
            c.execute("UPDATE work SET data=? WHERE id=?",(__import__("json").dumps(legacy),j["id"]))
        mobile.recover_abandoned()
        self.assertEqual(self.balance()["freeConceptTokens"],0)
        with mobile.connect() as c:
            owner=c.execute("SELECT owner FROM work WHERE id=?",(j["id"],)).fetchone()[0]
            terminal=dict(j,status="failed")
            mobile._settle(c,owner,terminal,0)
        mobile.save_job(owner,dict(j,status="running"))
        with mobile.connect() as c:
            mobile._settle(c,owner,dict(j,status="failed"),0)
        self.assertEqual(self.balance()["freeConceptTokens"],45)
        self.assertEqual(self.client.get("/api/mobile/jobs/"+j["id"],headers=self.auth).json()["status"],"failed")

    def test_preupgrade_ledger_settlement_cannot_be_applied_twice(self):
        import json
        j=self.start().json()
        with mobile.connect() as c:
            owner=c.execute("SELECT owner FROM work WHERE id=?",(j["id"],)).fetchone()[0]
            mobile._settle(c,owner,dict(j,status="failed"),0)
            c.execute("DELETE FROM settlements WHERE job_id=?",(j["id"],))
            c.execute("UPDATE work SET data=? WHERE id=?",(json.dumps(j),j["id"]))
            mobile._settle(c,owner,dict(j,status="failed"),0)
        self.assertEqual(self.balance()["freeConceptTokens"],45)
        with mobile.connect() as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM settlements WHERE job_id=?",(j["id"],)).fetchone()[0],1)

    def test_examples_are_not_owned(self):
        with patch.object(mobile.jobs,"list_assets",return_value=[{"id":"existing","name":"Cat","galleryExample":{"slug":"sample-cat"},"visibility":"public"}, {"id":"user-dog","name":"A cut dog"}]):
            data=self.client.get("/api/mobile/assets",headers=self.auth).json()
        self.assertEqual(data["owned"],[])
        self.assertEqual(data["examples"][0]["ownership"],"example")
        self.assertEqual([asset["id"] for asset in data["examples"]],["existing"])

    def test_invalid_upload_rejected_before_project_creation(self):
        r=self.client.post("/api/mobile/projects",headers=self.auth,files={"image":("bad.png",b"not image","image/png")})
        self.assertEqual(r.status_code,422)


if __name__ == "__main__": unittest.main()
