import { AIModelInfo } from '../types';

export const SUPPORTED_MODELS: AIModelInfo[] = [
  {
    id: 'hunyuan3d-2.1',
    name: 'Tencent Hunyuan3D 2.1',
    creator: 'Tencent Games & AI Lab',
    badge: 'High-Res Textures',
    tagline: 'State-of-the-art text/image to 3D with ultra-crisp PBR texture baking and balanced topology.',
    description: 'Hunyuan3D-2.1 combines a multi-view diffusion generative prior with high-resolution neural mesh synthesis, producing production-ready 3D game assets with 4K albedo, normal, and roughness maps.',
    latencySec: 35,
    minVramGb: 12,
    outputFormats: ['GLB', 'OBJ', 'FBX', 'USDZ'],
    topologyType: 'Quad Dominant',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://huggingface.co/spaces/tencent/Hunyuan3D-2.1'
  },
  {
    id: 'trellis-2.0',
    name: 'Microsoft TRELLIS.2',
    creator: 'Microsoft Research',
    badge: 'Structured Latents',
    tagline: 'Structured 3D Latents (SLaD) producing dual 3D Gaussian Splats + high-detail Quad Meshes.',
    description: 'TRELLIS transforms 2D images directly into unified 3D representations (Gaussian Splats, Radiance Fields, and clean meshes) with micro-geometry surface details and seamless materials in under 20 seconds.',
    latencySec: 18,
    minVramGb: 16,
    outputFormats: ['GLB', 'PLY (Gaussian Splat)', 'OBJ', 'USDZ'],
    topologyType: 'Gaussian Splat + Mesh',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://huggingface.co/spaces/microsoft/TRELLIS.2'
  },
  {
    id: 'hybrid-pipeline',
    name: 'Rodin Hybrid Engine',
    creator: 'Rodin 3D Studio Architecture',
    badge: 'Dual-Pass Ultra',
    tagline: 'Combines TRELLIS fast geometry synthesis with Hunyuan3D multi-view PBR texture baking.',
    description: 'The ultimate dual-pass pipeline: uses TRELLIS for sub-20s structural latent generation followed by Hunyuan3D-2.1 neural refinement for 4K ray-traced materials.',
    latencySec: 45,
    minVramGb: 24,
    outputFormats: ['GLB', 'OBJ', 'FBX', 'USDZ', 'PLY'],
    topologyType: 'Quad Dominant',
    textureResolution: '4096x4096',
    hfSpaceUrl: 'https://hyper3d.ai/workspace/rodin'
  }
];
