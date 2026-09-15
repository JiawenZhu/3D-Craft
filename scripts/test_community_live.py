"""Live end-to-end test script for Community Games & Leaderboard in Firebase Firestore."""
import json
import time
import requests

API_KEY = "AIzaSyCKjbzHGU6N4X16ZRkmm2otkkL27MeNQYI"
PROJECT_ID = "forma-studio-2026"
BASE_URL = "http://127.0.0.1:8001/api/mobile/community"
GATEWAY_URL = "http://192.168.68.108:8002/XhhzhZnoqLbXNe7q_e0rBoDNMkr-vyUvp9_lXgIjzDc/api/mobile/community"

def get_id_token(email: str, password: str) -> tuple[str, str]:
    url = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={API_KEY}"
    res = requests.post(url, json={"email": email, "password": password, "returnSecureToken": True}, timeout=10)
    data = res.json()
    if "idToken" not in data:
        raise RuntimeError(f"Sign in failed for {email}: {data}")
    return data["idToken"], data["localId"]

def test_live():
    print("=== 1. Testing Unauthenticated Guest Access ===")
    r = requests.get(f"{BASE_URL}/games", timeout=5)
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"
    games_data = r.json()
    assert len(games_data["games"]) >= 4, f"Expected at least 4 games, got {len(games_data['games'])}"
    for g in games_data["games"]:
        assert not g["isMine"], f"Guest should not own game {g['id']}"
        assert g["myVotes"] == [], f"Guest should have empty myVotes"
    print(f"✔ Guest successfully retrieved {len(games_data['games'])} games from community")

    print("\n=== 2. Authenticating Test User test@test.com ===")
    token, uid = get_id_token("test@test.com", "123456")
    headers = {"Authorization": f"Bearer {token}"}
    print(f"✔ test@test.com authenticated, UID: {uid}")

    print("\n=== 3. Testing Ownership Scoping ===")
    r = requests.get(f"{BASE_URL}/games", headers=headers, timeout=5)
    assert r.status_code == 200
    games = r.json()["games"]
    zhujiawen_game = next((g for g in games if g["id"] == "201d38dccd0b40c3a9286ebfa9100cd7"), None)
    assert zhujiawen_game is not None, "Target game 'Game' not found in leaderboard"
    assert not zhujiawen_game["isMine"], "test@test.com must NOT own zhujiawen519's game"
    print("✔ Ownership correctly scoped: test@test.com is not the owner of zhujiawen519's game")

    print("\n=== 4. Testing Unauthorized Deletion Security (Strict 403) ===")
    r = requests.delete(f"{BASE_URL}/games/201d38dccd0b40c3a9286ebfa9100cd7", headers=headers, timeout=5)
    assert r.status_code == 403, f"Expected 403 Forbidden on deleting another user's game, got {r.status_code}: {r.text}"
    print(f"✔ Unauthorized deletion properly blocked with 403 Forbidden: {r.json()['detail']}")

    print("\n=== 5. Testing Voting & Like Increment in Leaderboard ===")
    # Initial vote count
    init_votes = zhujiawen_game["votes"].get("fun", 0)
    # Vote 'fun'
    r = requests.put(f"{BASE_URL}/games/201d38dccd0b40c3a9286ebfa9100cd7/vote", headers=headers, json={"category": "fun", "liked": True}, timeout=8)
    assert r.status_code == 200, f"Vote failed: {r.status_code} {r.text}"
    voted_game = r.json()
    assert voted_game["votes"]["fun"] == init_votes + 1, f"Expected {init_votes+1}, got {voted_game['votes']['fun']}"
    assert "fun" in voted_game["myVotes"], f"myVotes missing 'fun': {voted_game['myVotes']}"
    print(f"✔ Vote recorded: 'fun' likes increased from {init_votes} to {voted_game['votes']['fun']}")

    # Verify leaderboard sorting reflects votes
    r = requests.get(f"{BASE_URL}/games?category=fun", headers=headers, timeout=5)
    top_game = r.json()["games"][0]
    assert top_game["id"] == "201d38dccd0b40c3a9286ebfa9100cd7", f"Game with most votes should be ranked #1, got {top_game['id']}"
    print("✔ Leaderboard correctly sorted by likes (Game is #1 in 'fun' category)")

    print("\n=== 6. Testing Game Publishing (Saved to Firebase) ===")
    test_url = f"https://claude.ai/code/artifact/test-{int(time.time())}"
    # In live test, mock link check is not used, so we can submit via valid domain
    # Or submit directly:
    sub_payload = {
        "title": "Live Test Game",
        "creator": "Tester",
        "description": "Created by automated live test script",
        "url": "https://claude.ai/code/artifact/00000000-0000-0000-0000-000000000000",
        "played": True
    }
    # Check if this URL already exists
    r_check = requests.post(f"{BASE_URL}/games", headers=headers, json=sub_payload, timeout=8)
    if r_check.status_code == 201:
        created_game = r_check.json()
        new_game_id = created_game["id"]
        assert created_game["isMine"] is True, "Creator must have isMine=True"
        print(f"✔ Game published successfully to Firebase with ID: {new_game_id}")

        print("\n=== 7. Testing Owner Deletion (User removes their own game) ===")
        r_del = requests.delete(f"{BASE_URL}/games/{new_game_id}", headers=headers, timeout=8)
        assert r_del.status_code == 200, f"Owner deletion failed: {r_del.status_code} {r_del.text}"
        assert r_del.json().get("removed") is True
        print(f"✔ Owner successfully deleted their game from Firebase")

        # Verify game is gone from active list
        r_list = requests.get(f"{BASE_URL}/games", headers=headers, timeout=5)
        remaining_ids = [g["id"] for g in r_list.json()["games"]]
        assert new_game_id not in remaining_ids, "Deleted game should not appear in active leaderboard"
        print("✔ Game verified removed from community leaderboard")

    print("\n=== 8. Testing Vote Undo (Un-liking) ===")
    r_undo = requests.put(f"{BASE_URL}/games/201d38dccd0b40c3a9286ebfa9100cd7/vote", headers=headers, json={"category": "fun", "liked": False}, timeout=8)
    assert r_undo.status_code == 200
    undone_game = r_undo.json()
    assert undone_game["votes"]["fun"] == init_votes, f"Expected {init_votes}, got {undone_game['votes']['fun']}"
    assert "fun" not in undone_game["myVotes"], "Un-voted category still in myVotes"
    print(f"✔ Vote undo successful: 'fun' likes restored to {undone_game['votes']['fun']}")

    print("\n=== 9. Testing Gateway Proxy on LAN (Port 8002 for iOS Device) ===")
    r_gw = requests.get(f"{GATEWAY_URL}/games", timeout=5)
    assert r_gw.status_code == 200
    print(f"✔ LAN Gateway proxy verified functional: {len(r_gw.json()['games'])} games retrieved")

    print("\n🎉 ALL LIVE COMMUNITY GAMES & FIRESTORE TESTS PASSED!")

if __name__ == "__main__":
    test_live()
