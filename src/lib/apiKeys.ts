/* ------------------------------------------------------------------ api keys
 * Pure helpers for user-owned API credentials. No network or storage here —
 * the plaintext key only ever lives in React state for the one-time reveal.
 * ------------------------------------------------------------------------- */

export const API_ORIGIN = 'https://3d-craft.web.app';
export const OPENAPI_URL = `${API_ORIGIN}/api/v1/openapi.json`;

export interface ApiKeyMeta {
  id: string;
  name: string;
  prefix: string;
  scopes: string[];
  /** Epoch seconds. */
  createdAt: number;
  expiresAt: number | null;
  revokedAt: number | null;
  lastUsedAt: number | null;
  revoked: boolean;
}

export interface CreatedApiKey extends Omit<ApiKeyMeta, 'revoked' | 'revokedAt' | 'lastUsedAt'> {
  key: string;
  warning: string;
}

export const EXPIRY_OPTIONS = [30, 90, 365] as const;
export type ExpiryDays = (typeof EXPIRY_OPTIONS)[number];
export const DEFAULT_EXPIRY: ExpiryDays = 90;

export const API_SCOPES = [
  { id: 'assets:read', label: 'Read projects, jobs & assets' },
  { id: 'prompt:write', label: 'Chat & plan model prompts' },
  { id: 'concepts:write', label: 'Create & refine concept images' },
  { id: 'models:write', label: 'Start 3D model generation' },
  { id: 'wallet:read', label: 'Read Token balance' },
] as const;

export const MAX_NAME_LENGTH = 64;

export type KeyStatus = 'active' | 'expired' | 'revoked';

export function keyStatus(key: Pick<ApiKeyMeta, 'revoked' | 'expiresAt'>, nowSeconds = Date.now() / 1000): KeyStatus {
  if (key.revoked) return 'revoked';
  if (key.expiresAt != null && key.expiresAt <= nowSeconds) return 'expired';
  return 'active';
}

/** Full access is sent as ['*']; an empty custom selection is invalid. */
/** Permanent deletion is never part of full access; the server requires it explicitly. */
export const DELETE_SCOPE = 'assets:delete';

export function requestScopes(fullAccess: boolean, selected: readonly string[], allowDelete = false): string[] | null {
  const base = fullAccess ? ['*'] : API_SCOPES.map(s => s.id as string).filter(id => selected.includes(id));
  if (!base.length) return null;
  return allowDelete ? [...base, DELETE_SCOPE] : base;
}

export function validateKeyName(raw: string): string | null {
  const name = raw.trim();
  if (!name) return 'Give this key a name so you can recognize it later.';
  if (name.length > MAX_NAME_LENGTH) return `Use ${MAX_NAME_LENGTH} characters or fewer.`;
  return null;
}

/** Server prefixes already end in '...'; normalise to one ellipsis. */
export const displayPrefix = (prefix: string) => prefix.replace(/(\.{3}|…)+$/, '') + '…';

export function describeScopes(scopes: readonly string[]): string {
  const canDelete = scopes.includes(DELETE_SCOPE) ? ' · Can delete' : '';
  if (scopes.includes('*')) return 'Full API access' + canDelete;
  const labels = scopes.filter(id => id !== DELETE_SCOPE).map(id => API_SCOPES.find(s => s.id === id)?.label ?? id);
  return (labels.length ? labels.join(' · ') : 'No scopes') + canDelete;
}

export function formatKeyDate(seconds: number | null | undefined, empty = '—'): string {
  if (seconds == null || !Number.isFinite(seconds) || seconds <= 0) return empty;
  return new Date(seconds * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}

function num(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Whitelisted fields only, so nothing else the server sends can reach the UI. */
export function parseKeyMeta(raw: unknown): ApiKeyMeta | null {
  if (!raw || typeof raw !== 'object') return null;
  const d = raw as Record<string, unknown>;
  if (typeof d.id !== 'string' || !d.id) return null;
  return {
    id: d.id,
    name: typeof d.name === 'string' && d.name ? d.name : 'API key',
    prefix: typeof d.prefix === 'string' ? d.prefix : 'craft_live_',
    scopes: Array.isArray(d.scopes) ? d.scopes.filter((s): s is string => typeof s === 'string') : [],
    createdAt: num(d.createdAt) ?? 0,
    expiresAt: num(d.expiresAt),
    revokedAt: num(d.revokedAt),
    lastUsedAt: num(d.lastUsedAt),
    revoked: d.revoked === true,
  };
}

export function parseKeyList(raw: unknown): ApiKeyMeta[] {
  const keys = raw && typeof raw === 'object' ? (raw as { keys?: unknown }).keys : null;
  if (!Array.isArray(keys)) return [];
  return keys.map(parseKeyMeta).filter((k): k is ApiKeyMeta => k !== null)
    .sort((a, b) => b.createdAt - a.createdAt);
}

export function parseCreatedKey(raw: unknown): CreatedApiKey | null {
  const meta = parseKeyMeta(raw);
  const d = raw as Record<string, unknown> | null;
  if (!meta || !d || typeof d.key !== 'string' || !d.key.startsWith('craft_live_')) return null;
  return {
    id: meta.id, name: meta.name, prefix: meta.prefix, scopes: meta.scopes,
    createdAt: meta.createdAt, expiresAt: meta.expiresAt, key: d.key,
    warning: typeof d.warning === 'string' ? d.warning : '',
  };
}

/** Example request with a placeholder — never interpolate a real secret here. */
export const CURL_EXAMPLE =
  `curl ${API_ORIGIN}/api/v1/wallet \\\n  -H "Authorization: Bearer $CRAFT_API_KEY"`;
