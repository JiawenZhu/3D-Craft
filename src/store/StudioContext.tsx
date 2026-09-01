import React, {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState,
} from 'react';
import type {
  Asset, EngineId, GenerationSettings, Job, JobStage, RefImage, ShelfTab,
} from '../types';
import { engineById } from '../data/engines';
import * as api from '../lib/api';

const DEFAULT_SETTINGS: GenerationSettings = {
  engine: 'trellis-2',
  mode: 'image-to-3d',
  inputMode: 'image',
  imageMode: 'single',
  prompt: '',
  negativePrompt: '',
  effort: 'high',
  quality: 'default',
  creation: 'build-myself',
  geoMode: 'sharp',
  poseMode: 'none',
  batch: 1,
  seed: null,
  guidance: 7.5,
  steps: 50,
  targetFaces: 40_000,
  texture: true,
  quadRemesh: false,
  removeBackground: true,
  isPrivate: false,
  compare: false,
  compareWith: 'rodin',
};

/** Narration used by the preview simulator when no backend is running. */
const STAGES: Record<string, { stage: JobStage; message: string; weight: number }[]> = {
  'trellis-2': [
    { stage: 'preprocessing', message: 'Removing background · normalising input', weight: 0.08 },
    { stage: 'sparse-structure', message: 'Sampling sparse structure (SS flow)', weight: 0.3 },
    { stage: 'latent', message: 'Decoding structured latents (SLAT)', weight: 0.3 },
    { stage: 'mesh', message: 'Extracting mesh · marching cubes', weight: 0.2 },
    { stage: 'packaging', message: 'Baking vertex colour · writing GLB', weight: 0.12 },
  ],
  'hunyuan3d-2.1': [
    { stage: 'preprocessing', message: 'Removing background · normalising input', weight: 0.06 },
    { stage: 'latent', message: 'Shape diffusion (Hunyuan3D-DiT)', weight: 0.42 },
    { stage: 'mesh', message: 'Extracting mesh · decimating', weight: 0.14 },
    { stage: 'texture', message: 'Painting PBR maps (Hunyuan3D-Paint)', weight: 0.3 },
    { stage: 'packaging', message: 'Packing albedo / metallic / roughness', weight: 0.08 },
  ],
  hybrid: [
    { stage: 'preprocessing', message: 'Removing background · normalising input', weight: 0.05 },
    { stage: 'sparse-structure', message: 'TRELLIS · sparse structure', weight: 0.22 },
    { stage: 'latent', message: 'TRELLIS · structured latents', weight: 0.22 },
    { stage: 'mesh', message: 'Mesh extraction · quad remesh', weight: 0.16 },
    { stage: 'texture', message: 'Hunyuan3D-Paint · PBR texturing', weight: 0.28 },
    { stage: 'packaging', message: 'Writing GLB + texture set', weight: 0.07 },
  ],
};

const TINTS = ['#d18b2f', '#8771ff', '#5aa6c0', '#c4553a', '#6f9a63', '#caa14e', '#b98d5f'];
const SHAPES: Asset['seedShape'][] = ['figure', 'mech', 'creature', 'prop', 'vehicle'];

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Which engines one GENERATE press should run, in order. */
const compareQueue = (s: GenerationSettings): EngineId[] =>
  s.compare && s.compareWith !== s.engine ? [s.engine, s.compareWith] : [s.engine];

interface StudioValue {
  settings: GenerationSettings;
  patch: (p: Partial<GenerationSettings>) => void;
  images: RefImage[];
  addImages: (files: FileList | File[]) => void;
  /** Pull a handed-off inbox image in as a reference. */
  addFromUrl: (url: string, name: string, direction?: RefImage['direction']) => Promise<void>;
  inbox: api.InboxImage[];
  refreshInbox: () => void;
  removeImage: (id: string) => void;
  setDirection: (id: string, d: RefImage['direction']) => void;
  clearImages: () => void;

  job: Job | null;
  /** Last user-facing problem that was not a generation failure. */
  notice: string | null;
  dismissNotice: () => void;
  generate: () => void;
  /** Re-run an existing asset's source image against a new prompt. */
  regenerate: (asset: Asset, prompt: string) => void;
  cancel: () => void;

  assets: Asset[];
  exploreAssets: Asset[];
  toggleLike: (id: string) => void;
  removeAsset: (id: string) => void;

