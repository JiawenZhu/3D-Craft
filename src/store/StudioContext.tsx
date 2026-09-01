import React, {
  createContext, useCallback, useContext, useEffect, useMemo, useRef, useState,
} from 'react';
import type {
  Asset, EngineId, GenerationSettings, Job, JobStage, RefImage, ShelfTab,
} from '../types';
import { EXPLORE_ASSETS } from '../data/gallery';
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
  removeImage: (id: string) => void;
  setDirection: (id: string, d: RefImage['direction']) => void;
  clearImages: () => void;

  job: Job | null;
  generate: () => void;
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
  const [exploreAssets, setExplore] = useState<Asset[]>(EXPLORE_ASSETS);
  const [activeAsset, setActiveAsset] = useState<Asset | null>(null);
  const [comparison, setComparison] = useState<Asset[] | null>(null);
  const [shelfTab, setShelfTab] = useState<ShelfTab>('explore');
  const [health, setHealth] = useState<api.Health | null>(null);
  const [credits, setCredits] = useState(120);

  const abort = useRef(false);
  const running = useRef(false);

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
    const tick = async () => {
      const h = await api.getHealth();
      if (!stop) setHealth(h);
    };
    tick();
    const iv = window.setInterval(tick, 15_000);
    return () => { stop = true; window.clearInterval(iv); };
  }, []);

  useEffect(() => { api.listAssets().then((a) => a.length && setAssets(a)); }, [health?.status]);

  /* ---- one engine run --------------------------------------------------- */
  const patchJob = useCallback((p: Partial<Job>) => setJob((j) => (j ? { ...j, ...p } : j)), []);

  /** Drive a real backend job to completion. */
  const runRemote = useCallback(async (engine: EngineId, label: string): Promise<Asset[]> => {
    const { job_id } = await api.submitJob({ ...settings, engine }, images);
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
  }, [settings, images, patchJob]);

  /** Preview-mode stand-in so the whole UI is drivable with no backend. */
  const runSimulated = useCallback(async (engine: EngineId, label: string): Promise<Asset[]> => {
    const total = engineById(engine).effortSeconds[settings.effort]
      * (settings.quality === 'speedy' ? 0.55 : 1) * 1000;
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
    return Array.from({ length: settings.batch }).map((_, i) => {
      const faces = Math.round(settings.targetFaces * (0.82 + Math.random() * 0.3));
      return {
        id: `local-${Date.now()}-${engine}-${i}`,
        name: (settings.prompt.trim() || images[0]?.name.replace(/\.[^.]+$/, '') || 'Untitled asset').slice(0, 40),
        prompt: settings.prompt || `image → 3d · ${images[0]?.name ?? 'reference'}`,
        engine,
        createdAt: Date.now(),
        thumbUrl: images[0]?.url,
        seedShape: SHAPES[Math.floor(Math.random() * SHAPES.length)],
        tint: TINTS[Math.floor(Math.random() * TINTS.length)],
        faces,
        vertices: Math.round(faces * 0.52),
        textureRes: settings.texture ? 2048 : 0,
        fileSizeMb: Math.round((faces / 9000) * 10) / 10,
        liked: false,
        likes: 0,
        author: 'you',
        visibility: settings.isPrivate ? 'private' : 'public',
        local: true,
        provider: 'preview',
        note: 'Simulated — start the inference server for a real mesh.',
      } satisfies Asset;
    });
  }, [settings, images, patchJob]);

  /* ---- generate --------------------------------------------------------- */
  const generate = useCallback(() => {
    if (running.current) return;
    running.current = true;
    abort.current = false;

    const queue = compareQueue(settings);
    setJob({
      id: `run-${Date.now()}`,
      engine: queue[0],
      prompt: settings.prompt,
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
          const made = health ? await runRemote(engine, label) : await runSimulated(engine, label);
          produced.push(...made);
        }

        setAssets((prev) => [...produced, ...prev]);
        setShelfTab('asset');
        setCredits((c) => Math.max(0, c - produced.length * 0.5));
        patchJob({
          stage: 'done', progress: 100, message: 'Complete',
          finishedAt: Date.now(), assetIds: produced.map((a) => a.id),
        });

        if (settings.compare && produced.length > 1) setComparison(produced);
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
  }, [settings, health, runRemote, runSimulated, patchJob]);

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
    settings, patch, images, addImages, removeImage, setDirection, clearImages,
    job, generate, cancel,
    assets, exploreAssets, toggleLike, removeAsset,
    activeAsset, openAsset: setActiveAsset, closeAsset: () => setActiveAsset(null),
    comparison, openComparison: setComparison, closeComparison: () => setComparison(null),
    shelfTab, setShelfTab,
    health, backendOnline: !!health, credits, estimate, price, runCost,
  }), [settings, patch, images, addImages, removeImage, setDirection, clearImages, job, generate,
      cancel, assets, exploreAssets, toggleLike, removeAsset, activeAsset, comparison, shelfTab,
      health, credits, estimate, price, runCost]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
};
