import { useEffect, useState } from 'react';
import { auth, onAuthStateChanged, type User } from '../lib/firebase';
import { GoogleAuthProvider, signInWithRedirect, getRedirectResult, signInWithPopup } from 'firebase/auth';
import { Sparkles } from 'lucide-react';

export function isMobileAuthPath(path: string): boolean {
  return path === '/auth/ios' || path === '/auth/mobile-bridge' || path.startsWith('/auth/ios/');
}

const googleProvider = new GoogleAuthProvider();
googleProvider.addScope('profile');
googleProvider.addScope('email');
googleProvider.setCustomParameters({ prompt: 'select_account' });

export function MobileAuthBridge() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [redirectTarget, setRedirectTarget] = useState('');
  const [redirecting, setRedirecting] = useState(false);

  const forwardToApp = async (u: User) => {
    try {
      setRedirecting(true);
      const token = await u.getIdToken(true);
      const refresh = u.refreshToken;
      const target = `studio.craft.ios://auth?uid=${encodeURIComponent(u.uid)}&email=${encodeURIComponent(u.email || '')}&token=${encodeURIComponent(token)}&refresh=${encodeURIComponent(refresh)}`;
      setRedirectTarget(target);
      window.location.href = target;
    } catch (e: any) {
      setError(e.message || 'Failed to generate sign-in token.');
      setRedirecting(false);
    }
  };

  useEffect(() => {
    // 1. Check if returning from redirect
    getRedirectResult(auth)
      .then(async (result) => {
        if (result && result.user && !result.user.isAnonymous) {
          setUser(result.user);
          await forwardToApp(result.user);
        }
      })
      .catch((err: any) => {
        console.error('Redirect result error:', err);
        setError(err.message || 'Sign in was cancelled or failed.');
        setLoading(false);
      });

    // 2. Listen for auth state
    const unsubscribe = onAuthStateChanged(auth, async (u) => {
      setLoading(false);
      if (u && !u.isAnonymous) {
        setUser(u);
        await forwardToApp(u);
      }
    });

    return () => unsubscribe();
  }, []);

  const handleGoogleLogin = async () => {
    try {
      setLoading(true);
      setError('');
      // In mobile ASWebAuthenticationSession, use redirect
      try {
        await signInWithRedirect(auth, googleProvider);
      } catch (redirectErr) {
        // Fallback to popup if redirect is unsupported
        const res = await signInWithPopup(auth, googleProvider);
        if (res && res.user) {
          await forwardToApp(res.user);
        }
      }
    } catch (e: any) {
      setError(e.message || 'Sign in was cancelled or failed.');
      setLoading(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      backgroundColor: '#0a0a0c',
      color: '#fff',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
      padding: '24px'
    }}>
      <div style={{
        maxWidth: '400px',
        width: '100%',
        background: '#141418',
        borderRadius: '20px',
        border: '1px solid rgba(255, 255, 255, 0.1)',
        padding: '32px',
        textAlign: 'center'
      }}>
        <div style={{
          width: '56px',
          height: '56px',
          background: 'linear-gradient(135deg, #10b981, #059669)',
          borderRadius: '16px',
          margin: '0 auto 20px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          boxShadow: '0 8px 24px rgba(16, 185, 129, 0.3)'
        }}>
          <Sparkles size={28} color="#fff" />
        </div>

        <h1 style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>
          3D Craft
        </h1>
        <p style={{ color: '#9ca3af', fontSize: '14px', marginBottom: '28px', lineHeight: '1.5' }}>
          {redirecting ? 'Connecting to your 3D Craft iOS app…' : 'Sign in to connect your creations with your iPhone.'}
        </p>

        {error && (
          <div style={{
            background: 'rgba(239, 68, 68, 0.1)',
            border: '1px solid rgba(239, 68, 68, 0.2)',
            color: '#f87171',
            borderRadius: '12px',
            padding: '12px',
            fontSize: '13px',
            marginBottom: '20px'
          }}>
            {error}
          </div>
        )}

        {redirecting ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', alignItems: 'center' }}>
            <div style={{ color: '#10b981', fontSize: '15px', fontWeight: '600' }}>
              ✓ Returning to app…
            </div>
            {redirectTarget && (
              <a
                href={redirectTarget}
                style={{
                  display: 'inline-block',
                  padding: '12px 24px',
                  backgroundColor: '#10b981',
                  color: '#fff',
                  borderRadius: '12px',
                  textDecoration: 'none',
                  fontWeight: '600',
                  fontSize: '15px',
                  marginTop: '8px'
                }}
              >
                Open 3D Craft
              </a>
            )}
          </div>
        ) : (
          <button
            onClick={handleGoogleLogin}
            disabled={loading}
            style={{
              width: '100%',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: '12px',
              padding: '14px 20px',
              background: '#fff',
              color: '#000',
              border: 'none',
              borderRadius: '12px',
              fontSize: '15px',
              fontWeight: '600',
              cursor: loading ? 'not-allowed' : 'pointer',
              opacity: loading ? 0.7 : 1,
              transition: 'transform 0.1s'
            }}
          >
            <svg width="18" height="18" viewBox="0 0 24 24">
              <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
              <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
              <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z"/>
              <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/>
            </svg>
            Continue with Google
          </button>
        )}
      </div>
    </div>
  );
}
