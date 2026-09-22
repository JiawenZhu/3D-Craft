import { useEffect, useState } from 'react';
import { ArrowLeft, ExternalLink, LogOut } from 'lucide-react';
import { auth, logoutUser, onAuthStateChanged, type User } from '../lib/firebase';
import { API_ORIGIN, CURL_EXAMPLE, OPENAPI_URL } from '../lib/apiKeys';
import { ApiKeysManager } from '../components/auth/ApiKeysManager';
import { AuthModal } from '../components/auth/AuthModal';
import { LegalFooter } from './LegalPages';
import './showcase.css';
import './apiAccess.css';

export function ApiAccess() {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [login, setLogin] = useState(false);
  useEffect(() => { document.title = 'API access — 3D Craft'; }, []);
  useEffect(() => onAuthStateChanged(auth, u => { setUser(u && !u.isAnonymous ? u : null); setReady(true); }), []);

  return <div className="craft-showcase api-page">
    <header className="showcase-nav">
      <a className="showcase-brand" href="/"><img src="/craft-icon.png" alt="3D Craft" width="38" height="38" />3D Craft</a>
      <nav>
        <a href="/"><ArrowLeft size={16} /> Back</a>
        {user && <button onClick={() => void logoutUser()}><LogOut size={16} /> Sign out</button>}
      </nav>
    </header>
    <main className="api-main">
      <span className="showcase-eyebrow">Account · API access</span>
      <h1>Use 3D Craft from your own tools</h1>
      <p className="api-lede">Create a personal API key to call 3D Craft from scripts and tools that support custom HTTP requests. API calls act as your account and spend your real production Token balance. Apple Sandbox test Tokens from TestFlight can’t be used with API keys. Anyone holding a key can spend your Tokens until you revoke it or it expires.</p>

      {!ready ? <p role="status">Loading your account…</p>
        : !user ? <div className="api-card">
            <p>Sign in to create and manage API keys for your account.</p>
            <button className="api-primary" onClick={() => setLogin(true)}>Sign in</button>
          </div>
        : <>
            <p className="api-account">Signed in as <strong>{user.email}</strong></p>
            {/* key={uid}: an account switch remounts and drops any revealed secret. */}
            <ApiKeysManager key={user.uid} uid={user.uid} />
          </>}

      <section className="api-card api-connect" aria-labelledby="api-connect-title">
        <h2 id="api-connect-title">Connect a client</h2>
        <dl>
          <dt>Base URL</dt><dd><code>{API_ORIGIN}/api/v1</code></dd>
          <dt>OpenAPI schema</dt><dd><a href={OPENAPI_URL} target="_blank" rel="noreferrer"><code>{OPENAPI_URL}</code> <ExternalLink size={13} /></a></dd>
          <dt>Authentication</dt><dd>HTTP header <code>Authorization: Bearer &lt;your key&gt;</code></dd>
          <dt>Operations</dt><dd>Token balance, projects, concept images and refinements, model-prompt planning, 3D model jobs and finished assets.</dd>
        </dl>
        <pre aria-label="Example request"><code>{CURL_EXAMPLE}</code></pre>
        <h3>Assistants and agents</h3>
        <p className="api-note">3D Craft doesn’t have built-in integrations with ChatGPT, Claude or other assistants. A key works with any client that lets you add a custom HTTP tool using an OpenAPI schema and a Bearer key. Check your client’s own documentation to see whether it supports this; many mobile chat apps don’t.</p>
        <p className="api-note"><a href="https://muse.ai/join" target="_blank" rel="noreferrer">Muse by Meta</a>: integration hasn’t been verified yet.</p>
        <p className="api-note">Paste a key only into a client’s dedicated secret or authentication field — never into a chat message, prompt, shared document or link.</p>
      </section>
    </main>
    <AuthModal open={login} onClose={() => setLogin(false)} />
    <LegalFooter />
  </div>;
}