  activeAsset: Asset | null;
  openAsset: (a: Asset) => void;
  closeAsset: () => void;

  /** Two results of one compare run, shown side by side. */
  comparison: Asset[] | null;
  openComparison: (a: Asset[]) => void;
  closeComparison: () => void;

  shelfTab: ShelfTab;
  setShelfTab: (t: ShelfTab) => void;

  health: api.Health | null;
  backendOnline: boolean;
  credits: number;
  /** Seconds for an effort tier, from the backend when it knows better. */
  estimate: (engine: EngineId, effort: string) => number;
  /** USD per generation for an engine — 0 when it runs locally / free. */
  price: (engine: EngineId) => number;
  /** What this GENERATE press will actually cost, across the whole run. */
  runCost: number;
}

const Ctx = createContext<StudioValue | null>(null);

export const useStudio = () => {
  const v = useContext(Ctx);
  if (!v) throw new Error('useStudio must be used inside <StudioProvider>');
  return v;
};

export const StudioProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [settings, setSettings] = useState<GenerationSettings>(DEFAULT_SETTINGS);
  const [images, setImages] = useState<RefImage[]>([]);
  const [job, setJob] = useState<Job | null>(null);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [exploreAssets, setExplore] = useState<Asset[]>([]);
  const [activeAsset, setActiveAsset] = useState<Asset | null>(null);
  const [comparison, setComparison] = useState<Asset[] | null>(null);
  const [shelfTab, setShelfTab] = useState<ShelfTab>('explore');
  const [health, setHealth] = useState<api.Health | null>(null);
  const [inbox, setInbox] = useState<api.InboxImage[]>([]);
  const [credits, setCredits] = useState(120);
  const [notice, setNotice] = useState<string | null>(null);

  const abort = useRef(false);
  const running = useRef(false);
  const inboxSignature = useRef('');

  const patch = useCallback((p: Partial<GenerationSettings>) => setSettings((s) => ({ ...s, ...p })), []);

  /* ---- reference images ------------------------------------------------ */
  const addImages = useCallback((files: FileList | File[]) => {
    const list = Array.from(files).filter((f) => f.type.startsWith('image/'));
    if (!list.length) return;
    setImages((prev) => {
      const room = settings.imageMode === 'single' ? 1 : 8;
      const next = [
        ...(settings.imageMode === 'single' ? [] : prev),
        ...list.map((f, i) => ({
          id: `img-${Date.now()}-${i}`,
          url: URL.createObjectURL(f),
          name: f.name,
          direction: 'unknown' as const,
          file: f,
        })),
      ];
      return next.slice(0, room);
    });
  }, [settings.imageMode]);

  const addFromUrl = useCallback(async (url: string, name: string, direction: RefImage['direction'] = 'unknown') => {
    const abs = api.imageSrc(url)!;
    const res = await fetch(abs);
    const blob = await res.blob();
    // Vite answers a missing static file with 200 + index.html rather than 404,
    // so a stale path yields an HTML "image" that the engine rejects downstream
    // with an unhelpful UnidentifiedImageError. Catch it here instead.
    if (!res.ok || !blob.type.startsWith('image/')) {
      const why = `${name} could not be loaded — it is no longer at ${url}`;
      setNotice(why);
      throw new Error(why);
    }
    const file = new File([blob], name, { type: blob.type });
    setImages((prev) => {
      const room = settings.imageMode === 'single' ? 1 : 8;
      const next = [
        ...(settings.imageMode === 'single' ? [] : prev),
        { id: `inbox-${Date.now()}-${name}`, url: URL.createObjectURL(file), name, direction, file, sourceUrl: url },
      ];
      return next.slice(0, room);
    });
  }, [settings.imageMode]);

  const refreshInbox = useCallback(() => {
    api.listInbox().then((items) => {
      const signature = items.map((i) => `${i.url}:${i.modifiedAt}`).join('|');
      if (signature === inboxSignature.current) return;
      inboxSignature.current = signature;
      setInbox(items);
      // Surface the hand-off images as EXPLORE cards: real art you can generate
      // from, rather than procedural filler.
      setExplore(items.map((img, i) => ({
        id: `ref-${img.url}`,
        name: img.name.replace(/\.[^.]+$/, '').replace(/[_-]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
        prompt: img.name.replace(/\.[^.]+$/, '').replace(/[_-]/g, ' '),
        engine: 'trellis-2' as const,
        createdAt: img.modifiedAt,
        thumbUrl: img.url,
        seedShape: 'prop' as const,
        tint: '#b98d5f',
        faces: 0, vertices: 0, textureRes: 0,
        fileSizeMb: Math.round((img.sizeKb / 1024) * 100) / 100,
        liked: false, likes: 0,
        author: 'inbox', visibility: 'public' as const, local: false,
        isReference: true,
      })));
    });
  }, []);
  // The image side drops files in whenever it likes, so poll rather than only
  // reading the folder once at mount — otherwise new art never appears.
  useEffect(() => {
    refreshInbox();
    const iv = window.setInterval(refreshInbox, 5000);
    const onFocus = () => refreshInbox();
    window.addEventListener('focus', onFocus);
    return () => { window.clearInterval(iv); window.removeEventListener('focus', onFocus); };
  }, [refreshInbox, health?.status]);

  const removeImage = useCallback((id: string) => {
    setImages((prev) => {
      prev.filter((i) => i.id === id).forEach((i) => URL.revokeObjectURL(i.url));
      return prev.filter((i) => i.id !== id);
    });
  }, []);

  const clearImages = useCallback(() => {
    setImages((prev) => { prev.forEach((i) => URL.revokeObjectURL(i.url)); return []; });
  }, []);

  const setDirection = useCallback((id: string, direction: RefImage['direction']) => {
    setImages((prev) => prev.map((i) => (i.id === id ? { ...i, direction } : i)));
  }, []);

  /* ---- backend health --------------------------------------------------- */
  useEffect(() => {
    let stop = false;
    let misses = 0;
    const tick = async () => {
      const h = await api.getHealth();
      if (stop) return;
      // One dropped poll used to null this out, and the next run would quietly
      // simulate instead of calling the API — producing a fake asset that looks
      // real. Only give up after several consecutive misses.
      if (h) { misses = 0; setHealth(h); }
      else if (++misses >= 3) setHealth(null);
    };
    tick();
    const iv = window.setInterval(tick, 15_000);
    return () => { stop = true; window.clearInterval(iv); };
  }, []);

  useEffect(() => { api.listAssets().then((a) => a.length && setAssets(a)); }, [health?.status]);

  /* ---- one engine run --------------------------------------------------- */
  const patchJob = useCallback((p: Partial<Job>) => setJob((j) => (j ? { ...j, ...p } : j)), []);

  /** Drive a real backend job to completion. */
  const runRemote = useCallback(async (
    engine: EngineId, label: string, cfg: GenerationSettings, refs: RefImage[],
  ): Promise<Asset[]> => {
    const { job_id } = await api.submitJob({ ...cfg, engine }, refs);
    for (;;) {
      if (abort.current) throw new Error('cancelled');
      await sleep(900);
      let r;
      try {
        r = await api.getJob(job_id);
      } catch {
        continue; // transient; the worker may be mid-write
      }
      patchJob({ stage: r.stage, progress: r.progress, message: `${label}${r.message}` });
      if (r.stage === 'done') return r.assets ?? [];
      if (r.stage === 'failed') throw new Error(r.error || r.message || 'generation failed');
    }
  }, [patchJob]);

  /** Preview-mode stand-in so the whole UI is drivable with no backend. */
  const runSimulated = useCallback(async (
    engine: EngineId, label: string, cfg: GenerationSettings, refs: RefImage[],
  ): Promise<Asset[]> => {
    const total = engineById(engine).effortSeconds[cfg.effort]
      * (cfg.quality === 'speedy' ? 0.55 : 1) * 1000;
    const steps = STAGES[engine] ?? STAGES['trellis-2'];
    let acc = 0;
    for (const s of steps) {
      const from = acc;
      acc += s.weight * 100;
      for (let k = 1; k <= 6; k++) {
        if (abort.current) throw new Error('cancelled');
        await sleep((total * s.weight) / 6);
        patchJob({ stage: s.stage, message: `${label}${s.message}`, progress: from + ((acc - from) * k) / 6 });
      }
    }
    return Array.from({ length: cfg.batch }).map((_, i) => {
      const faces = Math.round(cfg.targetFaces * (0.82 + Math.random() * 0.3));
      return {
        id: `local-${Date.now()}-${engine}-${i}`,
        name: (cfg.prompt.trim() || refs[0]?.name.replace(/\.[^.]+$/, '') || 'Untitled asset').slice(0, 40),
        prompt: cfg.prompt || `image → 3d · ${refs[0]?.name ?? 'reference'}`,
        engine,
        createdAt: Date.now(),
        thumbUrl: refs[0]?.url,
        seedShape: SHAPES[Math.floor(Math.random() * SHAPES.length)],
        tint: TINTS[Math.floor(Math.random() * TINTS.length)],
        faces,
        vertices: Math.round(faces * 0.52),
        textureRes: cfg.texture ? 2048 : 0,
        fileSizeMb: Math.round((faces / 9000) * 10) / 10,
        liked: false,
        likes: 0,
        author: 'you',
        visibility: cfg.isPrivate ? 'private' : 'public',
        local: true,
        provider: 'preview',
        note: 'Simulated — start the inference server for a real mesh.',
      } satisfies Asset;
    });
  }, [patchJob]);

  /**
   * Try the real backend, and only fall back to the preview simulator when the
   * submit itself fails. Deciding this from cached health meant one stale poll
   * could silently produce a simulated asset that looks like a real one.
   */
  const runEngine = useCallback(async (
    engine: EngineId, label: string, cfg: GenerationSettings, refs: RefImage[],
  ): Promise<Asset[]> => {
    try {
      return await runRemote(engine, label, cfg, refs);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (message === 'cancelled') throw err;
      // a generation that reached the server and failed there is a real failure
      if (!/failed to fetch|networkerror|load failed/i.test(message)) throw err;
      return runSimulated(engine, label, cfg, refs);
    }
  }, [runRemote, runSimulated]);


  /* ---- generate --------------------------------------------------------- */
  /**
   * `settingsOverride`/`imagesOverride` let a caller run against values it just
   * computed. generate() otherwise closes over state, so a caller that patches
   * settings and immediately runs would use the previous prompt.
   */
  const run = useCallback((settingsOverride?: GenerationSettings, imagesOverride?: RefImage[]) => {
    if (running.current) return;
    running.current = true;
    abort.current = false;
    const cfg = settingsOverride ?? settings;
    const refs = imagesOverride ?? images;

    const queue = compareQueue(cfg);
    setJob({
      id: `run-${Date.now()}`,
      engine: queue[0],
      prompt: cfg.prompt,
      stage: 'queued',
      progress: 0,
      message: 'Queued',
      startedAt: Date.now(),
      assetIds: [],
    });

    (async () => {
      const produced: Asset[] = [];
      try {
        for (let i = 0; i < queue.length; i++) {
          const engine = queue[i];
          const label = queue.length > 1 ? `${engineById(engine).label} (${i + 1}/${queue.length}) · ` : '';
          patchJob({ engine, progress: 0, stage: 'queued', message: `${label}Queued` });
          const made = await runEngine(engine, label, cfg, refs);
          produced.push(...made);
        }

        setAssets((prev) => [...produced, ...prev]);
        setShelfTab('asset');
        setCredits((c) => Math.max(0, c - produced.length * 0.5));
        patchJob({
          stage: 'done', progress: 100, message: 'Complete',
          finishedAt: Date.now(), assetIds: produced.map((a) => a.id),
        });

        if (cfg.compare && produced.length > 1) setComparison(produced);
        else if (produced[0]) setActiveAsset(produced[0]);

        setTimeout(() => setJob(null), 1400);
      } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        if (message === 'cancelled') setJob(null);
        else patchJob({ stage: 'failed', message, error: message, finishedAt: Date.now() });
        // keep whatever finished before the failure
        if (produced.length) setAssets((prev) => [...produced, ...prev]);
      } finally {
        running.current = false;
      }
    })();
  }, [settings, images, runEngine, patchJob]);

  const generate = useCallback(() => run(), [run]);

  /**
   * Same pipeline as generate(), but seeded from an asset already on screen:
   * its source image is pulled back in as the reference so the new prompt is
   * applied to the same subject rather than starting from nothing.
   */
  const regenerate = useCallback((asset: Asset, prompt: string) => {
    if (running.current) return;
    // thumbUrl first: it lives on the API, always exists for a generated asset,
    // and is the already-prepped input. sourceRef can point at a gallery file
    // that has since been moved or renamed.
    const candidates = [asset.thumbUrl, asset.sourceRef].filter(Boolean) as string[];
    if (!candidates.length) return;

    const tryNext = async (i: number): Promise<void> => {
      if (i >= candidates.length) {
        setJob({
          id: `run-${Date.now()}`, engine: asset.engine, prompt,
          stage: 'failed', progress: 0,
          message: 'Source image for this asset is missing, so it cannot be re-prompted.',
          error: 'source image unavailable', startedAt: Date.now(), assetIds: [],
        });
        return;
      }
      const src = candidates[i];
      const name = src.split('/').pop() ?? 'reference.png';
      try {
        const abs = api.imageSrc(src)!;
        const res = await fetch(abs);
        const blob = await res.blob();
        if (!res.ok || !blob.type.startsWith('image/')) throw new Error('not an image');
        const file = new File([blob], name, { type: blob.type });
        const ref: RefImage = {
          id: `regen-${Date.now()}`, url: URL.createObjectURL(file), name,
          direction: 'unknown', file, sourceUrl: asset.sourceRef ?? undefined,
        };
        const next: GenerationSettings = {
          ...settings, prompt, engine: asset.engine,
          inputMode: 'image', mode: 'image-to-3d', compare: false, batch: 1,
        };
        // Reflect it in the card too, then run against these exact values rather
        // than waiting for the state patch to land — that race is what produced
        // an "Untitled asset" with an empty prompt.
        setImages((prev) => { prev.forEach((p) => URL.revokeObjectURL(p.url)); return [ref]; });
        setSettings(next);
        run(next, [ref]);
      } catch {
        await tryNext(i + 1);
      }
    };
    void tryNext(0);
  }, [settings, run]);

  const cancel = useCallback(() => { abort.current = true; setJob(null); running.current = false; }, []);
  useEffect(() => () => { abort.current = true; }, []);

  /* ---- assets ----------------------------------------------------------- */
  const toggleLike = useCallback((id: string) => {
    const flip = (a: Asset) => (a.id === id ? { ...a, liked: !a.liked, likes: a.likes + (a.liked ? -1 : 1) } : a);
    setAssets((p) => p.map(flip));
    setExplore((p) => p.map(flip));
    setActiveAsset((p) => (p && p.id === id ? flip(p) : p));
  }, []);

  const removeAsset = useCallback((id: string) => {
    setAssets((p) => p.filter((a) => a.id !== id));
    setActiveAsset((p) => (p && p.id === id ? null : p));
    api.deleteAsset(id).catch(() => {});
  }, []);

  /** The static table is a guess; the server knows the device it will run on. */
  const estimate = useCallback((engine: EngineId, effort: string) => {
    const live = health?.engines?.[engine]?.effortSeconds?.[effort];
    return live ?? engineById(engine).effortSeconds[effort as keyof typeof STAGES extends never ? never : never] ??
      engineById(engine).effortSeconds[effort as 'high'];
  }, [health]);

  const price = useCallback(
    (engine: EngineId) => health?.engines?.[engine]?.pricePerGen ?? 0,
    [health],
  );

  // A compare run bills both engines; a batch bills every result.
  const runCost = useMemo(() => {
    const queue = compareQueue(settings);
    return queue.reduce((sum, e) => sum + price(e) * settings.batch, 0);
  }, [settings, price]);

  const value = useMemo<StudioValue>(() => ({
    settings, patch, images, addImages, addFromUrl, inbox, refreshInbox, removeImage, setDirection, clearImages,
    job, notice, dismissNotice: () => setNotice(null), generate, regenerate, cancel,
    assets, exploreAssets, toggleLike, removeAsset,
    activeAsset, openAsset: setActiveAsset, closeAsset: () => setActiveAsset(null),
    comparison, openComparison: setComparison, closeComparison: () => setComparison(null),
    shelfTab, setShelfTab,
    health, backendOnline: !!health, credits, estimate, price, runCost,
  }), [settings, patch, images, addImages, addFromUrl, inbox, refreshInbox, removeImage, setDirection, clearImages, job, notice, generate, regenerate,
      cancel, assets, exploreAssets, toggleLike, removeAsset, activeAsset, comparison, shelfTab,
      health, credits, estimate, price, runCost]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
};
