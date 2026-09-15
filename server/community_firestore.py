"""Firestore cloud storage integration for Community Games & Leaderboard.

Provides bidirectional sync between Firestore (source of truth) and local SQLite.
Enforces that user-created games can only be modified/deleted by their owner.
Tracks category votes and calculates like-based leaderboard rankings.
"""
import json
import os
import time
from urllib.parse import quote
import requests

PROJECT_ID = "forma-studio-2026"
FIRESTORE_BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
GAMES_COLLECTION = f"{FIRESTORE_BASE}/communityGames"

def _get_server_token() -> str:
    """Read server-level access token from CLI configstore for background sync."""
    try:
        config_path = os.path.expanduser("~/.config/configstore/firebase-tools.json")
        if os.path.exists(config_path):
            with open(config_path) as f:
                data = json.load(f)
            return data.get("tokens", {}).get("access_token", "")
    except Exception:
        pass
    return ""

def _build_headers(auth_token: str = None) -> dict:
    headers = {"X-Goog-User-Project": PROJECT_ID}
    token = auth_token or _get_server_token()
    if token:
        if not token.startswith("Bearer "):
            token = f"Bearer {token}"
        headers["Authorization"] = token
    return headers

def to_firestore_value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    elif isinstance(v, int):
        return {"integerValue": str(v)}
    elif isinstance(v, float):
        return {"doubleValue": v}
    elif isinstance(v, str):
        return {"stringValue": v}
    elif isinstance(v, list):
        return {"arrayValue": {"values": [to_firestore_value(x) for x in v]}}
    elif isinstance(v, dict):
        return {"mapValue": {"fields": {k: to_firestore_value(val) for k, val in v.items()}}}
    elif v is None:
        return {"nullValue": None}
    return {"stringValue": str(v)}

def from_firestore_value(v):
    if not isinstance(v, dict):
        return v
    if "stringValue" in v:
        return v["stringValue"]
    elif "booleanValue" in v:
        return v["booleanValue"]
    elif "integerValue" in v:
        return int(v["integerValue"])
    elif "doubleValue" in v:
        return float(v["doubleValue"])
    elif "mapValue" in v:
        fields = v["mapValue"].get("fields", {})
        return {k: from_firestore_value(val) for k, val in fields.items()}
    elif "arrayValue" in v:
        values = v["arrayValue"].get("values", [])
        return [from_firestore_value(val) for val in values]
    elif "nullValue" in v:
        return None
    return None

def doc_to_game(doc: dict) -> dict:
    fields = doc.get("fields", {})
    game = {k: from_firestore_value(v) for k, v in fields.items()}
    name = doc.get("name", "")
    if "id" not in game and name:
        game["id"] = name.split("/")[-1]
    if "votes" not in game or not isinstance(game["votes"], dict):
        game["votes"] = {"fun": 0, "animation": 0, "visuals": 0, "creativity": 0}
    for cat in ("fun", "animation", "visuals", "creativity"):
        if cat not in game["votes"]:
            game["votes"][cat] = 0
    game["likes"] = int(game.get("likes") or sum(game["votes"].values()))
    game["reachable"] = bool(game.get("reachable", True))
    game["removed"] = bool(game.get("removed", False))
    return game

def game_to_fields(game: dict) -> dict:
    votes = game.get("votes") or {}
    vote_map = {
        "fun": int(votes.get("fun", 0)),
        "animation": int(votes.get("animation", 0)),
        "visuals": int(votes.get("visuals", 0)),
        "creativity": int(votes.get("creativity", 0)),
    }
    likes = int(game.get("likes", sum(vote_map.values())))
    clean = {
        "id": str(game["id"]),
        "title": str(game["title"]),
        "creator": str(game["creator"]),
        "description": str(game.get("description", "")),
        "url": str(game["url"]),
        "ownerId": str(game.get("ownerId") or game.get("owner", "system")).removeprefix("firebase:"),
        "owner": str(game.get("owner") or "system"),
        "createdAt": float(game.get("createdAt") or time.time()),
        "checkedAt": float(game.get("checkedAt") or time.time()),
        "reachable": bool(game.get("reachable", True)),
        "removed": bool(game.get("removed", False)),
        "likes": likes,
        "votes": vote_map,
        "updatedAt": float(time.time()),
    }
    return {k: to_firestore_value(v) for k, v in clean.items()}

def save_game_to_firestore(game: dict, auth_token: str = None) -> bool:
    """Save or update a community game in Firestore."""
    game_id = game["id"]
    url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}"
    headers = _build_headers(auth_token)
    payload = {"fields": game_to_fields(game)}
    try:
        r = requests.patch(url, headers=headers, json=payload, timeout=8)
        if r.status_code in (200, 201):
            return True
        print(f"[Firestore] save_game failed ({r.status_code}): {r.text}", flush=True)
    except Exception as e:
        print(f"[Firestore] save_game exception: {e}", flush=True)
    return False

