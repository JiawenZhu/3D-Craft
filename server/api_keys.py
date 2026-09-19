"""User-authorized 3D Craft API keys for third-party agents and applications.

High-entropy bearer keys (recognizable prefix `craft_live_`) linked to a
Firebase user UID. Only SHA-256 cryptographic hashes and safe metadata are
stored in Firestore. Plaintext secrets are returned strictly once at generation
and never logged, persisted in Firebase, or written to disk.

Concurrency and rate limits are atomic and distributed (Cloud Run safe) via
Firestore transactions.
"""
from __future__ import annotations

import hashlib
import secrets
import time
from typing import Any, Dict, List, Optional, Tuple
from fastapi import HTTPException
from firebase_admin import auth, firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from .account_deletion import request_ref
from .identity import firebase_app

KEY_PREFIX = "craft_live_"
MAX_ACTIVE_KEYS_PER_USER = 5
DEFAULT_SCOPES = ["*"]
ALLOWED_SCOPES = {
    "*",
    "wallet:read",
    "prompt:write",
    "concepts:write",
    "models:write",
    "assets:read",
    "assets:delete",
}
# Deleting is permanent, so full access ("*") never implies it; a key must be
# granted assets:delete explicitly.
EXPLICIT_SCOPES = {"assets:delete"}
RATE_LIMIT_PER_MINUTE = 60


def generate_key_pair(
    name: str = "API Key",
    scopes: Optional[List[str]] = None,
    expires_in_days: Optional[int] = None,
) -> Tuple[str, str, str, Dict[str, Any]]:
    """Generates a high-entropy bearer token, its SHA-256 hash, key ID, and initial metadata."""
    entropy = secrets.token_urlsafe(32)
    raw_key = f"{KEY_PREFIX}{entropy}"
    key_hash = hashlib.sha256(raw_key.encode("utf-8")).hexdigest()
    key_id = "key_" + hashlib.sha256(entropy.encode("utf-8")).hexdigest()[:16]
    prefix_display = f"{KEY_PREFIX}{entropy[:6]}..."

    effective_scopes = scopes if scopes is not None else list(DEFAULT_SCOPES)
    for s in effective_scopes:
        if s not in ALLOWED_SCOPES:
            raise HTTPException(400, f"Invalid scope '{s}'. Allowed: {sorted(list(ALLOWED_SCOPES))}")

    now = time.time()
    expires_at = (now + expires_in_days * 86400) if expires_in_days and expires_in_days > 0 else None

    clean_name = name.strip()
    if not clean_name or len(clean_name) > 64:
        raise HTTPException(400, "Key name must be between 1 and 64 characters.")

    metadata = {
        "id": key_id,
        "name": clean_name,
        "prefix": prefix_display,
        "scopes": effective_scopes,
        "createdAt": now,
        "expiresAt": expires_at,
        "revoked": False,
        "revokedAt": None,
        "lastUsedAt": None,
    }
    return raw_key, key_hash, key_id, metadata


