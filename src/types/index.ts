export type AIModelType = 'hunyuan3d-2.1' | 'trellis-2.0' | 'hybrid-pipeline';

export interface AIModelInfo {
  id: AIModelType;
  name: string;
  creator: string;
  badge: string;
  tagline: string;
  description: string;
  latencySec: number;
  minVramGb: number;
  outputFormats: string[];
  topologyType: 'Quad Dominant' | 'Triangle Mesh' | 'Gaussian Splat + Mesh';
  textureResolution: '2048x2048' | '4096x4096';
  hfSpaceUrl: string;
}

export type RenderMode = 'pbr' | 'wireframe' | 'normal' | 'roughness' | 'metallic' | 'matcap';

export type LightingPreset = 'studio' | 'cyberpunk' | 'sunset' | 'dawn' | 'dramatic';

export type CharacterStyle = 
  | 'aaa-photorealistic' 
  | 'stylized-anime' 
  | 'cyberpunk' 
  | 'fantasy-rpg' 
  | 'scifi-mech' 
  | 'low-poly';

export interface CharacterPreset {
  id: string;
  title: string;
  style: CharacterStyle;
  prompt: string;
  thumbnail: string;
  modelType: AIModelType;
  polyCount: number;
  textureRes: string;
  geometryColor: string;
  metallic: number;
  roughness: number;
}

export interface GenerationJob {
  id: string;
  prompt: string;
  referenceImage?: string;
  model: AIModelType;
  style: CharacterStyle;
  status: 'idle' | 'generating-multiview' | 'synthesizing-latent' | 'extracting-mesh' | 'baking-pbr' | 'completed' | 'failed';
  progress: number;
  resultMeshUrl?: string;
  createdAt: Date;
}
