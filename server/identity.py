import os
import threading
from fastapi import Depends, Header, HTTPException

_lock = threading.Lock()

def firebase_app():
    if 'GOOGLE_APPLICATION_CREDENTIALS' in os.environ and not os.path.exists(os.environ['GOOGLE_APPLICATION_CREDENTIALS']):
        del os.environ['GOOGLE_APPLICATION_CREDENTIALS']
    import firebase_admin
    from firebase_admin import auth
    with _lock:
        try:
            app = firebase_admin.get_app('craft-identity')
        except ValueError:
            app = firebase_admin.initialize_app(options={'projectId': 'forma-studio-2026'}, name='craft-identity')
    return app

def verify_token(token, check_revoked=False):
    from firebase_admin import auth
    return auth.verify_id_token(token, app=firebase_app(), check_revoked=check_revoked)

def require_claims(authorization: str = Header(default='')):
    if authorization.startswith('Bearer craft_live_'):
        raise HTTPException(403, 'API keys are only accepted on /api/v1 pipeline endpoints. This endpoint requires account sign-in.')
    if not authorization.startswith('Bearer ') or not authorization[7:]:
        raise HTTPException(401, 'Sign in to your 3D Craft account to continue.')
    try:
        claims = verify_token(authorization[7:])
    except ImportError:
        raise HTTPException(503, 'Account verification is not configured.') from None
    except Exception:
        raise HTTPException(401, 'Your sign-in could not be verified. Please sign in again.') from None
    uid = claims.get('uid') or claims.get('sub')
    provider = claims.get('firebase', {}).get('sign_in_provider')
    if not uid or provider in (None, 'anonymous'):
        raise HTTPException(401, 'Create an account or sign in. Guest sessions cannot generate assets.')
    return claims

def require_account(claims=Depends(require_claims)):
    # Direct middleware callers pass their Authorization header.
    if isinstance(claims, str):
        claims = require_claims(claims)
    uid = claims.get("uid") or claims.get("sub")
    from . import mobile
    owner = 'firebase:' + uid
    with mobile.connect() as c:
        # Real accounts always begin empty, including on the acceptance server.
        paid, trial = 0, 0
        c.execute('INSERT OR IGNORE INTO users(id,token,paid,trial) VALUES(?,?,?,?)', (owner, 'firebase:' + uid, paid, trial))
    return owner

def require_admin(claims=Depends(require_claims)):
    if claims.get("admin") is not True:
        raise HTTPException(403, "Only an administrator can grant credits.")
    return "firebase:" + (claims.get("uid") or claims["sub"])

def require_paid(owner):
    from . import mobile
    with mobile.connect() as c:
        row = c.execute('SELECT paid FROM users WHERE id=?', (owner,)).fetchone()
        purchase = c.execute("SELECT 1 FROM ledger WHERE owner=? AND kind IN ('verified_purchase','admin_credit') LIMIT 1", (owner,)).fetchone()
    if not row or row['paid'] <= 0 or not purchase:
        raise HTTPException(402, 'You need purchased or admin-granted credits to create.')
    return owner
