#!/usr/bin/env python3
"""Isolated localhost UI fixture. No provider calls, user data or real ledger changes.
Run from repository root: venv/bin/python ios/scripts/chat-review-server.py
"""
import sys, tempfile, json, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from fastapi import FastAPI
from server import mobile, mobile_chat
import uvicorn

sandbox = tempfile.TemporaryDirectory(prefix="craft-chat-review-")
mobile.DB_PATH = Path(sandbox.name) / "review.sqlite3"
app = FastAPI()
app.include_router(mobile.router)
app.dependency_overrides[mobile.account] = lambda: "chat-ui-review"
app.dependency_overrides[mobile.development] = lambda: None

def reply(*args):
    return {"reply":"A little explorer on two wheels — I can picture it. What kind of world will they ride through?",
            "brief":"A cheerful ginger cat riding a bicycle, full body, stylized cozy game art with clear separated forms, soft mint background.",
            "ready":False,"suggestions":["A cozy forest adventure","A colorful racing game","Surprise me"]}
mobile_chat.plan_turn = reply
mobile_chat.planning.require_available = lambda *args: None
# Deliberately fail if a UI test accidentally confirms a paid provider action.
mobile.enqueue = lambda *args, **kwargs: (_ for _ in ()).throw(RuntimeError("Paid generation is disabled in the UI fixture"))
now = time.time()
project = {"id":"chat-ui-review", "name":"Bicycle explorer — UI fixture", "prompt":"A cat riding a bicycle", "style":"Stylized", "imageUrl":None, "createdAt":now, "concepts":[]}
turn = {"id":"chat-ui-turn", "projectId":project["id"], "clientId":"chat-ui-turn", "text":"A cat riding a bicycle", "status":"done", "createdAt":now, **reply()}
concept = {"id":"chat-ui-concept", "projectId":project["id"], "name":"Existing sample for UI review", "label":"Lantern Explorer", "prompt":"Existing public sample", "imageUrl":"http://127.0.0.1:8001/files/gallery-samples/lantern-explorer.png", "width":2048,"height":2048,"viewSetId":"chat-ui-images"}
asset = {"id":"chat-ui-model","name":"Lantern Explorer", "kind":"character", "faces":94000,"fileSizeMb":10,"modelUrl":"http://127.0.0.1:8001/files/a-a44cd03b47/model.glb"}
image_job = {"id":"chat-ui-images","projectId":project["id"],"kind":"concepts","status":"done","progress":100,"message":"UI fixture","concepts":[concept],"assets":[],"createdAt":now+1,"charged":0}
model_job = {"id":"chat-ui-3d","projectId":project["id"],"kind":"model","status":"done","progress":100,"message":"UI fixture","selectedConceptId":concept["id"],"selectedImageUrl":concept["imageUrl"],"concepts":[],"assets":[asset],"createdAt":now+2,"charged":0}
with mobile.connect() as c:
    c.execute("INSERT INTO users VALUES(?,?,?,?)", ("chat-ui-review","unused-ui-fixture",1000,45))
    c.execute("INSERT INTO projects VALUES(?,?,?)", (project["id"],"chat-ui-review",json.dumps(project)))
    c.execute("INSERT INTO chat_turns VALUES(?,?,?,?,?)", (turn["id"],"chat-ui-review",project["id"],turn["clientId"],json.dumps(turn)))
    c.execute("INSERT INTO concepts VALUES(?,?,?,?)",(concept["id"],"chat-ui-review",project["id"],json.dumps(concept)))
    for job in [image_job,model_job]: c.execute("INSERT INTO work VALUES(?,?,?,?,?)",(job["id"],"chat-ui-review",job["id"],job["id"],json.dumps(job)))
uvicorn.run(app, host="127.0.0.1", port=8003, log_level="warning")
