"""Copy verified-account creations to Firebase, preserving source files.

Default is a read-only inventory. --apply performs the upload with ADC.
This never converts local/sandbox credits into a production wallet.
"""
import argparse
import json
from server import mobile
from server.showcase import items
from server.firebase_studio import FirebaseStudio


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--gcloud-account', help='Authorized CLI account for this one-time migration only')
    args = parser.parse_args()
    with mobile.connect() as c:
        owners = [r[0] for r in c.execute("SELECT id FROM users WHERE id LIKE 'firebase:%'")]
        records = {owner: {table: [dict(r) for r in c.execute(f'SELECT * FROM {table} WHERE owner=?', (owner,))]
                          for table in ('projects', 'concepts', 'work', 'chat_turns')} for owner in owners}
    summary = {'accounts': len(owners), 'records': {table: sum(len(records[o][table]) for o in owners) for table in ('projects','concepts','work','chat_turns')}, 'applied': args.apply}
    print(json.dumps(summary))
    if not args.apply: return
    if args.gcloud_account:
        import subprocess
        import firebase_admin
        from firebase_admin import credentials
        from google.oauth2.credentials import Credentials
        token = subprocess.check_output(['gcloud','auth','print-access-token','--account='+args.gcloud_account], text=True).strip()
        class MigrationCredential(credentials.Base):
            def get_credential(self): return Credentials(token)
        firebase_admin.initialize_app(MigrationCredential(), {'projectId':'forma-studio-2026'}, name='craft-identity')
    cloud = FirebaseStudio()
    mapping = {'projects':'studioProjects', 'concepts':'studioConcepts', 'work':'studioJobs', 'chat_turns':'studioConversations'}
    completed = 0
    for owner in owners:
        for table, collection in mapping.items():
            for row in records[owner][table]:
                data=json.loads(row['data'])
                if table == 'chat_turns': data['projectId']=row['project']
                if table == 'work' and data.get('status') in ('running','queued'):
                    raise RuntimeError('A local job is still active. Finish it before migrating this account.')
                cloud.save_record(owner, collection, row['id'], data)
        for item in items(owner):
            cloud.save_creation(owner, item)
            completed += 1
    print(json.dumps({'creationsUploaded': completed, 'sourceDeleted': False, 'walletsMigrated': False}))

if __name__ == '__main__': main()
