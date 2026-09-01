import type { Asset, GenerationSettings, Job, RefImage } from '../types';

export const API_BASE = (import.meta as any).env?.VITE_API_BASE ?? 'http://127.0.0.1:8000';

export interface EngineHealth {
  installed: boolean;
  loaded: boolean;
  note: string;
  /** "local" (native torch) or "space" (hosted Hugging Face Space). */
  provider: string;
  /** Wall-clock estimate per effort tier for wherever this engine actually runs. */
  effortSeconds?: Record<string, number>;
  /** USD per generation when running through a paid API; 0 when local/free. */
  pricePerGen?: number;
}
export interface Health {
  status: 'ok';
  device: string;
  torch: string;
  provider: string;
  engines: Record<string, EngineHealth>;
}

const timeout = (ms: number) => {
  const c = new AbortController();
  setTimeout(() => c.abort(), ms);
  return c.signal;
};

export async function getHealth(): Promise<Health | null> {
  try {
    const r = await fetch(`${API_BASE}/api/health`, { signal: timeout(2500) });
    if (!r.ok) return null;
    return (await r.json()) as Health;
  } catch {
    return null;
  }
}

export async function submitJob(settings: GenerationSettings, images: RefImage[]): Promise<{ job_id: string }> {
  const fd = new FormData();
  // Trace the result back to the gallery image it came from.
  const sourceRef = images.find((i) => i.sourceUrl)?.sourceUrl;
  fd.append('settings', JSON.stringify(sourceRef ? { ...settings, sourceRef } : settings));
  // append in lockstep — the server zips images with directions by index
  images.forEach((img) => {
    if (!img.file) return;
    fd.append('images', img.file, img.name);
    fd.append('directions', img.direction);
  });
  const r = await fetch(`${API_BASE}/api/generate`, { method: 'POST', body: fd });
  if (!r.ok) throw new Error(`generate failed: ${r.status} ${await r.text()}`);
  return r.json();
}

export async function getJob(id: string): Promise<Job & { assets: Asset[] }> {
  const r = await fetch(`${API_BASE}/api/jobs/${id}`);
  if (!r.ok) throw new Error(`job ${id}: ${r.status}`);
  return r.json();
}

export interface InboxImage {
  name: string;
  /** Same-origin path when the folder is under public/, else an API path. */
  url: string;
  /** Always resolvable through the API, for folders outside public/. */
  apiUrl?: string;
  direction: string;
  sizeKb: number;
  modifiedAt: number;
}

/**
 * Resolve an image path for the browser.
 *
 * Anything the dev server already serves (/images/...) must stay same-origin —
 * prefixing it with the API base turns a plain load into a cross-origin fetch
 * that CORS then blocks.
 */
export const imageSrc = (url?: string) =>
  !url ? undefined : url.startsWith('/images/') ? url : absolute(url);

/** Reference images handed over by the image/animation side. */
export async function listInbox(): Promise<InboxImage[]> {
  try {
    const r = await fetch(`${API_BASE}/api/inbox`, { signal: timeout(3000) });
    if (!r.ok) return [];
    return await r.json();
  } catch {
    return [];
  }
}

export async function listAssets(): Promise<Asset[]> {
  try {
    const r = await fetch(`${API_BASE}/api/assets`, { signal: timeout(3000) });
    if (!r.ok) return [];
    return await r.json();
  } catch {
    return [];
  }
}

export async function deleteAsset(id: string): Promise<void> {
  await fetch(`${API_BASE}/api/assets/${id}`, { method: 'DELETE' });
}

export const absolute = (url?: string) =>
  !url ? undefined : /^https?:|^blob:|^data:/.test(url) ? url : `${API_BASE}${url}`;
