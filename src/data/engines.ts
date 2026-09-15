import type { Engine, EngineId } from '../types';

export const ENGINES: Engine[] = [
  {
    id: 'hunyuan3d-2.1',
    label: 'Hunyuan3D 2',
    release: 'Hunyuan3D 2 · textured',
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
    id: 'hunyuan3d-2-white', label: 'Hunyuan 2 · White mesh',
    release: 'Hunyuan 3D 2 · Shape only', vendor: 'Tencent',
    blurb: 'Geometry without color or texture. Supports one image or front, back and left views of the same object.',
    spaceUrl: 'https://fal.ai/models/fal-ai/hunyuan3d/v2',
    repoUrl: 'https://github.com/Tencent-Hunyuan/Hunyuan3D-2',
    effortSeconds: { 'extreme-low': 12, low: 24, medium: 45, high: 90, 'extreme-high': 170 },
    supports: { textToImage: false, multiView: true, pbr: false, gaussianSplat: false, quadRemesh: true },
    outputs: ['GLB'], vramGb: 10,
  },
  {
    id: 'trellis-2',
    label: 'TRELLIS.2',
    release: 'TRELLIS.2',
    vendor: 'Microsoft',
    blurb:
      'Provider-dependent: fal uses TRELLIS.2 with single or multi-image input; the hosted TRELLIS.2 Space accepts a single image. Check the provider endpoint for the actual version.',
    spaceUrl: 'https://huggingface.co/spaces/microsoft/TRELLIS.2',
    repoUrl: 'https://github.com/microsoft/TRELLIS',
    effortSeconds: { 'extreme-low': 6, low: 11, medium: 20, high: 38, 'extreme-high': 75 },
    supports: { textToImage: false, multiView: true, pbr: false, gaussianSplat: true, quadRemesh: true },
    outputs: ['GLB', 'PLY (splat)', 'OBJ'],
    vramGb: 16,
  },
  {
    id: 'rodin',
    label: 'Rodin (Ultra)',
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
  'Re-running a stage creates a new provider request and may incur a charge.',
  'TRELLIS on fal accepts multiple consistent views. Conflicting views can reduce fidelity.',
  'Compare the texture and gray model separately to locate shape and material defects.',
  'Need ultra-fast results? Drop the effort to Extreme-Low.',
  'RGBA image? The alpha channel is used as the mask automatically.',
  'Specify image directions via the direction bar to improve accuracy.',
  'Want clean, sharp surfaces without distractions? Use Zero mode.',
  'Remote providers process your reference images. Check the active provider in the status menu.',
  'Review the silhouette from the back and sides before exporting your asset.',
  'Inspect topology and materials in your game engine before rigging or shipping.',
];
