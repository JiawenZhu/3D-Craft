"""Review community queues with the operator's existing gcloud IAM identity.

Examples (run from the repository root):
  python scripts/moderate_community.py queue
  python scripts/moderate_community.py decide GAME_ID approved --reason 'Reviewed playable content and metadata; age-appropriate, rights confirmed.'
  python scripts/moderate_community.py decide GAME_ID rejected --reason 'Please remove the offending content before resubmitting.'
  python scripts/moderate_community.py resolve REPORT_ID --reason 'Removed the reported game.'

Do not approve from metadata alone. Open and play the URL, including its menus
and links; review the content rights statement before approving. No notifications
are sent by this tool. Private report text must remain in the moderation workflow.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import firebase_admin
from firebase_admin import credentials, firestore
from google.oauth2.credentials import Credentials
from google.cloud.firestore_v1.base_query import FieldFilter
from server.firebase_community import CloudCommunity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('queue')
    decide = sub.add_parser('decide')
    decide.add_argument('id'); decide.add_argument('decision', choices=['approved', 'rejected'])
    decide.add_argument('--reason', required=True)
    decide.add_argument('--browser-verified', action='store_true', help='Confirm the public game was opened and played in a browser; required when automated access is blocked.')
    resolve = sub.add_parser('resolve'); resolve.add_argument('id'); resolve.add_argument('--reason', required=True)
    restrict = sub.add_parser('posting'); restrict.add_argument('uid')
    restrict.add_argument('action', choices=['block', 'allow']); restrict.add_argument('--reason', required=True)
    args = parser.parse_args()
    actor = subprocess.check_output(['gcloud', 'config', 'get-value', 'account'], text=True).strip()
    if not actor or actor == '(unset)': raise SystemExit('Sign in with an authorized gcloud account first.')
    class CLIIdentity(credentials.Base):
        def get_credential(self):
            return Credentials(subprocess.check_output(['gcloud', 'auth', 'print-access-token'], text=True).strip(),
                               quota_project_id='forma-studio-2026')
    app = firebase_admin.initialize_app(CLIIdentity(), {'projectId': 'forma-studio-2026'})
    service = CloudCommunity(firestore.client(app=app))
    if args.command == 'queue':
        pending = []
        for snap in service.db.collection('communityGames').stream():
            data = snap.to_dict()
            if not data.get('removed') and data.get('moderationStatus', 'pending') == 'pending':
                pending.append(dict(id=snap.id, title=data.get('title'), creator=data.get('creator'),
                    url=data.get('url'), rightsConfirmed=data.get('rightsConfirmed', False),
                    played=data.get('played', False), submittedAt=data.get('createdAt')))
        reports = [dict(id=s.id, **s.to_dict()) for s in service.db.collection('communityReports')
                   .where(filter=FieldFilter('status', '==', 'open')).stream()]
        print(json.dumps(dict(pending=pending, reports=reports), ensure_ascii=False, indent=2))
    elif args.command == 'decide': service.moderate(args.id, args.decision, args.reason, actor, browser_verified=args.browser_verified)
    elif args.command == 'resolve': service.resolve_report(args.id, args.reason, actor)
    elif args.command == 'posting': service.restrict_posting(args.uid, args.action == 'block', args.reason, actor)
    if args.command != 'queue': print('Saved moderation action to Firebase.')


if __name__ == '__main__': main()