def create_api_key(
    db: firestore.Client,
    uid: str,
    name: str = "API Key",
    scopes: Optional[List[str]] = None,
    expires_in_days: Optional[int] = None,
) -> Dict[str, Any]:
    """Creates a new API key for the owner with atomic concurrency protection on active keys.

    Plaintext key is returned only in this response and never stored.
    """
    if not uid or "/" in uid:
        raise HTTPException(400, "Invalid account ID.")

    # Fail closed if account is scheduled for deletion
    try:
        if request_ref(db, uid).get().exists:
            raise HTTPException(403, "This account is scheduled for deletion.")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, "Security verification is temporarily unavailable.") from exc

    raw_key, key_hash, key_id, meta = generate_key_pair(name, scopes, expires_in_days)
    doc_data = dict(meta)
    doc_data["ownerId"] = uid
    doc_data["keyHash"] = key_hash

    # Atomic Firestore transaction for bounded active keys limit
    index_ref = (
        db.collection("users")
        .document(uid)
        .collection("private")
        .document("apiKeysIndex")
    )
    key_ref = db.collection("apiKeys").document(key_hash)

    @firestore.transactional
    def create_tx(tx):
        now = time.time()
        # Verify account active within transaction
        del_snap = request_ref(db, uid).get(transaction=tx)
        if del_snap.exists:
            raise HTTPException(403, "This account is scheduled for deletion.")

        index_snap = index_ref.get(transaction=tx)
        index_data = index_snap.to_dict() if index_snap.exists else {}
        active_keys = dict(index_data.get("activeKeys", {}))

        # Prune expired keys from active accounting
        current_active = {}
        for kh, km in active_keys.items():
            if km.get("revoked"):
                continue
            exp = km.get("expiresAt")
            if exp is not None and exp <= now:
                continue
            current_active[kh] = km

        if len(current_active) >= MAX_ACTIVE_KEYS_PER_USER:
            raise HTTPException(
                400,
                f"Active API key limit reached ({MAX_ACTIVE_KEYS_PER_USER}). "
                "Please revoke an unused key before creating a new one.",
            )

        current_active[key_hash] = {
            "id": key_id,
            "name": meta["name"],
            "prefix": meta["prefix"],
            "createdAt": meta["createdAt"],
            "expiresAt": meta["expiresAt"],
        }
        tx.set(index_ref, {"activeKeys": current_active, "updatedAt": now})
        tx.set(key_ref, doc_data)

    try:
        create_tx(db.transaction())
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, "Failed to register API key due to database error.") from exc

    return {
        "key": raw_key,
        "id": key_id,
        "name": meta["name"],
        "prefix": meta["prefix"],
        "scopes": meta["scopes"],
        "createdAt": meta["createdAt"],
        "expiresAt": meta["expiresAt"],
        "warning": (
            "Store this key securely now. You will not be able to view it again. "
            "Requests authenticated with this key use your account Tokens."
        ),
    }


def list_api_keys(db: firestore.Client, uid: str) -> List[Dict[str, Any]]:
    """Returns safe metadata for all API keys owned by uid. Never includes key hashes or plaintext."""
    if not uid or "/" in uid:
        raise HTTPException(400, "Invalid account ID.")

    try:
        docs = (
            db.collection("apiKeys")
            .where(filter=FieldFilter("ownerId", "==", uid))
            .stream()
        )
        results = []
        for doc in docs:
            d = doc.to_dict() or {}
            results.append({
                "id": d.get("id"),
                "name": d.get("name", "API Key"),
                "prefix": d.get("prefix", f"{KEY_PREFIX}..."),
                "scopes": d.get("scopes", ["*"]),
                "createdAt": d.get("createdAt", 0),
                "expiresAt": d.get("expiresAt"),
                "revoked": bool(d.get("revoked", False)),
                "revokedAt": d.get("revokedAt"),
                "lastUsedAt": d.get("lastUsedAt"),
            })
        return sorted(results, key=lambda k: k.get("createdAt", 0), reverse=True)
    except Exception as exc:
        raise HTTPException(503, "Failed to load API keys.") from exc


def revoke_api_key(db: firestore.Client, uid: str, key_id: str) -> Dict[str, Any]:
    """Revokes an API key owned by uid with atomic update to both key record and active index."""
    if not uid or not key_id:
        raise HTTPException(400, "Invalid account ID or key ID.")

    # Find the matching key document
    try:
        docs = list(
            db.collection("apiKeys")
            .where(filter=FieldFilter("ownerId", "==", uid))
            .where(filter=FieldFilter("id", "==", key_id))
            .stream()
        )
    except Exception as exc:
        raise HTTPException(503, "Database service is temporarily unavailable.") from exc

    if not docs:
        raise HTTPException(404, "API key not found in your account.")

    target_doc = docs[0]
    key_hash = target_doc.id

    index_ref = (
        db.collection("users")
        .document(uid)
        .collection("private")
        .document("apiKeysIndex")
    )

    @firestore.transactional
    def revoke_tx(tx):
        now = time.time()
        # READ PHASE: all Firestore reads must precede any writes
        index_snap = index_ref.get(transaction=tx)
        _ = target_doc.reference.get(transaction=tx)

        # WRITE PHASE: execute writes
        tx.update(target_doc.reference, {"revoked": True, "revokedAt": now})
        if index_snap.exists:
            active_keys = dict(index_snap.to_dict().get("activeKeys", {}))
            if key_hash in active_keys:
                active_keys.pop(key_hash, None)
                tx.set(index_ref, {"activeKeys": active_keys, "updatedAt": now})

    try:
        revoke_tx(db.transaction())
        return {"status": "revoked", "id": key_id}
    except Exception as exc:
        raise HTTPException(503, "Failed to revoke API key.") from exc


