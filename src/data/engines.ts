import type { Engine, EngineId } from '../types';

export const ENGINES: Engine[] = [
  {
    id: 'hunyuan3d-2.1',
    label: 'Hunyuan3D-2.1',
    release: 'Hunyuan3D-2.1 (PBR)',
    vendor: 'Tencent',
    blurb:
      'Shape diffusion plus PBR texture synthesis. Its shape stage is the only part of either engine that runs natively off CUDA.',
    spaceUrl: 'https://huggingface.co/spaces/tencent/Hunyuan3D-2.1',
    repoUrl: 'https://github.com/Tencent-Hunyuan/Hunyuan3D-2.1',
    effortSeconds: { 'extreme-low': 12, low: 24, medium: 45, high: 90, 'extreme-high': 170 },
    supports: { textToImage: false, multiView: true, pbr: true, gaussianSplat: false, quadRemesh: true },
    outputs: ['GLB', 'OBJ', 'PLY', 'STL'],
    vramGb: 10,
  },
  {
    id: 'trellis-2',
    label: 'TRELLIS.2',
    release: 'TRELLIS.2 (SLAT)',
    vendor: 'Microsoft',
    blurb:
      'Structured LATents: one latent decodes to a radiance field, 3D Gaussians and a mesh. Fast and multi-image native, but CUDA-only.',
    spaceUrl: 'https://huggingface.co/spaces/microsoft/TRELLIS.2',
    repoUrl: 'https://github.com/microsoft/TRELLIS',
    effortSeconds: { 'extreme-low': 6, low: 11, medium: 20, high: 38, 'extreme-high': 75 },
    supports: { textToImage: false, multiView: true, pbr: false, gaussianSplat: true, quadRemesh: true },
    outputs: ['GLB', 'PLY (splat)', 'OBJ'],
    vramGb: 16,
  },
  {
    id: 'rodin',
    label: 'Rodin Gen-2',
    release: 'Hyper3D Rodin (API)',
    vendor: 'Deemos',
    blurb:
      'The commercial model this workspace is modelled on. No open release — API only, via fal.',
    spaceUrl: 'https://hyper3d.ai/workspace/rodin',
    repoUrl: 'https://fal.ai/models/fal-ai/hyper3d/rodin',
    effortSeconds: { 'extreme-low': 15, low: 25, medium: 40, high: 70, 'extreme-high': 70 },
    supports: { textToImage: true, multiView: true, pbr: true, gaussianSplat: false, quadRemesh: true },
    outputs: ['GLB', 'USDZ', 'FBX', 'OBJ', 'STL'],
    vramGb: 0,
  },
  {
    id: 'hybrid',
    label: 'Hybrid',
    release: 'TRELLIS geometry → Hunyuan texture',
    vendor: 'Local pipeline',
    blurb:
      'Runs TRELLIS.2 for structure, then hands the mesh to Hunyuan3D-2.1 Paint for PBR maps. Slowest, sharpest.',
    spaceUrl: 'https://huggingface.co/spaces/tencent/Hunyuan3D-2.1',
    repoUrl: 'https://github.com/microsoft/TRELLIS',
    effortSeconds: { 'extreme-low': 18, low: 34, medium: 62, high: 120, 'extreme-high': 220 },
    supports: { textToImage: false, multiView: true, pbr: true, gaussianSplat: true, quadRemesh: true },
    outputs: ['GLB', 'PLY (splat)', 'OBJ', 'FBX'],
    vramGb: 24,
  },
];

export const engineById = (id: EngineId): Engine =>
  ENGINES.find((e) => e.id === id) ?? ENGINES[0];

export const EFFORTS = [
  { id: 'extreme-low', label: 'Extreme-Low', steps: 8 },
  { id: 'low', label: 'Low', steps: 16 },
  { id: 'medium', label: 'Medium', steps: 30 },
  { id: 'high', label: 'High', steps: 50 },
  { id: 'extreme-high', label: 'Extreme-High', steps: 75 },
] as const;

export const TIPS = [
  'Redos are free — nothing is charged until you confirm.',
  'TRELLIS.2 is multi-image native: drop 2–4 views for a much cleaner back side.',
  'Hunyuan3D-2.1 is the only one of the two with real PBR texture output.',
  'Need ultra-fast results? Drop the effort to Extreme-Low.',
  'RGBA image? The alpha channel is used as the mask automatically.',
  'Specify image directions via the direction bar to improve accuracy.',
  'Want clean, sharp surfaces without distractions? Use Zero mode.',
  'Both engines run entirely on this machine — nothing leaves your GPU.',
  'Hybrid pipes TRELLIS geometry into Hunyuan Paint for the sharpest result.',
  'Quad remesh gives you animation-friendly topology at export time.',
];