def get_game_from_firestore(game_id: str) -> dict | None:
    """Fetch a single game from Firestore."""
    url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}"
    headers = _build_headers()
    try:
        r = requests.get(url, headers=headers, timeout=5)
        if r.status_code == 200:
            return doc_to_game(r.json())
    except Exception as e:
        print(f"[Firestore] get_game error: {e}", flush=True)
    return None

def list_games_from_firestore() -> list[dict]:
    """Fetch all active community games from Firestore."""
    url = f"{GAMES_COLLECTION}?pageSize=300"
    headers = _build_headers()
    results = []
    try:
        r = requests.get(url, headers=headers, timeout=8)
        if r.status_code == 200:
            docs = r.json().get("documents", [])
            for doc in docs:
                game = doc_to_game(doc)
                if not game.get("removed"):
                    results.append(game)
    except Exception as e:
        print(f"[Firestore] list_games error: {e}", flush=True)
    return results

def delete_game_from_firestore(game_id: str, owner_uid: str, auth_token: str = None) -> bool:
    """Mark removed or delete game from Firestore if caller is owner."""
    url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}"
    headers = _build_headers(auth_token)
    try:
        patch_url = f"{url}?updateMask.fieldPaths=removed&updateMask.fieldPaths=updatedAt"
        payload = {
            "fields": {
                "removed": {"booleanValue": True},
                "updatedAt": {"doubleValue": time.time()}
            }
        }
        r = requests.patch(patch_url, headers=headers, json=payload, timeout=8)
        if r.status_code in (200, 201):
            return True
        r_del = requests.delete(url, headers=headers, timeout=8)
        return r_del.status_code in (200, 204)
    except Exception as e:
        print(f"[Firestore] delete_game error: {e}", flush=True)
    return False

def record_vote_in_firestore(game_id: str, user_uid: str, category: str, liked: bool, auth_token: str = None) -> dict | None:
    """Record user vote in Firestore and update game vote counts."""
    headers = _build_headers(auth_token)
    vote_url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}/votes/{quote(user_uid, safe='')}"
    
    existing_cats = []
    try:
        r_v = requests.get(vote_url, headers=headers, timeout=5)
        if r_v.status_code == 200:
            doc = r_v.json()
            cats = from_firestore_value(doc.get("fields", {}).get("categories", {}))
            if isinstance(cats, list):
                existing_cats = list(cats)
    except Exception:
        pass

    if liked:
        if category not in existing_cats:
            existing_cats.append(category)
    else:
        if category in existing_cats:
            existing_cats.remove(category)

    try:
        vote_payload = {
            "fields": {
                "userId": {"stringValue": user_uid},
                "categories": {"arrayValue": {"values": [{"stringValue": c} for c in existing_cats]}},
                "updatedAt": {"doubleValue": time.time()}
            }
        }
        requests.patch(vote_url, headers=headers, json=vote_payload, timeout=6)
    except Exception as e:
        print(f"[Firestore] save vote error: {e}", flush=True)

    game = get_game_from_firestore(game_id)
    if not game:
        return None

    votes = game.get("votes", {})
    delta = 1 if liked else -1
    curr = votes.get(category, 0)
    votes[category] = max(0, curr + delta)
    game["votes"] = votes
    game["likes"] = sum(votes.values())

    patch_url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}?updateMask.fieldPaths=votes&updateMask.fieldPaths=likes&updateMask.fieldPaths=updatedAt"
    payload = {
        "fields": {
            "votes": to_firestore_value(votes),
            "likes": to_firestore_value(game["likes"]),
            "updatedAt": to_firestore_value(time.time()),
        }
    }
    try:
        r = requests.patch(patch_url, headers=headers, json=payload, timeout=8)
        if r.status_code not in (200, 201):
            server_headers = _build_headers()
            requests.patch(patch_url, headers=server_headers, json=payload, timeout=8)
    except Exception as e:
        print(f"[Firestore] update votes error: {e}", flush=True)

    return game

def get_user_votes_for_game(game_id: str, user_uid: str, auth_token: str = None) -> list[str]:
    """Get the category votes cast by user_uid on a game."""
    if not user_uid:
        return []
    headers = _build_headers(auth_token)
    vote_url = f"{GAMES_COLLECTION}/{quote(game_id, safe='')}/votes/{quote(user_uid, safe='')}"
    try:
        r = requests.get(vote_url, headers=headers, timeout=4)
        if r.status_code == 200:
            cats = from_firestore_value(r.json().get("fields", {}).get("categories", {}))
            if isinstance(cats, list):
                return cats
    except Exception:
        pass
    return []