def delete_keys_for_user(db: firestore.Client, uid: str) -> int:
    """Deletes all keys and index for a user during account deletion."""
    if not uid:
        return 0
    try:
        docs = (
            db.collection("apiKeys")
            .where(filter=FieldFilter("ownerId", "==", uid))
            .stream()
        )
        count = 0
        for doc in docs:
            # Also cleanup rate quota record
            try:
                db.collection("rateQuotas").document(doc.id).delete()
            except Exception:
                pass
            doc.reference.delete()
            count += 1

        # Delete user apiKeysIndex
        try:
            db.collection("users").document(uid).collection("private").document("apiKeysIndex").delete()
        except Exception:
            pass

        return count
    except Exception:
        return 0


def check_distributed_rate_quota(
    db: firestore.Client, key_hash: str, limit: int = RATE_LIMIT_PER_MINUTE
) -> None:
    """Distributed Cloud Run safe rate quota enforcement using Firestore transactions."""
    now = time.time()
    current_minute = int(now // 60)
    quota_ref = db.collection("rateQuotas").document(key_hash)

    @firestore.transactional
    def update_quota_tx(tx):
        snap = quota_ref.get(transaction=tx)
        data = snap.to_dict() if snap.exists else {}
        window = data.get("window", 0)
        count = data.get("count", 0) if window == current_minute else 0
        if count >= limit:
            raise HTTPException(
                429,
                f"Rate limit exceeded. Maximum {limit} requests per minute.",
                headers={"Retry-After": "60"},
            )
        tx.set(
            quota_ref,
            {"window": current_minute, "count": count + 1, "lastRequestAt": now},
            merge=True,
        )

    try:
        update_quota_tx(db.transaction())
    except HTTPException:
        raise
    except Exception as exc:
        # Fail closed on quota service failure
        raise HTTPException(503, "Rate quota service is temporarily unavailable.") from exc


def verify_api_key(
    db: firestore.Client,
    raw_bearer: str,
    required_scope: Optional[str] = None,
) -> Tuple[str, Dict[str, Any]]:
    """Verifies a bearer API key against Firestore and Firebase Auth.

    Returns:
        (uid, key_metadata) where uid is the Firebase UID of the owner.
    Fails closed on any database, validation, deletion, or authentication error.
    """
    token = raw_bearer.strip()
    if not token.startswith(KEY_PREFIX) or len(token) < 20:
        raise HTTPException(401, "Invalid API key format.")

    key_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()

    try:
        snap = db.collection("apiKeys").document(key_hash).get()
    except Exception as exc:
        raise HTTPException(503, "Authentication database is unavailable.") from exc

    if not snap.exists:
        raise HTTPException(401, "Invalid or unrecognized API key.")

    data = snap.to_dict() or {}
    owner_uid = data.get("ownerId")
    if not owner_uid:
        raise HTTPException(401, "Invalid API key owner.")

    if data.get("revoked", False):
        raise HTTPException(401, "This API key has been revoked.")

    now = time.time()
    expires_at = data.get("expiresAt")
    if expires_at is not None and now > expires_at:
        raise HTTPException(401, "This API key has expired.")

    # Validate scopes
    scopes = set(data.get("scopes", []))
    covered = required_scope in scopes or ("*" in scopes and required_scope not in EXPLICIT_SCOPES)
    if required_scope and not covered:
        raise HTTPException(403, f"API key does not possess required scope '{required_scope}'.")

    # Distributed Cloud Run safe rate quota enforcement
    check_distributed_rate_quota(db, key_hash)

    # Validate owner account deletion status (fail closed)
    try:
        if request_ref(db, owner_uid).get().exists:
            raise HTTPException(
                403,
                "Account associated with this API key has been deleted or requested deletion.",
            )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(503, "Security verification is unavailable.") from exc

    # Validate owner Firebase Auth status (fail closed if disabled or deleted)
    try:
        user_record = auth.get_user(owner_uid, app=firebase_app())
        if user_record.disabled:
            raise HTTPException(401, "The account owning this key has been disabled.")
    except auth.UserNotFoundError:
        raise HTTPException(401, "The account owning this key no longer exists.") from None
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Account authentication check failed.") from None

    # Update lastUsedAt best-effort
    try:
        snap.reference.update({"lastUsedAt": now})
    except Exception:
        pass

    return owner_uid, data
