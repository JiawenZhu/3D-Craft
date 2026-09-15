"""Publish the five shipped 3D Craft games; preserve existing votes on reruns.

Run after verifying /play and the exported game pack on production Hosting.
Uses the authenticated gcloud account; no credentials are stored in this file.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import time

import firebase_admin
from firebase_admin import credentials, firestore
from google.oauth2.credentials import Credentials
import requests

PROJECT = 'forma-studio-2026'
ORIGIN = 'https://3d-craft.web.app'
GAMES = [
    ('arena', 'Emberfront', 'Drive into an armored arena, outmaneuver rival vehicles, and set off chain reactions.'),
    ('race', 'Coastline Rush', 'Race three rivals around a coastal circuit with ramps, obstacles, and eight checkpoints.'),
    ('ruins', 'The Last Signal', 'Explore ancient ruins, solve a physical puzzle, and recover three lost signals.'),
    ('dragon', 'Emerald Skies', 'Fly with a little emerald dragon, race through sky rings, and protect the valley.'),
    ('survivor', 'Lanternfall', 'Guide a lantern-carrying cat through the old town, gather light, and hold back the shadows.'),
]


class GcloudIdentity(credentials.Base):
    def get_credential(self):
        token = subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip()
        return Credentials(token, quota_project_id=PROJECT)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    if not args.publish:
        parser.error('Use --publish after reviewing the shipped games.')
    pack = Path(__file__).resolve().parents[1] / 'public/games/forma/index.pck'
    digest = hashlib.sha256(pack.read_bytes()).hexdigest()
    for mode, _, _ in GAMES:
        for path in ('/play?game=' + mode, '/games/covers/' + mode + '.jpg'):
            response = requests.get(ORIGIN + path, timeout=30)
            response.raise_for_status()
            if path.endswith('.jpg') and not response.headers.get('Content-Type', '').startswith('image/'):
                raise RuntimeError('Cover is not deployed: ' + path)
    firebase_admin.initialize_app(GcloudIdentity(), {'projectId': PROJECT})
    db = firestore.client()
    now = time.time()
    for mode, title, description in GAMES:
        ident = 'craft-original-' + mode
        ref = db.collection('communityGames').document(ident)
        @firestore.transactional
        def publish(tx):
            prior = ref.get(transaction=tx)
            data = dict(id=ident, ownerId='3d-craft-originals', title=title,
                        creator='3D Craft', description=description,
                        url=ORIGIN + '/play?game=' + mode,
                        coverUrl=ORIGIN + '/games/covers/' + mode + '.jpg',
                        moderationStatus='approved', reachable=True, removed=False,
                        publicationKind='first_party', reviewedPackSHA256=digest,
                        reviewNote='Shipped 3D Craft source, packaged scene smoke checks and production player reviewed.',
                        moderatedAt=now, updatedAt=now)
            if not prior.exists:
                data.update(createdAt=now, votes={c: 0 for c in ('fun', 'animation', 'visuals', 'creativity')})
            tx.set(ref, data, merge=True)
            audit = db.collection('communityModeration').document()
            tx.create(audit, dict(gameId=ident, decision='approved', operator='3d-craft-release',
                                 reason=data['reviewNote'], packSHA256=digest, createdAt=now))
        publish(db.transaction())
        print(title + ': published; existing votes preserved')


if __name__ == '__main__':
    main()
