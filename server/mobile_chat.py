"""Owner-scoped, persisted creative conversations. No generation or credit charge here."""
from __future__ import annotations
import json
import os
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from fastapi import Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, Field
from . import gemini, planning

_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="creative-chat")
from .creative_prompts import CHAT_SCHEMA as SCHEMA, CHAT_SYSTEM as SYSTEM

class ChatTurnRequest(BaseModel):
    clientId: str = Field(min_length=8, max_length=120)
    text: str = Field(min_length=1, max_length=4000)
    plannerModel: str = Field(default=planning.DEFAULT_MODEL, max_length=120)
    plannerEffort: str = Field(default="low", max_length=20)
    conceptId: str | None = None
    style: str = Field(default="Stylized", max_length=100)


def plan_turn(owner, model, effort, history, image, style):
    latest_user_text = next((turn.get("text", "") for turn in reversed(history) if turn.get("role") == "user"), "")
    user_is_chinese = any("\u4e00" <= char <= "\u9fff" for char in latest_user_text)
    lang_directive = (
        "User is communicating in Chinese (中文). All fields ('reply', 'suggestions', 'brief') MUST be in Chinese."
        if user_is_chinese else
        "User is communicating in English (or non-Chinese). All fields ('reply', 'suggestions', 'brief') MUST be strictly in English. Do NOT use Chinese words."
    )
    content_data = {
        "selectedStyle": style,
        "detectedUserLanguage": "Chinese (zh-CN)" if user_is_chinese else "English (en-US)",
        "languageRequirement": lang_directive,
        "conversation": history
    }
    prompt = SYSTEM + "\nContext:\n" + json.dumps(content_data, ensure_ascii=False)
    if model == planning.DEFAULT_MODEL:
        parts = ([gemini._inline(image)] if image and image.is_file() else []) + [{"text": prompt}]
        data = gemini._call(gemini.GEMINI_TEXT_MODEL, {"contents": [{"role": "user", "parts": parts}],
            "generationConfig": {"responseMimeType": "application/json", "responseSchema": {key: value for key, value in SCHEMA.items() if key != "additionalProperties"}}})
        parts = (data.get("candidates") or [{}])[0].get("content", {}).get("parts", [])
        result = json.loads(next((p["text"] for p in parts if p.get("text") and not p.get("thought")), "{}"))
    else:
        from .codex_bridge import plan
        result = plan(owner, model, prompt, [image] if image else [], SCHEMA, effort=effort)
    if (not isinstance(result, dict) or not isinstance(result.get("reply"), str) or not result["reply"].strip()
        or not isinstance(result.get("brief"), str) or not result["brief"].strip()
        or type(result.get("ready")) is not bool or not isinstance(result.get("suggestions"), list)
        or any(not isinstance(s, str) for s in result["suggestions"])):
        raise ValueError("The creative assistant returned an incomplete response. Please try again.")
    return {"reply": result["reply"][:4000], "brief": result["brief"][:4000], "ready": result["ready"],
            "suggestions": [s[:120] for s in result["suggestions"][:3]]}


def turns_for(c, owner, project_id):
    return [json.loads(row[0]) for row in c.execute(
        "SELECT data FROM chat_turns WHERE owner=? AND project=? ORDER BY rowid", (owner, project_id))]


def execute_turn(owner, project, turn, body):
    from . import mobile
    try:
        planning.require_available(owner, body.plannerModel, body.plannerEffort)
        with mobile.connect() as c:
            turns = turns_for(c, owner, project["id"])
        history = []
        for item in turns[-20:]:
            history.append({"role": "user", "text": item["text"]})
            if item.get("reply"): history.append({"role": "assistant", "text": item["reply"], "brief": item.get("brief", "")})
        source = project.get("imageUrl")
        if body.conceptId:
            concept = mobile.record("concepts", body.conceptId, owner)
            if concept["projectId"] != project["id"]: raise ValueError("Choose an image from this conversation")
            source = concept["imageUrl"]
        image = mobile.image_path(source) if source else None
        result = plan_turn(owner, body.plannerModel, body.plannerEffort, history, image, body.style)
        turn.update(result, status="done")
    except Exception:
        # Never surface provider request URLs or authentication details.
        turn.update(status="failed", error="Your message is saved, but the assistant could not reply. Check your selected planning model and try again.")
    with mobile.connect() as c:
        c.execute("UPDATE chat_turns SET data=? WHERE id=? AND owner=?", (json.dumps(turn), turn["id"], owner))


