"""Publish the three creator-authorized games reviewed on September 15, 2026.

These are explicit operator-curated entries, not automatic approval of future
user submissions. Existing votes and creation dates are retained on reruns.
"""
import argparse
from pathlib import Path
import sys
import time
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import firebase_admin
from firebase_admin import firestore
from scripts.publish_first_party_games import GcloudIdentity, PROJECT
from server.game_links import verify_game_url

GAMES = [
    ('example-moonrun', 'Moonrun · Fox of the Hollow Road',
     'https://claude.ai/artifact/PvCrAGzNSy4xSVVTTwPspj',
     'Leap across an enchanted road, throw foxfire, and collect moonlight in a two-level fox adventure.'),
    ('example-moss-garden', 'Moss Robot · Sunseed Garden',
     'https://moss-robot-sunseed-garden.evan001007.chatgpt.site/',
     'Guide a little robot through a floating garden. Gather six sun seeds, hop over beetles, and bring the garden to life.'),
    ('example-dragon-flight', 'Emberwing · Dragon Flight',
     'https://emberwing-dragon-flight.evan001007.chatgpt.site/',
     'Steer a dragon through sky islands, fly through rings, and breathe fire. Best played with your phone sideways.'),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    checked = [(ident, title, verify_game_url(url)['url'], description)
               for ident, title, url, description in GAMES]
    if not args.publish:
        for _, title, _, _ in checked: print(title + ': public link verified; dry run')
        return
    firebase_admin.initialize_app(GcloudIdentity(), {'projectId': PROJECT})
    db = firestore.client()
    now = time.time()
    for ident, title, url, description in checked:
        ref = db.collection('communityGames').document(ident)
        @firestore.transactional
        def publish(tx):
            previous = ref.get(transaction=tx).to_dict() or {}
            if previous.get('removed'):
                raise RuntimeError('Refusing to republish a removed entry: ' + ident)
            data = dict(id=ident, ownerId='3d-craft-originals', creator='Jiawen Zhu',
                        title=title, description=description, url=url,
                        reachable=True, removed=False, moderationStatus='approved',
                        publicationKind='creator_authorized', updatedAt=now,
                        rightsConfirmed=True, rightsConfirmedAt=now,
                        authorizationNote='Creator supplied these links and explicitly requested community publication on September 15, 2026.',
                        moderatedAt=now, reviewNote='Public pages and game start/controls reviewed in the browser. Full phone gameplay performance is not certified.')
            if not previous:
                data.update(createdAt=now, votes={c: 0 for c in ('fun', 'animation', 'visuals', 'creativity')})
            tx.set(ref, data, merge=True)
            tx.create(db.collection('communityModeration').document(),
                      dict(gameId=ident, decision='approved', operator='3d-craft-release',
                           reason=data['reviewNote'], authorization=data['authorizationNote'], createdAt=now))
        publish(db.transaction())
        print(title + ': published; existing votes preserved')


if __name__ == '__main__': main()
