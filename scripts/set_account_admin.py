"""Run with trusted Firebase Admin credentials: python -m scripts.set_account_admin --email EMAIL."""
import argparse
from firebase_admin import auth
from server.identity import firebase_app

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Assign a verified Firebase account the 3D Craft admin role.')
    parser.add_argument('--email', required=True)
    parser.add_argument('--revoke', action='store_true')
    args = parser.parse_args()
    app = firebase_app()
    user = auth.get_user_by_email(args.email, app=app)
    if user.disabled:
        raise SystemExit('Cannot assign a disabled account.')
    claims = dict(user.custom_claims or {})
    if args.revoke:
        claims.pop('admin', None)
    else:
        claims['admin'] = True
    auth.set_custom_user_claims(user.uid, claims, app=app)
    if args.revoke:
        auth.revoke_refresh_tokens(user.uid, app=app)
    print('Admin role updated. Sign out and back in to refresh access.')
