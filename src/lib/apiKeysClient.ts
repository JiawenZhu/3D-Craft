import { auth } from './firebase';
import { API_ORIGIN, parseCreatedKey, parseKeyList, type ApiKeyMeta, type CreatedApiKey } from './apiKeys';

/* Key management uses the normal Firebase ID token against the canonical
 * cloud origin — never a local server. Every call is pinned to the uid that
 * started it, so a sign-out or account switch mid-request can neither send
 * another account's token nor hand this account's result to the next. */

export class AccountChangedError extends Error {
  constructor() { super('Your account changed. Please try again.'); }
}

async function keysFetch(uid: string, path: string, init: RequestInit = {}) {
  await auth.authStateReady();
  const user = auth.currentUser;
  if (!user || user.isAnonymous || user.uid !== uid) throw new AccountChangedError();
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${await user.getIdToken()}`);
  if (init.body) headers.set('Content-Type', 'application/json');
  const r = await fetch(`${API_ORIGIN}${path}`, { ...init, headers, cache: 'no-store' });
  if (auth.currentUser?.uid !== uid) throw new AccountChangedError();
  let body: unknown = null;
  try { body = await r.json(); } catch { /* non-JSON error page */ }
  if (!r.ok) {
    const detail = (body as { detail?: unknown } | null)?.detail;
    throw new Error(typeof detail === 'string' ? detail : `API keys are unavailable right now (${r.status}).`);
  }
  return body;
}

export async function listApiKeys(uid: string): Promise<ApiKeyMeta[]> {
  return parseKeyList(await keysFetch(uid, '/api/keys'));
}

export async function createApiKey(
  uid: string,
  body: { name: string; scopes: string[]; expiresInDays: number | null },
): Promise<CreatedApiKey> {
  const created = parseCreatedKey(await keysFetch(uid, '/api/keys', { method: 'POST', body: JSON.stringify(body) }));
  if (!created) throw new Error('The key could not be displayed. Revoke any key you don’t recognize below, then try again.');
  return created;
}

export async function revokeApiKey(uid: string, keyId: string): Promise<void> {
  await keysFetch(uid, `/api/keys/${encodeURIComponent(keyId)}`, { method: 'DELETE' });
}
