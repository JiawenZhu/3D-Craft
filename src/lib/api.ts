import { auth } from './firebase';
import type {
  Asset, ConceptSetResult, GenerationSettings, Job, PipelineRun, PipelineStage, PipelineSummary, RefImage,
} from '../types';

export const API_BASE = "https://3d-craft.web.app";

export async function authenticatedFetch(input: RequestInfo | URL, init: RequestInit = {}) {
  await auth.authStateReady();
  const user = auth.currentUser;
  if (!user || user.isAnonymous) throw new Error('Sign in to your 3D Craft account.');
  const headers = new Headers(init.headers);
  headers.set('Authorization', `Bearer ${await user.getIdToken()}`);
  return fetch(input, { ...init, headers });
}


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
  /** Whether the server can run the concept stage; absent on older builds. */
  gemini?: { available: boolean; note: string };
}

const timeout = (ms: number) => {
  const c = new AbortController();
  setTimeout(() => c.abort(), ms);
  return c.signal;
};

export interface ModelPrice {
  name: string;
  unitUsd: number | null;
  texturedUsd?: number;
  effortUsd?: Record<string, number>;
  effortTexturedUsd?: Record<string, number>;
  multiUnitUsd?: number | null;
  multiTexturedUsd?: number | null;
  highPackUsd?: number;
  fourKUsd?: number;
  unit: 'generation' | 'image' | 'tokens' | 'account' | 'unknown';
  inputPerMillion?: number;
  outputPerMillion?: number;
  note: string;
  noteZh: string;
  source: string;
}
export interface PricingCatalog {
  currency: 'USD';
  verifiedAt: string;
  models: Record<string, ModelPrice>;
}

export async function getPricing(): Promise<PricingCatalog | null> {
  try {
    const response = await fetch(`${API_BASE}/api/pricing`, { signal: timeout(5000) });
    if (!response.ok) return null;
    const result = await response.json() as PricingCatalog;
    return result.currency === 'USD' && result.models ? result : null;
  } catch { return null; }
}

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
  const r = await authenticatedFetch(`${API_BASE}/api/generate`, { method: 'POST', body: fd });
  if (!r.ok) throw new Error(`generate failed: ${r.status} ${await r.text()}`);
  return r.json();
}

export async function getJob(id: string): Promise<Job & { assets: Asset[] }> {
  const r = await authenticatedFetch(`${API_BASE}/api/jobs/${id}`);
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
    const r = await authenticatedFetch(`${API_BASE}/api/inbox`, { signal: timeout(3000) });
    if (!r.ok) return [];
    return await r.json();
  } catch {
    return [];
  }
}

export async function listAssets(): Promise<Asset[]> {
  try {
    const r = await authenticatedFetch(`${API_BASE}/api/assets`, { signal: timeout(3000) });
    if (!r.ok) return [];
    return await r.json();
  } catch {
    return [];
  }
}

export async function deleteAsset(id: string): Promise<void> {
  await authenticatedFetch(`${API_BASE}/api/assets/${id}`, { method: 'DELETE' });
}

export const absolute = (url?: string) => {
  if (!url) return undefined;
  if (/^https?:|^blob:|^data:/.test(url)) return url;
  if (url.startsWith('/images/') || url.startsWith('/models/')) return url;
  return `${API_BASE}${url}`;
};

/* ------------------------------------------------------------------ pipelines
 * The concept run. Everything here goes through this process — the Gemini key
 * lives on the server and the browser never sees it, same rule as FAL_KEY.
 * ------------------------------------------------------------------------- */

export async function startPipeline(
  prompt: string,
  settings: GenerationSettings,
  image?: RefImage,
): Promise<{ run_id: string }> {
  const fd = new FormData();
  fd.append('prompt', prompt);
  fd.append('settings', JSON.stringify(settings));
  if (image?.file) fd.append('image', image.file, image.name);
  if (image?.sourceUrl) fd.append('sourceRef', image.sourceUrl);

  const r = await authenticatedFetch(`${API_BASE}/api/pipelines`, { method: 'POST', body: fd });
  if (!r.ok) {
    // FastAPI puts the reason in {detail}; surfacing it is the difference
    // between "503" and "GEMINI_API_KEY not set".
    let why = `${r.status}`;
    try { why = (await r.json()).detail ?? why; } catch { /* keep the status */ }
    throw new Error(why);
  }
  return r.json();
}

export async function getPipeline(id: string): Promise<PipelineRun> {
  const r = await authenticatedFetch(`${API_BASE}/api/pipelines/${id}`);
  if (!r.ok) throw new Error(`run ${id}: ${r.status}`);
  return r.json();
}

export async function listPipelines(): Promise<PipelineSummary[]> {
  try {
    const r = await authenticatedFetch(`${API_BASE}/api/pipelines`, { signal: timeout(3000) });
    if (!r.ok) return [];
    return await r.json();
  } catch {
    return [];
  }
}

/** Re-run from one stage onward; everything before it is kept as-is. */
export async function retryPipeline(id: string, stage: PipelineStage, prompt?: string): Promise<void> {
  const fd = new FormData();
  fd.append('stage', stage);
  if (prompt !== undefined) fd.append('prompt', prompt);
  const r = await authenticatedFetch(`${API_BASE}/api/pipelines/${id}/retry`, { method: 'POST', body: fd });
  if (!r.ok) throw new Error(`retry failed: ${r.status}`);
}

export async function deletePipeline(id: string): Promise<void> {
  await authenticatedFetch(`${API_BASE}/api/pipelines/${id}`, { method: 'DELETE' });
}

export async function generateConceptSet(
  image?: File | Blob | null,
  imageUrl?: string | null,
  prompt: string = '',
  count: number = 4,
): Promise<ConceptSetResult> {
  const fd = new FormData();
  if (image) fd.append('image', image, 'upload.png');
  if (imageUrl) fd.append('image_url', imageUrl);
  fd.append('prompt', prompt);
  fd.append('count', String(count));

  const r = await authenticatedFetch(`${API_BASE}/api/concept-set`, { method: 'POST', body: fd });
  if (!r.ok) {
    let why = `${r.status}`;
    try { why = (await r.json()).detail ?? why; } catch { /* keep status */ }
    throw new Error(why);
  }
  return r.json();
}

export async function selectPipelineConcept(runId: string, imageUrl: string): Promise<void> {
  const fd = new FormData();
  fd.append('image_url', imageUrl);
  const r = await authenticatedFetch(`${API_BASE}/api/pipelines/${runId}/select-concept`, { method: 'POST', body: fd });
  if (!r.ok) throw new Error(`select concept failed: ${r.status}`);
}

export async function directPipelineRecon(runId: string): Promise<void> {
  const r = await authenticatedFetch(`${API_BASE}/api/pipelines/${runId}/direct-recon`, { method: 'POST' });
  if (!r.ok) throw new Error(`direct recon failed: ${r.status}`);
}