def install(router):
    from . import mobile

    @router.post("/projects/{project_id}/references")
    async def reference(project_id: str, image: UploadFile = File(...), owner=Depends(mobile.account)):
        mobile.record("projects", project_id, owner)
        raw = await image.read(20 * 1024 * 1024 + 1)
        if len(raw) > 20 * 1024 * 1024: raise HTTPException(413, "Choose a photo under 20 MB")
        import io
        from PIL import Image, ImageOps
        cid = "mc-" + uuid.uuid4().hex
        try:
            with Image.open(io.BytesIO(raw)) as im:
                if im.width * im.height > 40_000_000: raise ValueError("Image too large")
                im = ImageOps.exif_transpose(im).convert("RGB")
                dest = mobile.STORAGE / "mobile" / (cid + ".png")
                dest.parent.mkdir(parents=True, exist_ok=True)
                im.save(dest)
                width, height = im.size
        except Exception as exc:
            raise HTTPException(422, "Choose a valid reference image") from exc
        concept = {"id": cid, "projectId": project_id, "name": "Reference", "label": "Reference",
                   "prompt": "", "imageUrl": "/files/mobile/" + dest.name, "width": width, "height": height,
                   "isOriginal": True, "createdAt": time.time()}
        with mobile.connect() as c:
            c.execute("INSERT INTO concepts VALUES(?,?,?,?)", (cid, owner, project_id, json.dumps(concept)))
        return concept

    @router.post("/projects/{project_id}/chat")
    def send(project_id: str, body: ChatTurnRequest, owner=Depends(mobile.account)):
        if (owner.startswith("firebase:") and body.plannerModel == planning.DEFAULT_MODEL
                and not (os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") == "1" and not mobile.IS_PRODUCTION)):
            from .identity import require_paid
            require_paid(owner)
            raise HTTPException(503, "Paid chat is being connected. Your credits have not been charged.")
        project = mobile.record("projects", project_id, owner)
        if not body.text.strip(): raise HTTPException(422, "Write a message first")
        if body.conceptId:
            source = mobile.record("concepts", body.conceptId, owner)
            if source["projectId"] != project_id: raise HTTPException(422, "Choose an image from this conversation")
        payload = body.model_dump(exclude={"clientId"})
        with mobile.connect() as c:
            c.execute("BEGIN IMMEDIATE")
            rows = turns_for(c, owner, project_id)
            prior = next((t for t in rows if t["clientId"] == body.clientId), None)
            if prior:
                if prior["request"] != payload: raise HTTPException(409, "This message ID already belongs to a different message")
                return prior
            for row in rows:
                if row["status"] == "working":
                    if mobile.worker_alive(row.get("workerId")):
                        raise HTTPException(409, "Wait for the assistant's current reply")
                    row.update(status="failed", error="The studio restarted. Your message is saved; please try again.")
                    c.execute("UPDATE chat_turns SET data=? WHERE id=?", (json.dumps(row), row["id"]))
            turn = {"id": "chat-" + uuid.uuid4().hex, "projectId": project_id, "clientId": body.clientId,
                    "text": body.text.strip(), "status": "working", "createdAt": time.time(),
                    "request": payload, "workerId": mobile.process_owner()}
            c.execute("INSERT INTO chat_turns VALUES(?,?,?,?,?)", (turn["id"], owner, project_id, body.clientId, json.dumps(turn)))
        _pool.submit(execute_turn, owner, project, turn.copy(), body)
        return turn
