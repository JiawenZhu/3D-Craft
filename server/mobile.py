"""Authenticated loopback-only iOS review API. No production identity or billing.

SQLite persists sessions, drafts, jobs and a transactional token ledger. Provider
calls are never retried automatically: restart-interrupted jobs release their
reservation, keeping any successfully saved concept versions.
"""
from __future__ import annotations
import fcntl
import hashlib
import io
import json
import os
import secrets
import sqlite3
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Request, UploadFile
from pydantic import BaseModel, Field
from PIL import Image

from . import pricing, engines, gemini, jobs, image_models, thumbnails
from .config import IS_PRODUCTION, RUNS, STORAGE
from .engines.base import GenRequest

router = APIRouter(prefix="/api/mobile", tags=["iOS local review"])
DB_PATH = RUNS / "mobile.sqlite3"
_pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="mobile")
_init_lock = threading.Lock()
_initialized: set[str] = set()
_process_id = uuid.uuid4().hex
_process_leases: dict[str, object] = {}
_lease_lock = threading.Lock()
PRODUCTS = [
    {"id": "craft.creator.weekly.v1", "name": "Creator Weekly", "price": 4.99, "tokens": 250, "period": "week"},
    {"id": "craft.creator.monthly.v1", "name": "Creator Monthly", "price": 14.99, "tokens": 850, "period": "month"},
    {"id": "craft.credits.small.v1", "name": "Extra Credits", "price": 4.99, "tokens": 200, "period": "once"},
    {"id": "craft.credits.medium.v1", "name": "Creator Pack", "price": 9.99, "tokens": 500, "period": "once"},
    {"id": "craft.credits.large.v1", "name": "Studio Pack", "price": 19.99, "tokens": 1200, "period": "once"},
    {"id": "starter", "name": "Starter Pack", "price": 3.99, "tokens": 100, "period": "once"},
    {"id": "weekly", "name": "Creator Weekly", "price": 7.99, "tokens": 300, "period": "week"},
]
EFFORT_STEPS = {
    "extreme-low": 15,
    "low": 25,
    "medium": 35,
    "high": 50,
    "extreme-high": 75,
}


def _connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    c = sqlite3.connect(DB_PATH, timeout=30)
    c.row_factory = sqlite3.Row
    with _init_lock:
        key = str(DB_PATH)
        if key not in _initialized:
            c.executescript("""
            CREATE TABLE IF NOT EXISTS chat_turns(id TEXT PRIMARY KEY, owner TEXT, project TEXT, client_id TEXT, data TEXT, UNIQUE(owner,project,client_id));
            CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, token TEXT UNIQUE, paid INTEGER DEFAULT 0, trial INTEGER DEFAULT 45);
            CREATE TABLE IF NOT EXISTS projects(id TEXT PRIMARY KEY, owner TEXT, data TEXT);
            CREATE TABLE IF NOT EXISTS concepts(id TEXT PRIMARY KEY, owner TEXT, project TEXT, data TEXT);
            CREATE TABLE IF NOT EXISTS work(id TEXT PRIMARY KEY, owner TEXT, idem TEXT, signature TEXT, data TEXT, UNIQUE(owner,idem));
            CREATE TABLE IF NOT EXISTS ledger(id TEXT PRIMARY KEY, owner TEXT, kind TEXT, amount INTEGER, created REAL, data TEXT);
            CREATE TABLE IF NOT EXISTS purchases(transaction_id TEXT PRIMARY KEY, owner TEXT, product TEXT);
            CREATE TABLE IF NOT EXISTS settlements(job_id TEXT PRIMARY KEY, owner TEXT, charged INTEGER, created REAL);
            """)
            c.commit()
            _initialized.add(key)
    return c


@contextmanager
def connect():
    c = _connect()
    try:
        with c:
            yield c
    finally:
        c.close()


def process_owner():
    """Hold a process-unique OS lock for the lifetime of this worker process."""
    key = str(DB_PATH.resolve())
    with _lease_lock:
        if key not in _process_leases:
            folder = DB_PATH.parent / "mobile-workers"
            folder.mkdir(parents=True, exist_ok=True)
            lease = (folder / (_process_id + ".lock")).open("a+")
            fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            _process_leases[key] = lease
    return _process_id


