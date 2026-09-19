import { useEffect, useRef, useState } from 'react';
import { Check, Copy, KeyRound, Plus, ShieldCheck, Trash2 } from 'lucide-react';
import { AccountChangedError, createApiKey, listApiKeys, revokeApiKey } from '../../lib/apiKeysClient';
import {
  API_SCOPES, DEFAULT_EXPIRY, EXPIRY_OPTIONS, MAX_NAME_LENGTH, describeScopes, displayPrefix, formatKeyDate, keyStatus,
  requestScopes, validateKeyName, type ApiKeyMeta, type CreatedApiKey, type ExpiryDays,
} from '../../lib/apiKeys';

const message = (e: unknown, fallback: string) => e instanceof Error ? e.message : fallback;

/**
 * Mount with `key={uid}` so a sign-out or account switch discards every piece
 * of state, including a key that is mid-reveal. The plaintext secret lives only
 * in `revealed` and is never written to storage, the URL or the console.
 */
export function ApiKeysManager({ uid }: { uid: string }) {
  const [keys, setKeys] = useState<ApiKeyMeta[] | null>(null);
  const [error, setError] = useState('');
  const [name, setName] = useState('');
  const [expiry, setExpiry] = useState<ExpiryDays>(DEFAULT_EXPIRY);
  const [fullAccess, setFullAccess] = useState(true);
  const [allowDelete, setAllowDelete] = useState(false);
  const [scopes, setScopes] = useState<string[]>(API_SCOPES.map(s => s.id));
  const [creating, setCreating] = useState(false);
  const [revealed, setRevealed] = useState<CreatedApiKey | null>(null);
  const [copied, setCopied] = useState(false);
  const [stored, setStored] = useState(false);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [revoking, setRevoking] = useState<string | null>(null);
  const alive = useRef(true);

  // An AccountChangedError means this component is about to unmount — stay quiet.
  const fail = (e: unknown, fallback: string) => {
    if (alive.current && !(e instanceof AccountChangedError)) setError(message(e, fallback));
  };
  const refresh = async () => {
    try { const k = await listApiKeys(uid); if (alive.current) setKeys(k); }
    catch (e) { if (alive.current) setKeys(k => k ?? []); fail(e, 'Could not load your API keys.'); }
  };

  useEffect(() => {
    alive.current = true;
    void refresh();
    return () => { alive.current = false; };
  }, [uid]);

  async function create(event: React.FormEvent) {
    event.preventDefault();
    const nameError = validateKeyName(name);
    const chosen = requestScopes(fullAccess, scopes, allowDelete);
    if (nameError) return setError(nameError);
    if (!chosen) return setError('Choose at least one permission, or allow full access.');
    setCreating(true); setError('');
    try {
      const result = await createApiKey(uid, { name: name.trim(), scopes: chosen, expiresInDays: expiry });
      if (!alive.current) return;
      setRevealed(result); setCopied(false); setStored(false); setName('');
      void refresh();
    } catch (e) {
      fail(e, 'The key could not be created.');
    } finally {
      if (alive.current) setCreating(false);
    }
  }

  async function copy() {
    if (!revealed) return;
    try { await navigator.clipboard.writeText(revealed.key); if (alive.current) setCopied(true); }
    catch { setError('Copy was blocked by the browser. Select the key and copy it manually.'); }
  }

  async function revoke(id: string) {
    setRevoking(id); setError('');
    try {
      await revokeApiKey(uid, id);
      if (!alive.current) return;
      setConfirming(null);
      await refresh();
    } catch (e) {
      fail(e, 'The key could not be revoked.');
    } finally {
      if (alive.current) setRevoking(null);
    }
  }

  const toggleScope = (id: string) =>
    setScopes(current => current.includes(id) ? current.filter(s => s !== id) : [...current, id]);

  return <div className="api-keys">
    {revealed && <section className="api-reveal" aria-labelledby="api-reveal-title">
      <h3 id="api-reveal-title"><ShieldCheck size={18} /> Copy “{revealed.name}” now</h3>
      <p>This is the only time the full key is shown. 3D Craft stores only a one-way hash, so it can’t be recovered — if you lose it, revoke it and create a new one.</p>
      <div className="api-secret">
        <input readOnly value={revealed.key} aria-label="New API key" spellCheck={false} autoComplete="off"
          onFocus={e => e.currentTarget.select()} data-lpignore="true" />
        <button type="button" onClick={() => void copy()}>{copied ? <><Check size={16} /> Copied</> : <><Copy size={16} /> Copy</>}</button>
      </div>
      {revealed.warning && <p className="api-note">{revealed.warning}</p>}
      <label className="api-check"><input type="checkbox" checked={stored} onChange={e => setStored(e.target.checked)} /> I’ve stored this key somewhere safe</label>
      <button type="button" className="api-primary" disabled={!stored} onClick={() => { setRevealed(null); setCopied(false); setStored(false); }}>Done — hide key</button>
    </section>}

    {!revealed && <form className="api-card api-create" onSubmit={create}>
      <h3><Plus size={18} /> Create a key</h3>
      <label className="api-field">Name
        <input value={name} maxLength={MAX_NAME_LENGTH} placeholder="e.g. My script" onChange={e => setName(e.target.value)} autoComplete="off" />
      </label>
      <fieldset className="api-field">
        <legend>Expires after</legend>
        <div className="api-segments" role="radiogroup" aria-label="Expires after">
          {EXPIRY_OPTIONS.map(days => <button type="button" key={days} role="radio" aria-checked={expiry === days}
            className={expiry === days ? 'active' : ''} onClick={() => setExpiry(days)}>{days === 365 ? '1 year' : `${days} days`}</button>)}
        </div>
      </fieldset>
      <fieldset className="api-field">
        <legend>Permissions</legend>
        <label className="api-check"><input type="checkbox" checked={fullAccess} onChange={e => setFullAccess(e.target.checked)} /> Full API access</label>
        {!fullAccess && <div className="api-scopes">
          {API_SCOPES.map(s => <label key={s.id} className="api-check">
            <input type="checkbox" checked={scopes.includes(s.id)} onChange={() => toggleScope(s.id)} /> {s.label} <code>{s.id}</code>
          </label>)}
        </div>}
        <label className="api-check"><input type="checkbox" checked={allowDelete} onChange={e => setAllowDelete(e.target.checked)} /> Allow permanent deletes <code>assets:delete</code></label>
        <p className="api-note">Lets the tool erase projects, images and 3D objects. Deleted work can’t be restored. Full access never includes this.</p>
        <p className="api-note">Grant only what the connected tool needs. No key can manage other keys or perform account administration such as deleting your account.</p>
      </fieldset>
      <button className="api-primary" disabled={creating}>{creating ? 'Creating…' : 'Create key'}</button>
    </form>}

    {error && <p role="alert" className="api-error">{error}</p>}

    <section className="api-card" aria-labelledby="api-list-title">
      <h3 id="api-list-title"><KeyRound size={18} /> Your keys</h3>
      {keys === null ? <p className="api-note" role="status">Loading your keys…</p>
        : keys.length === 0 ? <p className="api-note">No keys yet. Keys you create appear here with their prefix only.</p>
        : <ul className="api-list">{keys.map(k => {
          const status = keyStatus(k);
          return <li key={k.id} className={status}>
            <div>
              <strong>{k.name}</strong> <span className={`api-badge ${status}`}>{status === 'active' ? 'Active' : status === 'expired' ? 'Expired' : 'Revoked'}</span>
              <code className="api-prefix">{displayPrefix(k.prefix)}</code>
              <small>{describeScopes(k.scopes)}</small>
              <small>Created {formatKeyDate(k.createdAt)} · {status === 'revoked' ? `Revoked ${formatKeyDate(k.revokedAt)}` : `Expires ${formatKeyDate(k.expiresAt, 'never')}`} · Last used {formatKeyDate(k.lastUsedAt, 'never')}</small>
            </div>
            {status === 'active' && (confirming === k.id
              ? <div className="api-confirm" role="group" aria-label={`Confirm revoking ${k.name}`}>
                  <span>Revoke now? Anything using this key stops working immediately.</span>
                  <button type="button" onClick={() => setConfirming(null)} disabled={revoking === k.id}>Cancel</button>
                  <button type="button" className="api-danger" onClick={() => void revoke(k.id)} disabled={revoking === k.id}>{revoking === k.id ? 'Revoking…' : 'Revoke key'}</button>
                </div>
              : <button type="button" className="api-ghost" onClick={() => setConfirming(k.id)}><Trash2 size={15} /> Revoke</button>)}
          </li>;
        })}</ul>}
    </section>
  </div>;
}
