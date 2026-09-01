export type AIModelType = 'hunyuan3d-2.1' | 'trellis-2.0' | 'hybrid-pipeline';

export type GenerationSpeed = 'speedy' | 'default' | 'extreme-4k';

export type GenerationInputMode = 'text' | 'image' | 'multiview';

export interface MultiViewImages {
  front?: string;
  left?: string;
  right?: string;
  back?: string;
  top?: string;
}

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

export type RenderMode = 
  | 'pbr' 
  | 'wireframe' 
  | 'wire-on-shaded'
  | 'normal' 
  | 'roughness' 
  | 'metallic' 
  | 'matcap'
  | 'ao'
  | 'splats';

export type LightingPreset = 'studio' | 'cyberpunk' | 'sunset' | 'dawn' | 'dramatic' | 'neutral-hdri';

export type CameraOrientation = 'free' | 'front' | 'back' | 'left' | 'right' | 'top' | 'isometric';

export type CharacterStyle = 
  | 'aaa-photorealistic' 
  | 'stylized-anime' 
  | 'cyberpunk' 
  | 'fantasy-rpg' 
  | 'scifi-mech' 
  | 'clay-sculpt'
  | 'figurine-chibi'
  | 'low-poly';

export interface CharacterPreset {
  id: string;
  title: string;
  style: CharacterStyle;
  prompt: string;
  thumbnail: string;
  modelType: AIModelType;
  polyCount: number;
  vertexCount: number;
  textureRes: string;
  geometryColor: string;
  metallic: number;
  roughness: number;
  emissiveIntensity?: number;
  hasBones?: boolean;
  segments?: string[];
  glbUrl?: string;
}

export type OmniCraftTab = 'omnicraft' | 'materials' | 'gallery' | 'rigging';

export type MeshSegment = 'all' | 'head' | 'torso' | 'arms' | 'legs' | 'weapon' | 'accessories';

export type AnimationPose = 't-pose' | 'idle' | 'walk' | 'combat' | 'victory';

export interface GenerationJob {
  id: string;
  prompt: string;
  referenceImage?: string;
  multiViewImages?: MultiViewImages;
  model: AIModelType;
  style: CharacterStyle;
  speed: GenerationSpeed;
  seed: number;
  symmetry: boolean;
  textureRes: '2048x2048' | '4096x4096';
  targetPolyBudget: number;
  status: 'idle' | 'generating-multiview' | 'synthesizing-latent' | 'extracting-mesh' | 'baking-pbr' | 'completed' | 'failed';
  progress: number;
  resultMeshUrl?: string;
  createdAt: Date;
}
