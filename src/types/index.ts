/* ---------------------------------------------------------------------------
 * Domain model for the local Rodin studio.
 * Mirrors the vocabulary of hyper3d.ai/workspace/rodin, but every knob maps to
 * a real parameter on one of the two local engines.
 * ------------------------------------------------------------------------- */

export type EngineId = 'hunyuan3d-2.1' | 'trellis-2' | 'rodin' | 'hybrid';

export interface Engine {
  id: EngineId;
  /** Shown in the ‹ Gen-2.5 › style switcher. */
  label: string;
  /** Marketing-ish subtitle rendered under the wordmark. */
  release: string;
  vendor: string;
  blurb: string;
  spaceUrl: string;
  repoUrl: string;
  /** Rough seconds per effort tier, used for the "~ 40s" hints. */
  effortSeconds: Record<EffortId, number>;
  supports: {
    textToImage: boolean;
    multiView: boolean;
    pbr: boolean;
    gaussianSplat: boolean;
    quadRemesh: boolean;
  };
  outputs: string[];
  vramGb: number;
}

export type WorkMode = 'image-to-3d' | '3d-editing' | 'worldgen';
export type InputMode = 'image' | 'text';
export type ImageMode = 'single' | 'multi';

export type EffortId = 'extreme-low' | 'low' | 'medium' | 'high' | 'extreme-high';
export type QualityMode = 'default' | 'speedy';
export type CreationMode = 'build-myself' | 'ai-assist' | 'full-ai';

/** Rodin's surface-style toggles on the right icon rail. */
export type GeoMode = 'sharp' | 'smooth' | 'zero' | 'focal';
export type PoseMode = 'none' | 't-pose' | 'a-pose';

export type Direction =
  | 'unknown' | 'front' | 'front-left' | 'front-right' | 'left' | 'right'
  | 'back' | 'back-left' | 'back-right' | 'up' | 'down';

export interface RefImage {
  id: string;
  /** object URL for preview */
  url: string;
  name: string;
  direction: Direction;
  file?: File;
  /** Inbox path this came from, so the result can be traced back to it. */
  sourceUrl?: string;
}

export interface GenerationSettings {
  engine: EngineId;
  mode: WorkMode;
  inputMode: InputMode;
  imageMode: ImageMode;
  prompt: string;
  negativePrompt: string;
  effort: EffortId;
  quality: QualityMode;
  creation: CreationMode;
  geoMode: GeoMode;
  poseMode: PoseMode;
  batch: number;
  seed: number | null;
  /** Hunyuan/TRELLIS shared samplers. */
  guidance: number;
  steps: number;
  /** Target face count for the extracted mesh. */
  targetFaces: number;
  texture: boolean;
  quadRemesh: boolean;
  removeBackground: boolean;
  isPrivate: boolean;
  /** Run the same input through two engines and show them side by side. */
  compare: boolean;
  /** The engine `compare` runs against the selected one. */
  compareWith: EngineId;
}

export type JobStage =
  | 'queued'
  | 'preprocessing'
  | 'multiview'
  | 'sparse-structure'
  | 'latent'
  | 'mesh'
  | 'texture'
  | 'packaging'
  | 'done'
  | 'failed';

export interface Job {
  id: string;
  engine: EngineId;
  prompt: string;
  stage: JobStage;
  progress: number;
  message: string;
  startedAt: number;
  finishedAt?: number;
  error?: string;
  assetIds: string[];
}

export interface Asset {
  id: string;
  name: string;
  prompt: string;
  engine: EngineId;
  createdAt: number;
  /** Server-relative or absolute URL to a .glb */
  modelUrl?: string;
  /** Optional gaussian splat (.ply) when TRELLIS produced one. */
  splatUrl?: string;
  thumbUrl?: string;
  /** Procedural stand-in used before/without a real mesh. */
  seedShape: 'figure' | 'mech' | 'creature' | 'prop' | 'vehicle';
  tint: string;
  faces: number;
  vertices: number;
  textureRes: number;
  fileSizeMb: number;
  liked: boolean;
  likes: number;
  author: string;
  visibility: 'public' | 'private';
  local: boolean;
  /** Which backend produced it: "local", "space", or a hybrid pair. */
  provider?: string;
  /** Free-text engine note, e.g. which Space endpoint ran. */
  note?: string;
  /** A starting point handed over by the image side — no mesh yet. */
  isReference?: boolean;
  /** Inbox path this asset was generated from, if any. */
  sourceRef?: string;
  /** Measured server-side from the GLB, so the panel fills instantly. */
  meshes?: number;
  materials?: number;
  dimensions?: [number, number, number];
}

export type ShelfTab = 'asset' | 'explore';
export type ViewportShading = 'material' | 'solid' | 'wireframe' | 'normal' | 'uv' | 'splat';
export type StudioLight = 'studio' | 'rim' | 'sunset' | 'night' | 'flat';

/** Live light intensities, layered on top of whichever preset is selected. */
export interface LightTrim {
  directional: number;
  ambient: number;
  environment: number;
  exposure: number;
}

/** What the viewport can report back about the mesh it loaded. */
export interface ModelStats {
  triangles: number;
  vertices: number;
  meshes: number;
  materials: number;
  /** width x height x depth in model units */
  dimensions: [number, number, number];
}
