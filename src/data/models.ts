import { AIModelInfo } from '../types';

export const SUPPORTED_MODELS: AIModelInfo[] = [
  {
    id: 'hybrid-pipeline',
    name: 'Rodin Gen-2 Dual-Pass',
    creator: 'Deemos Tech & Rodin Architecture',
    badge: 'Flagship Gen-2',
    tagline: 'Dual-Pass Engine: TRELLIS.2 structural latent geometry + Hunyuan3D-2.1 4K PBR neural baking.',
    description: 'The premier production pipeline for Hyper3D Rodin. Generates clean quad-dominant topologies and photorealistic 4K PBR texture maps (Albedo, Normal, Roughness, Metallic, AO) in under 35 seconds.',
    latencySec: 32,
    minVramGb: 16,
    outputFormats: ['GLB', 'FBX (Rigged)', 'OBJ', 'USDZ', 'STL', 'PLY (Splats)'],
    topologyType: 'Quad Dominant',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://hyper3d.ai/workspace/rodin'
  },
  {
    id: 'trellis-2.0',
    name: 'Microsoft TRELLIS.2',
    creator: 'Microsoft Research',
    badge: 'Structured Latents (SLaD)',
    tagline: 'Sub-20s ultra-fast generation of 3D Gaussian Splats + crisp quad meshes with micro-surface details.',
    description: 'Direct 2D-to-3D Structured Latent Diffusion (SLaD) producing dual representations: instant 3D Gaussian Splats and watertight quad meshes with clean hard-surface edges.',
    latencySec: 18,
    minVramGb: 16,
    outputFormats: ['GLB', 'PLY (Gaussian Splats)', 'OBJ', 'USDZ'],
    topologyType: 'Gaussian Splat + Mesh',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://huggingface.co/spaces/microsoft/TRELLIS.2'
  },
  {
    id: 'hunyuan3d-2.1',
    name: 'Tencent Hunyuan3D 2.1',
    creator: 'Tencent Games & AI Lab',
    badge: '4K PBR Texture Master',
    tagline: 'Multi-view diffusion prior with deep neural texture synthesis and balanced game character topology.',
    description: 'Hunyuan3D-2.1 employs multi-view orthogonal diffusion priors to bake high-fidelity ray-traced materials with non-overlapping UVs and sub-surface scattering approximations.',
    latencySec: 28,
    minVramGb: 12,
    outputFormats: ['GLB', 'OBJ', 'FBX', 'USDZ'],
    topologyType: 'Quad Dominant',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://huggingface.co/spaces/tencent/Hunyuan3D-2.1'
  }
];