def worker_alive(worker_id):
    # Legacy jobs lack ownership evidence. Never infer that they are stopped.
    if not worker_id:
        return True
    path = DB_PATH.parent / "mobile-workers" / (worker_id + ".lock")
    if not path.exists():
        return False
    with path.open("a+") as lease:
        try:
            fcntl.flock(lease.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
        fcntl.flock(lease.fileno(), fcntl.LOCK_UN)
        return False


def recover_abandoned():
    """Explicit lifecycle operation; opening a connection never changes jobs.

    Only a released OS process lease proves a worker stopped. Other live server
    processes and legacy jobs are preserved, regardless of elapsed time.
    """
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        for row in c.execute("SELECT * FROM work").fetchall():
            data = json.loads(row["data"])
            if data["status"] in ("queued", "running") and not worker_alive(data.get("workerId")):
                data.update(status="failed", error="Worker stopped. Unfinished work was not retried; unused Tokens returned.", message="Interrupted worker")
                _settle(c, row["owner"], data, len(data.get("concepts", [])) * data.get("imageTokenCost", 15))


@router.on_event("startup")
def mobile_startup():
    if os.getenv("RODIN_MOBILE_DEVELOPMENT") == "1":
        recover_abandoned()


def development(request: Request):
    if IS_PRODUCTION:
        # In production, require HTTPS to protect credentials and payloads in transit
        proto = request.headers.get("x-forwarded-proto", request.url.scheme).lower()
        is_loopback = request.client and request.client.host in ("127.0.0.1", "::1", "testclient")
        if proto != "https" and not is_loopback:
            raise HTTPException(403, "HTTPS is required in production.")
        return

    if os.getenv("RODIN_MOBILE_DEVELOPMENT") != "1":
        raise HTTPException(503, "Local iOS review is disabled. Set RODIN_MOBILE_DEVELOPMENT=1 on the local server.")
    if not request.client or request.client.host not in ("127.0.0.1", "::1", "testclient"):
        raise HTTPException(403, "Development sessions are available only over loopback.")


def account(request: Request, authorization: str = Header(default="")):
    if os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") != "1" or IS_PRODUCTION or authorization.removeprefix("Bearer ").count(".") == 2:
        from .identity import require_account
        return require_account(authorization)
    development(request)
    token = authorization.removeprefix("Bearer ")
    with connect() as c:
        row = c.execute("SELECT id FROM users WHERE token=?", (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()
    if not row:
        raise HTTPException(401, "Sign in to this local review session again.")
    return row["id"]


def wallet(owner):
    with connect() as c:
        u = c.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone()
        if not u:
            paid = 1000 if (not owner.startswith("firebase:") and os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") == "1" and not IS_PRODUCTION) else 0
            trial = 45 if (not owner.startswith("firebase:") and os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") == "1" and not IS_PRODUCTION) else 0
            c.execute("INSERT OR IGNORE INTO users(id,token,paid,trial) VALUES(?,?,?,?)", (owner, owner, paid, trial))
            c.commit()
            u = c.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone()
        entries = [dict(r) for r in c.execute("SELECT kind,amount,created,data FROM ledger WHERE owner=? ORDER BY created DESC", (owner,))]
        pending = [json.loads(r[0]) for r in c.execute("SELECT data FROM work WHERE owner=?", (owner,))]
    return {"available": u["paid"] if u else 0, "freeConceptTokens": u["trial"] if u else 0, "reserved": sum(j["reserved"] for j in pending if j["status"] in ("queued", "running")), "ledger": entries}


class Session(BaseModel):
    deviceId: str = Field(min_length=8, max_length=120)


@router.post("/session")
def session(body: Session, request: Request):
    if IS_PRODUCTION or os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") != "1":
        raise HTTPException(403, "Device sessions are disabled. Sign in to your 3D Craft account.")
    development(request)
    # deviceId is a label, never authentication. Each new session is isolated;
    # clients retain the unguessable credential in Keychain across launches.
    owner, token = uuid.uuid4().hex, secrets.token_urlsafe(40)
    with connect() as c:
        c.execute("INSERT INTO users(id,token) VALUES(?,?)", (owner, hashlib.sha256(token.encode()).hexdigest()))
    return {"token": token, "userId": owner, "mode": "development", "wallet": wallet(owner)}


@router.get("/pricing")
def provider_pricing(owner=Depends(account)):
    return pricing.catalog()


@router.get("/bootstrap")
def bootstrap(owner=Depends(account)):
    grant_review_credits(owner, initial=True)
    statuses = engines.status_all()
    catalog = [{"id": eid, "label": engine.label, **statuses[eid],
                "multiView": (statuses[eid].get("provider") == "api" if eid != "hybrid" else statuses[eid].get("provider") == "api+api"),
                "multiViewDirections": ["front", "back", "left"] if eid in ("hunyuan3d-2.1", "hunyuan3d-2-white", "hybrid") else ["front", "back", "left", "right"]}
               for eid, engine in engines.ENGINES.items()]
    return {"mode": "development", "prices": {"concept": 15, "refine": 15, "model": pricing.model_quote("rodin")["usageWithServiceFee"]["credits"]},
            "products": PRODUCTS, "engines": list(engines.ENGINES), "engineCatalog": catalog,
            "modelOptions": {"qualities": ["default", "speedy"], "efforts": list(EFFORT_STEPS),
                             "defaultQuality": "default", "defaultEffort": "high", "cost": pricing.model_quote("rodin")["usageWithServiceFee"]["credits"], "pricing": "provider_cost_plus_service_fee"}, "wallet": wallet(owner)}


@router.get("/wallet")
def get_wallet(owner=Depends(account)):
    return wallet(owner)


def record(table, ident, owner):
    with connect() as c:
        row = c.execute(f"SELECT data FROM {table} WHERE id=? AND owner=?", (ident, owner)).fetchone()
    if not row:
        raise HTTPException(404, "Item not found in your workspace")
    return json.loads(row[0])


@router.post("/projects")
async def create_project(prompt: str = Form(default=""), name: str = Form(default="Untitled idea"), style: str = Form(default="Stylized"), image: UploadFile | None = File(default=None), owner=Depends(account)):
    if len(prompt) > 4000 or len(name) > 120:
        raise HTTPException(422, "Description is too long")
    ident = "mp-" + uuid.uuid4().hex
    data = {"id": ident, "name": name, "prompt": prompt, "style": style, "imageUrl": None, "createdAt": time.time(), "concepts": []}
    if image:
        raw = await image.read(20 * 1024 * 1024 + 1)
        if len(raw) > 20 * 1024 * 1024:
            raise HTTPException(413, "Use an image smaller than 20 MB")
        try:
            im = Image.open(io.BytesIO(raw)); im.load()
            if im.width * im.height > 40_000_000:
                raise ValueError("Image dimensions exceed limit")
            path = STORAGE / "mobile" / (ident + ".png")
            path.parent.mkdir(parents=True, exist_ok=True)
            from PIL import ImageOps
            ImageOps.exif_transpose(im).convert("RGB").save(path)
            data["imageUrl"] = "/files/mobile/" + path.name
        except Exception as exc:
            raise HTTPException(422, "Choose a valid JPEG, PNG or WebP image") from exc
    if not prompt.strip() and not data["imageUrl"]:
        raise HTTPException(422, "Add a photo or describe your idea")
    original = None
    if data["imageUrl"]:
        with Image.open(image_path(data["imageUrl"])) as saved:
            width, height = saved.size
        original = {"id": "mc-" + uuid.uuid4().hex, "projectId": ident, "parentId": None,
                    "name": "Original (Direct 3D)", "label": "Original (Direct 3D)",
                    "prompt": prompt, "imageUrl": data["imageUrl"], "width": width, "height": height,
                    "isOriginal": True, "direction": None, "createdAt": time.time()}
        data["concepts"] = [original]
    with connect() as c:
        c.execute("INSERT INTO projects VALUES(?,?,?)", (ident, owner, json.dumps(data)))
        if original:
            c.execute("INSERT INTO concepts VALUES(?,?,?,?)", (original["id"], owner, ident, json.dumps(original)))
    return data


@router.get("/projects")
def list_projects(owner=Depends(account)):
    with connect() as c:
        # Upgrade legacy local drafts on first read. This creates only a free
        # reference record; it never renders an image, starts 3D or edits a
        # user's generated versions. Serialize readers to avoid duplicate rows.
        c.execute("BEGIN IMMEDIATE")
        result = [json.loads(r[0]) for r in c.execute("SELECT data FROM projects WHERE owner=? ORDER BY rowid DESC", (owner,))]
        concepts = [json.loads(r[0]) for r in c.execute("SELECT data FROM concepts WHERE owner=?", (owner,))]
        originals = {v["projectId"] for v in concepts if v.get("isOriginal")}
        for project in result:
            source_url = project.get("imageUrl")
            if project["id"] in originals or not source_url or not source_url.startswith("/files/mobile/"):
                continue
            source = image_path(source_url)
            if not source.is_file():
                continue
            try:
                with Image.open(source) as image:
                    width, height = image.size
            except (OSError, ValueError):
                continue
            cid = "mc-original-" + uuid.uuid5(uuid.NAMESPACE_URL, f"craft-mobile:{owner}:{project['id']}:original").hex
            original = {"id": cid, "projectId": project["id"], "parentId": None,
                        "name": "Original (Direct 3D)", "label": "Original (Direct 3D)",
                        "prompt": project.get("prompt", ""), "imageUrl": source_url,
                        "width": width, "height": height, "isOriginal": True,
                        "direction": None, "createdAt": project.get("createdAt", time.time())}
            c.execute("INSERT OR IGNORE INTO concepts VALUES(?,?,?,?)", (cid, owner, project["id"], json.dumps(original)))
            concepts.append(original)
            originals.add(project["id"])
    from .mobile_chat import turns_for
    with connect() as c:
        for p in result:
            p["conversation"] = turns_for(c, owner, p["id"])
            for turn in p["conversation"]:
                if turn["status"] == "working" and not worker_alive(turn.get("workerId")):
                    turn.update(status="failed", error="The studio restarted. Your message is saved; please try again.")
                    c.execute("UPDATE chat_turns SET data=? WHERE id=?", (json.dumps(turn), turn["id"]))
    for p in result:
        p["concepts"] = [x for x in concepts if x["projectId"] == p["id"]]
    return result


from . import planning


class Generate(BaseModel):
    idempotencyKey: str = Field(min_length=8, max_length=120)
    count: int = Field(default=3, ge=1, le=4)
    prompt: str = Field(default="", max_length=4000)
    engine: str = "rodin"
    imageModel: Literal["gemini-3-pro-image", "codex-gpt-image-2"] = "gemini-3-pro-image"
    plannerModel: str = Field(default=planning.DEFAULT_MODEL, min_length=1, max_length=120)
    plannerEffort: Literal["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"] = "low"
    quality: Literal["default", "speedy"] = "default"
    effort: Literal["extreme-low", "low", "medium", "high", "extreme-high"] = "high"
    preserveReference: bool = False
    referenceId: str | None = Field(default=None, max_length=120)
    style: str | None = Field(default=None, max_length=100)
    conceptIds: list[str] | None = Field(default=None, min_length=1, max_length=4)
    modelPrompt: str | None = Field(default=None, max_length=800)


def _settle(c, owner, data, charge):
    prior = c.execute("SELECT charged FROM settlements WHERE job_id=?", (data["id"],)).fetchone()
    if prior:
        return
    # Preserve settlements written by the pre-lease server, even if a stale
    # worker subsequently overwrote its work JSON with settled=False.
    historical = next((r for r in c.execute("SELECT amount,data FROM ledger WHERE owner=? AND kind='settle' ORDER BY created", (owner,)) if json.loads(r["data"]).get("jobId") == data["id"]), None)
    if historical:
        c.execute("INSERT OR IGNORE INTO settlements VALUES(?,?,?,?)", (data["id"], owner, -historical["amount"], time.time()))
        return
    if data.get("settled"):
        return
    charge = min(data["cost"], charge)
    c.execute("INSERT INTO settlements VALUES(?,?,?,?)", (data["id"], owner, charge, time.time()))
    trial_used = min(data["trialReserved"], charge)
    paid_used = charge - trial_used
    c.execute("UPDATE users SET paid=paid+?,trial=trial+? WHERE id=?", (data["paidReserved"] - paid_used, data["trialReserved"] - trial_used, owner))
    data.update(charged=charge, reserved=0, settled=True)
    c.execute("UPDATE work SET data=? WHERE id=?", (json.dumps(data), data["id"]))
    c.execute("INSERT INTO ledger VALUES(?,?,?,?,?,?)", (uuid.uuid4().hex, owner, "settle", -charge, time.time(), json.dumps({"jobId": data["id"], "returned": data["cost"] - charge})))


def enqueue(owner, project, kind, body, concept=None):
    image_token_cost = 0 if kind != "model" and body.imageModel == image_models.CODEX_MODEL else 15
    account_only = kind != "model" and image_token_cost == 0 and (body.preserveReference or body.plannerModel != planning.DEFAULT_MODEL)
    local_review = os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") == "1" and not IS_PRODUCTION
    if owner.startswith("firebase:") and not account_only and not local_review:
        from .identity import require_paid
        require_paid(owner)
        # Until provider-cost settlement is integrated, never spend a customer's
        # purchased balance using the old 15/55 review tariffs.
        raise HTTPException(503, "Paid generation is being connected. Your credits have not been charged.")
    cost = 0 if kind == "model" else (body.count if kind == "concepts" else 1) * image_token_cost
    # Omit new default-valued fields so pre-upgrade idempotent requests retain
    # their exact signature. Explicit nondefaults and multiview remain bound.
    payload = body.model_dump(exclude={"idempotencyKey", "quality", "effort", "conceptIds", "modelPrompt", "imageModel", "plannerModel", "plannerEffort", "referenceId", "style", "preserveReference"})
    if body.modelPrompt is not None: payload["modelPrompt"] = body.modelPrompt
    if body.preserveReference:
        if kind != "concepts" or not (body.referenceId or project.get("imageUrl")):
            raise HTTPException(422, "Attach an image for reference generation")
        payload["preserveReference"] = True
    if body.style is not None: payload["style"] = body.style
    if body.referenceId is not None:
        reference = record("concepts", body.referenceId, owner)
        if reference["projectId"] != project["id"]: raise HTTPException(422, "Choose a reference from this conversation")
        payload["referenceId"] = body.referenceId
    if body.quality != "default": payload["quality"] = body.quality
    if body.effort != "high": payload["effort"] = body.effort
    if body.conceptIds is not None: payload["conceptIds"] = body.conceptIds
    if kind != "model" and body.imageModel != image_models.DEFAULT_MODEL: payload["imageModel"] = body.imageModel
    if kind != "model" and body.plannerModel != planning.DEFAULT_MODEL:
        payload["plannerModel"] = body.plannerModel
        if body.plannerEffort != "low": payload["plannerEffort"] = body.plannerEffort
    selected_image_model = None
    if kind != "model":
        # Account discovery can make a network request: never hold SQLite's
        # writer lock while waiting, and allow known requests to reconcile.
        with connect() as preflight:
            known = preflight.execute("SELECT 1 FROM work WHERE owner=? AND idem=?", (owner, body.idempotencyKey)).fetchone()
        if not known:
            try:
                if not body.preserveReference:
                    planning.require_available(owner, body.plannerModel, body.plannerEffort)
                image_account = None
                if body.imageModel == image_models.CODEX_MODEL:
                    from .codex_bridge import account_status
                    image_account = account_status(owner)
                selected_image_model = image_models.require_available(body.imageModel, image_account)
            except ValueError as exc:
                raise HTTPException(422, str(exc)) from None
            except RuntimeError as exc:
                raise HTTPException(503, str(exc)) from None
    sig = json.dumps([project["id"], kind, payload, concept and concept["id"]], sort_keys=True)
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        existing = c.execute("SELECT * FROM work WHERE owner=? AND idem=?", (owner, body.idempotencyKey)).fetchone()
        if existing:
            previous = json.loads(existing["signature"])
            requested = json.loads(sig)
            if kind in ("model", "refine"):
                # count never controls these operations; a previous release's
                # default count must not invalidate the same authorized work.
                previous[2].pop("count", None); requested[2].pop("count", None)
            if previous != requested:
                raise HTTPException(409, "This request key was already used for different work")
            return json.loads(existing["data"])
        if kind == "model":
            concept = select_model_views(owner, body, concept)
            model_quote = pricing.model_quote(body.engine, views=max(1, len(concept.get("modelViews", []))), effort=body.effort)
            cost = model_quote["usageWithServiceFee"]["credits"]
            if cost is None:
                raise HTTPException(422, "Price pending for this model and view combination. Choose a single view or another model. No Tokens were charged.")
        u = c.execute("SELECT * FROM users WHERE id=?", (owner,)).fetchone()
        trial = min(u["trial"], cost) if kind != "model" else 0
        paid = cost - trial
        if u["paid"] < paid:
            raise HTTPException(402, "Not enough Tokens. Add a local test pack, then confirm generation again.")
        ident = "mj-" + uuid.uuid4().hex
        data = {"id": ident, "projectId": project["id"], "kind": kind, "status": "queued", "progress": 0, "message": "Queued", "concepts": [], "assets": [], "cost": cost, "reserved": cost, "charged": 0, "paidReserved": paid, "trialReserved": trial, "createdAt": time.time(), "error": None, "workerId": process_owner(), "workerPid": os.getpid()}
        if kind == "model":
            data.update(selectedConceptId=concept["id"], selectedImageUrl=concept["imageUrl"],
                        providerEstimate=model_quote)
        else:
            data["imageTokenCost"] = image_token_cost
            if body.preserveReference:
                source = record("concepts", body.referenceId, owner) if body.referenceId else project
                data.update(sourcePrompt=body.prompt if body.referenceId else body.prompt or project["prompt"], selectedImageUrl=source.get("imageUrl"), preserveReference=True)
            data.update(imageModel=body.imageModel, imageProvider=selected_image_model["provider"],
                        plannerModel=body.plannerModel, plannerEffort=body.plannerEffort, plannerProvider="gemini" if body.plannerModel == planning.DEFAULT_MODEL else "chatgpt")
        c.execute("UPDATE users SET paid=paid-?,trial=trial-? WHERE id=?", (paid, trial, owner))
        c.execute("INSERT INTO work VALUES(?,?,?,?,?)", (ident, owner, body.idempotencyKey, sig, json.dumps(data)))
        c.execute("INSERT INTO ledger VALUES(?,?,?,?,?,?)", (uuid.uuid4().hex, owner, "reserve", -cost, time.time(), json.dumps({"jobId": ident})))
    _pool.submit(run, owner, data, project, body, concept)
    return data


@router.get("/image-models")
def available_image_models(owner=Depends(account)):
    from .codex_bridge import account_status
    return image_models.catalog(account_status(owner))


@router.post("/projects/{project_id}/concepts")
def concepts(project_id: str, body: Generate, owner=Depends(account)):
    return enqueue(owner, record("projects", project_id, owner), "concepts", body)


@router.post("/concepts/{concept_id}/refine")
def refine(concept_id: str, body: Generate, owner=Depends(account)):
    if not body.prompt.strip():
        raise HTTPException(422, "Describe what to change")
    concept = record("concepts", concept_id, owner)
    return enqueue(owner, record("projects", concept["projectId"], owner), "refine", body, concept)


@router.post("/concepts/{concept_id}/model")
def model(concept_id: str, body: Generate, owner=Depends(account)):
    if body.engine not in engines.ENGINES:
        raise HTTPException(422, "Unknown 3D engine")
    if body.modelPrompt and body.modelPrompt.strip() and body.engine != "rodin":
        raise HTTPException(422, "This model accepts images only. Choose Rodin for image + prompt, or refine the concept image first. No Tokens were reserved.")
    concept = record("concepts", concept_id, owner)
    return enqueue(owner, record("projects", concept["projectId"], owner), "model", body, concept)


class ModelPromptRequest(BaseModel):
    prompt: str = Field(default="", max_length=4000)
    plannerModel: str = Field(default=planning.DEFAULT_MODEL, min_length=1, max_length=120)
    plannerEffort: str = Field(default="low", max_length=20)


@router.post("/concepts/{concept_id}/model-prompt")
def improve_model_prompt(concept_id: str, body: ModelPromptRequest, owner=Depends(account)):
    concept = record("concepts", concept_id, owner)
    path = image_path(concept["imageUrl"])
    if not path.is_file(): raise HTTPException(422, "The selected image is unavailable")
    try:
        return planning.improve_model_prompt(owner, body.plannerModel, body.prompt, path, effort=body.plannerEffort)
    except Exception:
        raise HTTPException(503, "Prompt improvement is unavailable with the selected planning model. Your original text is unchanged; no 3D generation was started.") from None


def select_model_views(owner, body, concept):
    concept_id = concept["id"]
    if body.conceptIds is not None:
        if concept_id not in body.conceptIds or len(set(body.conceptIds)) != len(body.conceptIds):
            raise HTTPException(422, "Include the selected primary concept exactly once, with no duplicate views")
        selected = [record("concepts", cid, owner) for cid in [concept_id] + [cid for cid in body.conceptIds if cid != concept_id]]
        if len(selected) > 1:
            view_set = concept.get("viewSetId")
            if not view_set or any(v.get("isOriginal") or v.get("viewSetId") != view_set for v in selected):
                raise HTTPException(422, "Multi-view requires generated siblings from the same validated concept set")
            source_job = record("work", view_set, owner)
            if source_job["status"] not in ("done", "partial") or (source_job.get("validation") or {}).get("usable") is not True:
                raise HTTPException(422, "This concept set has not passed view-consistency validation. Select one view.")
            directions = [v.get("direction") for v in selected]
            if any(d not in ("front", "back", "left", "right") for d in directions) or len(set(directions)) != len(directions):
                raise HTTPException(422, "Multi-view requires distinct, verified camera directions")
            provider = engines.get(body.engine).status().get("provider")
            if body.engine in ("hunyuan3d-2.1", "hunyuan3d-2-white", "hybrid") and set(directions) != {"front", "back", "left"}:
                raise HTTPException(422, "This engine requires exactly front, back and left views")
            if provider != ("api+api" if body.engine == "hybrid" else "api"):
                raise HTTPException(422, "This engine's current provider does not support this multi-view workflow. Select one view.")
        concept = {**concept, "modelViews": selected}
    return concept


def save_job(owner, data):
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        if c.execute("SELECT 1 FROM settlements WHERE job_id=?", (data["id"],)).fetchone():
            return
        c.execute("UPDATE work SET data=? WHERE id=? AND owner=?", (json.dumps(data), data["id"], owner))


def image_path(url):
    return STORAGE / "mobile" / url.rsplit("/", 1)[-1]


def run(owner, data, project, body, concept):
    data = dict(data)
    charged = 0
    # Claim once transactionally before making any billable provider call.
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        row = c.execute("SELECT data FROM work WHERE id=? AND owner=?", (data["id"], owner)).fetchone()
        current = json.loads(row[0]) if row else {}
        if current.get("status") != "queued" or current.get("workerId") != _process_id:
            return
        current.update(status="running", message="Preparing reference")
        c.execute("UPDATE work SET data=? WHERE id=?", (json.dumps(current), data["id"]))
    try:
        data.update(status="running", message="Preparing reference")
        save_job(owner, data)
        if data["kind"] == "model":
            # Image-planning prose often exceeds providers' 1,024-character
            # reconstruction limit. Keep the chosen image authoritative and
            # carry only the original user direction into this separate stage.
            if body.modelPrompt is not None:
                # Explicit blank means image-only guidance. Never reintroduce
                # older project instructions that the user cleared in the sheet.
                reconstruction_prompt = ("Use the selected reference image(s) to create a 3D asset. " + body.modelPrompt.strip()).strip()
            else:
                prefix = ("Reconstruct the asset or scene in the selected image as a 3D asset. "
                          "Preserve its visible geometry, colors and proportions; "
                          "the image is the primary reference. Original user intent: ")
                intent = " ".join((project.get("prompt") or project["name"]).split())
                reconstruction_prompt = prefix + intent[:1024 - len(prefix)]
            selected_views = concept.get("modelViews") or [concept]
            selected_images = [image_path(v["imageUrl"]) for v in selected_views]
            if any(not path.is_file() for path in selected_images):
                raise RuntimeError("The selected reference image is missing. Restore it or choose another image; no fallback asset was used.")
            data.update(stage="reconstructing", selectedConceptId=concept["id"], selectedImageUrl=concept["imageUrl"],
                        selectedConceptIds=[v["id"] for v in selected_views],
                        modelSettings={"engine": body.engine, "quality": body.quality, "effort": body.effort,
                                       "prompt": reconstruction_prompt if body.engine == "rodin" else "",
                                       "promptApplied": body.engine == "rodin"})
            req = GenRequest(prompt=reconstruction_prompt, images=selected_images,
                             directions=[v.get("direction") or "unknown" for v in selected_views],
                             quality=body.quality, effort=body.effort, steps=EFFORT_STEPS.get(body.effort, 50), texture=body.engine != "hunyuan3d-2-white", batch=1)
            backend_id = jobs.submit(body.engine, req, project["name"])
            data["backendJobId"] = backend_id
            save_job(owner, data)
            while True:
                status = jobs.get_job(backend_id)
                if not status:
                    raise RuntimeError("3D job no longer available; no automatic paid retry")
                data.update(progress=status["progress"], message=status["message"])
                save_job(owner, data)
                if status["stage"] == "failed":
                    raise RuntimeError(status.get("error") or "3D generation failed")
                if status["stage"] == "done":
                    data["assets"] = status["assets"]
                    if not data["assets"]:
                        raise RuntimeError("Provider returned no 3D asset")
                    charged = data["cost"]
                    break
                time.sleep(1)
        else:
            reference = record("concepts", body.referenceId, owner) if body.referenceId else concept
            ref = image_path(reference["imageUrl"]) if reference else (image_path(project["imageUrl"]) if project["imageUrl"] else None)
            if ref and not ref.is_file():
                raise RuntimeError("The selected reference image is missing; no fallback asset was used.")
            prompt = body.prompt if body.preserveReference and body.referenceId else body.prompt or project["prompt"]
            count = body.count if data["kind"] == "concepts" else 1
            data.update(totalViews=count, completedViews=0)

            def progress(stage, completed, total, metadata):
                data.update(stage=stage, completedViews=completed, totalViews=total,
                            progress=round(completed / total * 100) if total else 0,
                            message={"analyzing_reference": "Understanding your reference and prompt",
                                     "rendering_canonical": "Creating a concept from your reference" if body.preserveReference else "Creating the shared front reference",
                                     "rendering_views": f"Saved {completed} of {total} candidate views",
                                     "validating_views": "Checking view consistency"}.get(stage, stage))
                if metadata:
                    data.update(coreConcept=metadata.get("core_concept", ""),
                                imageAssessment=metadata.get("image_assessment", ""),
                                conceptPrompt=metadata.get("prompt", ""), title=metadata.get("title", ""),
                                subject=metadata.get("subject", ""), notes=metadata.get("notes", ""))
                save_job(owner, data)

            def save_image(item, metadata):
                nonlocal charged
                im = Image.open(io.BytesIO(item["bytes"])); im.load()
                minimum = 1024 if body.imageModel == image_models.CODEX_MODEL else 2048
                if min(im.size) < minimum:
                    raise RuntimeError(f"Provider returned {im.width}×{im.height}; minimum native {minimum}px requirement not met")
                cid = "mc-" + uuid.uuid4().hex
                dest = STORAGE / "mobile" / (cid + ".png")
                dest.parent.mkdir(parents=True, exist_ok=True)
                im.save(dest)
                result = {"id": cid, "projectId": project["id"], "parentId": concept["id"] if concept else None,
                          "name": metadata.get("title", project["name"]), "label": item["label"],
                          "direction": item.get("direction"), "isOriginal": False, "viewSetId": data["id"],
                          "imageModel": item.get("model", body.imageModel), "imageProvider": data.get("imageProvider"),
                          "plannerModel": body.plannerModel, "plannerEffort": body.plannerEffort,
                          "coreConcept": metadata.get("core_concept", ""),
                          "imageAssessment": metadata.get("image_assessment", ""),
                          "prompt": metadata["prompt"], "imageUrl": "/files/mobile/" + dest.name,
                          "width": im.width, "height": im.height, "createdAt": time.time()}
                with connect() as c:
                    c.execute("INSERT INTO concepts VALUES(?,?,?,?)", (cid, owner, project["id"], json.dumps(result)))
                data["concepts"].append(result)
                charged += data.get("imageTokenCost", 15)
                save_job(owner, data)

            # Exactly the website's shared canonical -> labeled views ->
            # consistency assessment workflow, with persistence callbacks.
            planner_options = {}
            if body.plannerModel != planning.DEFAULT_MODEL:
                from functools import partial
                planner_options = {"prompt_writer": partial(planning.write_prompt, owner, body.plannerModel, effort=body.plannerEffort),
                                   "view_auditor": partial(planning.assess_turnaround, owner, body.plannerModel, effort=body.plannerEffort)}
            if body.imageModel == image_models.CODEX_MODEL:
                from .codex_bridge import generate_image
                planner_options["image_renderer"] = lambda prompt, refs=None, **options: generate_image(owner, prompt, refs or [])
            generation_prompt = prompt if body.preserveReference else prompt + "\nStyle: " + (body.style or project["style"])
            cset = gemini.make_concept_set(generation_prompt, ref,
                                          count=count, mode="reference" if body.preserveReference else "clear" if concept else "angles",
                                          image_size="2K", on_progress=progress, on_image=save_image, image_model=body.imageModel, **planner_options)
            data.update(warnings=cset.get("warnings", []), validation=cset.get("validation"),
                        coreConcept=cset.get("core_concept", ""), imageAssessment=cset.get("image_assessment", ""))
            if len(data["concepts"]) < count:
                data.update(status="partial" if data["concepts"] else "failed", error="Some candidate views could not be saved. Unused Tokens returned.")
        if data["status"] == "running":
            data.update(status="done", stage="ready", progress=100, message="Ready")
    except Exception as exc:
        data.update(status="failed", error=str(exc)[:500], message="Generation failed. Unused Tokens returned.")
    finally:
        with connect() as c:
            c.execute("BEGIN IMMEDIATE")
            _settle(c, owner, data, charged)


@router.get("/jobs")
def list_work(owner=Depends(account)):
    with connect() as c:
        return [json.loads(r[0]) for r in c.execute("SELECT data FROM work WHERE owner=? ORDER BY rowid DESC", (owner,))]


@router.get("/jobs/{job_id}")
def get_work(job_id: str, owner=Depends(account)):
    return record("work", job_id, owner)


@router.get("/assets")
def assets(owner=Depends(account)):
    work = list_work(owner)
    owned = [thumbnails.decorate(a) for j in work for a in j["assets"]]
    owned_ids = {a["id"] for a in owned}
    # Public browsing contains only deliberately curated examples. Assets from
    # a user generation remain in that owner's collection, never the demo feed.
    curated = [{**a, "ownership": "example"} for a in jobs.list_assets()
               if a["id"] not in owned_ids and a.get("galleryExample")
               and a.get("visibility", "public") == "public"]
    return {"owned": owned, "examples": curated}


class Purchase(BaseModel):
    productId: str
    transactionId: str = Field(min_length=8, max_length=150)


@router.post("/development/purchase")
def purchase(body: Purchase, owner=Depends(account)):
    if owner.startswith("firebase:"):
        raise HTTPException(403, "Use an Apple-verified purchase for this account.")
    if IS_PRODUCTION or os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") != "1":
        raise HTTPException(403, "Development purchase endpoint is disabled in production.")
    product_aliases = {
        "craft.starter100": "starter",
        "craft.creator.weekly300": "weekly",
        "$rc_weekly": "craft.creator.weekly.v1",
        "$rc_monthly": "craft.creator.monthly.v1",
        "credits_small": "craft.credits.small.v1",
        "credits_medium": "craft.credits.medium.v1",
        "credits_large": "craft.credits.large.v1",
    }
    body.productId = product_aliases.get(body.productId, body.productId)
    product = next((p for p in PRODUCTS if p["id"] == body.productId), None)
    if not product:
        raise HTTPException(422, f"Unknown product: {body.productId}")
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        c.execute("INSERT OR IGNORE INTO users(id, token, paid, trial) VALUES(?, ?, 0, 45)", (owner, owner))
        prev = c.execute("SELECT * FROM purchases WHERE transaction_id=?", (body.transactionId,)).fetchone()
        if prev and (prev["owner"] != owner or prev["product"] != body.productId):
            raise HTTPException(409, "Transaction belongs to another purchase")
        if not prev:
            c.execute("INSERT INTO purchases VALUES(?,?,?)", (body.transactionId, owner, body.productId))
            c.execute("UPDATE users SET paid=paid+? WHERE id=?", (product["tokens"], owner))
            c.execute("INSERT INTO ledger VALUES(?,?,?,?,?,?)", (uuid.uuid4().hex, owner, "review_purchase", product["tokens"], time.time(), json.dumps({"product": body.productId, "transactionId": body.transactionId, "realPayment": False})))
    return wallet(owner)


def grant_review_credits(owner, initial=False):
    """Synthetic device sessions only; Firebase demo credits require an admin."""
    if owner.startswith("firebase:"):
        return
    if IS_PRODUCTION or os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") != "1":
        return
    with connect() as c:
        c.execute("BEGIN IMMEDIATE")
        row = c.execute("SELECT paid, trial FROM users WHERE id=?", (owner,)).fetchone()
        if not row:
            c.execute("INSERT OR IGNORE INTO users(id,token,paid,trial) VALUES(?,?,?,?)", (owner, owner, 1000, 45))
            row = {"paid": 1000, "trial": 45}
        if initial and c.execute("SELECT 1 FROM ledger WHERE owner=? AND kind='review_credit'", (owner,)).fetchone():
            return
        current = row["paid"]
        amount = max(0, 1000 - current)
        if amount:
            c.execute("UPDATE users SET paid=paid+? WHERE id=?", (amount, owner))
            c.execute("INSERT INTO ledger VALUES(?,?,?,?,?,?)", (uuid.uuid4().hex, owner, "review_credit", amount, time.time(), json.dumps({"realPayment": False, "reason": "Local generation testing; no subscription required"})))


@router.post("/development/credits")
def review_credits(owner=Depends(account)):
    if owner.startswith("firebase:"):
        raise HTTPException(403, "Only an administrator can grant demo credits.")
    if IS_PRODUCTION or os.getenv("CRAFT_ALLOW_LOCAL_REVIEW") != "1":
        raise HTTPException(403, "Development credits refill endpoint is disabled in production.")
    grant_review_credits(owner)
    return wallet(owner)


from .mobile_chat import install as install_chat_routes
install_chat_routes(router)
