import React, { useEffect, useState } from 'react';
import {
  X, Mail, ArrowLeft, LogOut, CheckCircle, AlertCircle,
  Layers, Sparkles
} from 'lucide-react';
import { auth, onAuthStateChanged, type User } from '../../lib/firebase';
import { loginWithGoogle, loginWithEmail, registerWithEmail, logoutUser } from '../../lib/firebase';

interface AuthModalProps {
  open: boolean;
  onClose: () => void;
}

export const AuthModal: React.FC<AuthModalProps> = ({ open, onClose }) => {
  const [user, setUser] = useState<User | null>(auth.currentUser);
  useEffect(() => onAuthStateChanged(auth, setUser), []);
  const isGuest = !user || user.isAnonymous;
  const [viewMode, setViewMode] = useState<'options' | 'email'>('options');
  const [tab, setTab] = useState<'signin' | 'signup'>('signin');
  const [agreed, setAgreed] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  if (!open) return null;

  const handleGoogleSignIn = async () => {
    setError(null);
    setSuccess(null);
    if (!agreed) {
      setError('Please agree to the Terms & Conditions and Privacy Policy to continue.');
      return;
    }

    setGoogleLoading(true);
    try {
      await loginWithGoogle();
      setSuccess('Signed in with Google successfully.');
      setTimeout(() => {
        onClose();
      }, 600);
    } catch (err: any) {
      const msg = err?.message || 'Google sign-in failed.';
      if (msg.includes('auth/unauthorized-domain')) {
        setError('Sign-in is not configured for this website address. Please use https://3d-craft.web.app or contact support.');
      } else if (msg.includes('auth/popup-closed-by-user')) {
        setError('Sign-in cancelled by user.');
      } else if (msg.includes('auth/cancelled-popup-request')) {
        // Ignored
      } else {
        setError(msg);
      }
    } finally {
      setGoogleLoading(false);
    }
  };

  const handleEmailSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setSuccess(null);
    if (!agreed) {
      setError('Please agree to the Terms & Conditions and Privacy Policy to continue.');
      return;
    }
    if (!email.trim() || !password.trim()) {
      setError('Please provide both email and password.');
      return;
    }

    setLoading(true);
    try {
      if (tab === 'signin') {
        await loginWithEmail(email.trim(), password);
        setSuccess('Signed in successfully.');
        setTimeout(() => {
          onClose();
        }, 600);
      } else {
        await registerWithEmail(email.trim(), password);
        setSuccess('Account created and logged in.');
        setTimeout(() => {
          onClose();
        }, 600);
      }
    } catch (err: any) {
      const msg = err?.message || 'Authentication failed.';
      if (msg.includes('auth/invalid-credential') || msg.includes('auth/wrong-password') || msg.includes('auth/user-not-found')) {
        setError('Invalid email or password.');
      } else if (msg.includes('auth/email-already-in-use')) {
        setError('This email address is already registered.');
      } else if (msg.includes('auth/weak-password')) {
        setError('Password should be at least 6 characters.');
      } else {
        setError(msg);
      }
    } finally {
      setLoading(false);
    }
  };

  const handleSignOut = async () => {
    setLoading(true);
    try {
      await logoutUser();
      setSuccess('Signed out.');
      setTimeout(() => {
        onClose();
      }, 700);
    } catch (err: any) {
      setError(err?.message || 'Failed to sign out.');
    } finally {
      setLoading(false);
    }
  };

  const isGoogleUser = user?.providerData?.some((p) => p.providerId === 'google.com');

  return (
    <div className="fixed inset-0 z-[200] grid place-items-center overflow-y-auto bg-black/75 p-4 backdrop-blur-md animate-fadeIn">
      <div
        role="dialog" aria-modal="true" aria-label="Sign in to 3D Craft"
        className="my-auto relative w-full max-w-[420px] rounded-3xl border border-white/12 bg-[#121317]/95 p-7 shadow-2xl backdrop-blur-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Close Button */}
        <button
          onClick={onClose}
          className="absolute right-5 top-5 grid h-8 w-8 place-items-center rounded-full border border-white/10 text-chalk-dim transition-colors hover:border-white/20 hover:text-white"
        >
          <X className="h-4 w-4" />
        </button>

        {/* Back Button when in email mode */}
        {viewMode === 'email' && !user && (
          <button
            onClick={() => { setViewMode('options'); setError(null); }}
            className="absolute left-5 top-5 grid h-8 w-8 place-items-center rounded-full border border-white/10 text-chalk-dim transition-colors hover:border-white/20 hover:text-white"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
        )}

        {/* Brand Icon & Heading */}
        <div className="mb-6 flex flex-col items-center text-center">
          <div className="relative mb-3 flex h-16 w-16 items-center justify-center rounded-2xl bg-gradient-to-tr from-coral/20 via-amber-500/20 to-purple-600/20 p-0.5 shadow-xl shadow-coral/10">
            <div className="flex h-full w-full items-center justify-center rounded-2xl border border-white/15 bg-[#17181e]">
              <span className="bg-gradient-to-tr from-coral to-amber-300 bg-clip-text font-serif text-3xl font-bold text-transparent">
                3D
              </span>
            </div>
            <span className="absolute -bottom-1 -right-1 flex h-5 w-5 items-center justify-center rounded-full bg-emerald-500 shadow-md">
              <Sparkles className="h-2.5 w-2.5 text-ink" />
            </span>
          </div>

          <h2 className="text-xl font-bold tracking-tight text-white font-sans">
            3D Craft
          </h2>
          <p className="mt-0.5 text-[12px] text-chalk-dim">
            Your creations, together across devices
          </p>
        </div>

        {/* Signed In User View */}
        {user && !isGuest ? (
          <div className="space-y-4">
            <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
              <div className="flex items-center gap-3.5">
                {user.photoURL ? (
                  <img
                    src={user.photoURL}
                    alt={user.displayName || 'User'}
                    className="h-11 w-11 rounded-full border border-white/20 object-cover shadow-sm"
                  />
                ) : (
                  <div className="grid h-11 w-11 place-items-center rounded-full bg-gradient-to-tr from-coral to-amber-400 font-serif text-base font-bold text-ink shadow">
                    {(user.displayName || user.email || 'U').charAt(0).toUpperCase()}
                  </div>
                )}
                <div className="min-w-0 flex-1 text-left">
                  <div className="truncate text-sm font-semibold text-white">
                    {user.displayName || user.email?.split('@')[0]}
                  </div>
                  <div className="truncate text-xs text-chalk-dim">{user.email}</div>
                  <div className="mt-1 flex items-center gap-1.5">
                    {isGoogleUser && (
                      <span className="inline-flex items-center gap-1 rounded-md bg-white/10 px-1.5 py-0.5 text-[9px] font-medium text-white">
                        <svg className="h-2.5 w-2.5" viewBox="0 0 24 24">
                          <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                          <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                          <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" />
                          <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" />
                        </svg>
                        Google Account
                      </span>
                    )}
                    <span className="truncate font-mono text-[10px] text-chalk-ghost">
                      UID: {user.uid.slice(0, 8)}…
                    </span>
                  </div>
                </div>
              </div>

              <div className="mt-3.5 flex items-center gap-1.5 border-t border-white/5 pt-3 text-[11px] text-emerald-400">
                <CheckCircle className="h-3.5 w-3.5 shrink-0" />
                <span>Cloud Firestore real-time sync active</span>
              </div>
            </div>

            {error && (
              <div className="flex items-center gap-2 rounded-xl border border-red-500/20 bg-red-500/10 p-3 text-xs text-red-400">
                <AlertCircle className="h-4 w-4 shrink-0" />
                <span>{error}</span>
              </div>
            )}
            {success && (
              <div className="flex items-center gap-2 rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3 text-xs text-emerald-400">
                <CheckCircle className="h-4 w-4 shrink-0" />
                <span>{success}</span>
              </div>
            )}

            <div className="flex gap-2">
              <button
                onClick={handleSignOut}
                disabled={loading}
                className="flex flex-1 items-center justify-center gap-2 rounded-2xl border border-red-500/25 bg-red-500/10 py-3 text-xs font-semibold text-red-300 transition-colors hover:bg-red-500/20"
              >
                <LogOut className="h-3.5 w-3.5" />
                Sign Out
              </button>
              <button
                onClick={onClose}
                className="flex-1 rounded-2xl border border-white/10 bg-white/[0.06] py-3 text-xs font-semibold text-white transition-colors hover:bg-white/12"
              >
                Done
              </button>
            </div>
          </div>
        ) : viewMode === 'options' ? (
          /* Main Authentication Choices: Google or Email */
          <div className="space-y-4">
            {/* Terms & Conditions Agreement */}
            <div className="flex items-start gap-3 rounded-2xl border-2 border-[#83b9a4] bg-[#effaf5] p-4 text-left">
              <input id="craft-auth-agreement" type="checkbox" checked={agreed}
                onChange={event => {setAgreed(event.target.checked);setError(null)}}
                className="mt-1 h-6 w-6 shrink-0 cursor-pointer accent-[#206853] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#206853]"/>
              <label htmlFor="craft-auth-agreement" className="cursor-pointer text-[14px] leading-6 text-[#173e32]">
                I agree to the <a href="/terms" target="_blank" rel="noreferrer" className="font-semibold text-[#15553f] underline decoration-2 underline-offset-2">Terms & Conditions</a> and <a href="/privacy" target="_blank" rel="noreferrer" className="font-semibold text-[#15553f] underline decoration-2 underline-offset-2">Privacy Policy</a>.
                <span className="mt-1 block text-[13px] text-[#375d4e]">These explain how your account and creations are handled.</span>
              </label>
            </div>

            {error && (
              <div className="flex items-center gap-2 rounded-xl border border-red-500/20 bg-red-500/10 p-3 text-xs text-red-400">
                <AlertCircle className="h-4 w-4 shrink-0" />
                <span>{error}</span>
              </div>
            )}
            {success && (
              <div className="flex items-center gap-2 rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-3 text-xs text-emerald-400">
                <CheckCircle className="h-4 w-4 shrink-0" />
                <span>{success}</span>
              </div>
            )}

            {/* Google Authentication Button */}
            <button
              onClick={handleGoogleSignIn}
              disabled={googleLoading}
              className="flex w-full items-center justify-center gap-3 rounded-2xl bg-white px-4 py-3.5 text-sm font-semibold text-gray-900 shadow-lg shadow-white/5 transition-all hover:bg-gray-100 active:scale-[0.99] disabled:opacity-60"
            >
              {googleLoading ? (
                <div className="flex items-center gap-2 text-xs text-gray-600 font-medium">
                  <div className="h-4 w-4 animate-spin rounded-full border-2 border-gray-400 border-t-gray-900" />
                  Connecting to Google…
                </div>
              ) : (
                <>
                  <svg className="h-5 w-5 shrink-0" viewBox="0 0 24 24">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z" />
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z" />
                  </svg>
                  <span>Continue with Google</span>
                </>
              )}
            </button>

            {/* Email Authentication Button */}
            <button
              onClick={() => { setViewMode('email'); setError(null); }}
              className="flex w-full items-center justify-center gap-2.5 rounded-2xl border border-white/12 bg-white/[0.05] px-4 py-3.5 text-sm font-semibold text-white transition-all hover:bg-white/[0.09] active:scale-[0.99]"
            >
              <Mail className="h-4 w-4 text-chalk-dim" />
              <span>Continue with Email</span>
            </button>

            {/* Footer Notice */}
            <div className="pt-2 text-center">
              <p className="text-[11px] leading-relaxed text-chalk-dim">
                Sign in with the same account you use in the iPhone or iPad app to view your synced creations here.
              </p>
              <button
                onClick={onClose}
                className="mt-3 text-[11px] text-chalk-dim hover:text-white transition-colors underline decoration-white/20"
              >
                Back
              </button>
            </div>
          </div>
        ) : (
          /* Email / Password Form View */
          <div>
            {/* Tab switch */}
            <div className="mb-4 flex rounded-xl border border-white/10 bg-black/40 p-1">
              <button
                onClick={() => { setTab('signin'); setError(null); }}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-xs font-medium transition-all ${
                  tab === 'signin' ? 'bg-white/12 text-white shadow' : 'text-chalk-dim hover:text-chalk'
                }`}
              >
                Sign In
              </button>
              <button
                onClick={() => { setTab('signup'); setError(null); }}
                className={`flex flex-1 items-center justify-center gap-1.5 rounded-lg py-1.5 text-xs font-medium transition-all ${
                  tab === 'signup' ? 'bg-white/12 text-white shadow' : 'text-chalk-dim hover:text-chalk'
                }`}
              >
                Create Account
              </button>
            </div>

            <form onSubmit={handleEmailSubmit} className="space-y-3">
              <div>
                <label className="mb-1 block text-[11px] uppercase tracking-wider text-chalk-dim">
                  Email
                </label>
                <input
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="you@example.com"
                  className="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3.5 py-2 text-sm text-white placeholder-chalk-ghost outline-none transition-colors focus:border-coral/60 focus:bg-white/[0.07]"
                />
              </div>

              <div>
                <label className="mb-1 block text-[11px] uppercase tracking-wider text-chalk-dim">
                  Password
                </label>
                <input
                  type="password"
                  required
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="••••••••"
                  className="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3.5 py-2 text-sm text-white placeholder-chalk-ghost outline-none transition-colors focus:border-coral/60 focus:bg-white/[0.07]"
                />
              </div>

              {error && (
                <div className="flex items-center gap-2 rounded-xl border border-red-500/20 bg-red-500/10 p-2.5 text-xs text-red-400">
                  <AlertCircle className="h-4 w-4 shrink-0" />
                  <span>{error}</span>
                </div>
              )}
              {success && (
                <div className="flex items-center gap-2 rounded-xl border border-emerald-500/20 bg-emerald-500/10 p-2.5 text-xs text-emerald-400">
                  <CheckCircle className="h-4 w-4 shrink-0" />
                  <span>{success}</span>
                </div>
              )}

              <button
                type="submit"
                disabled={loading}
                className="mt-2 flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-coral/90 to-amber-500/90 py-3 text-xs font-semibold text-ink shadow-lg shadow-coral/20 transition-transform active:scale-[0.99] hover:brightness-110 disabled:opacity-50"
              >
                {loading ? 'Processing…' : tab === 'signin' ? 'Sign In with Email' : 'Create 3D Craft Account'}
              </button>
            </form>

            <div className="mt-4 text-center">
              <button
                onClick={() => setViewMode('options')}
                className="text-[11px] text-chalk-dim hover:text-white transition-colors"
              >
                ← Back to Google sign-in
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};
