"""Seed existing community games from local SQLite into Firebase Firestore."""
import sqlite3
import json
from server.config import RUNS
from server import community_firestore

def seed():
    db_path = RUNS / "mobile.sqlite3"
    if not db_path.exists():
        print("No mobile.sqlite3 database found.")
        return

    c = sqlite3.connect(db_path)
    c.row_factory = sqlite3.Row
    games = c.execute("SELECT * FROM community_games WHERE removed=0").fetchall()
    print(f"Found {len(games)} active games in SQLite to seed.")

    for g in games:
        game_id = g["id"]
        # Fetch votes
        vote_rows = c.execute("SELECT category, count(*) as n FROM community_votes WHERE game=? GROUP BY category", (game_id,)).fetchall()
        votes = {cat: 0 for cat in ("fun", "animation", "visuals", "creativity")}
        for vr in vote_rows:
            if vr["category"] in votes:
                votes[vr["category"]] = vr["n"]

        game_data = {
            "id": game_id,
            "title": g["title"],
            "creator": g["creator"],
            "description": g["description"],
            "url": g["url"],
            "owner": g["owner"],
            "ownerId": g["owner"].removeprefix("firebase:"),
            "createdAt": g["created"],
            "checkedAt": g["checked"],
            "reachable": bool(g["reachable"]),
            "removed": bool(g["removed"]),
            "votes": votes,
            "likes": sum(votes.values()),
        }

        success = community_firestore.save_game_to_firestore(game_data)
        print(f"Seeded game {game_id} ('{g['title']}') to Firestore: {success}")

if __name__ == "__main__":
    seed()
