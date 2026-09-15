/* ---------------------------------------------------------------------------
 * Domain model for the local Rodin studio.
 * Mirrors the vocabulary of hyper3d.ai/workspace/rodin, but every knob maps to
 * a real parameter on one of the two local engines.
 * ------------------------------------------------------------------------- */

export type EngineId = 'hunyuan3d-2.1' | 'hunyuan3d-2-white' | 'trellis-2' | 'rodin' | 'hybrid';

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
  ownerId?: string;
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
  /** The concept run that produced it, when it came through the pipeline. */
  runId?: string;
  /**
   * The gallery image the whole thing started from.
   *
   * Distinct from sourceRef: a pipeline mesh is reconstructed from the CONCEPT,
   * so sourceRef points at that. This is the picture the user actually picked,
   * and it is what stops that picture showing in EXPLORE as unbuilt next to the
   * mesh it produced.
   */
  originRef?: string;
  /** How many assets share this one's project key. Derived for the gallery. */
  versions?: number;
  /** Measured server-side from the GLB, so the panel fills instantly. */
  meshes?: number;
  materials?: number;
  dimensions?: [number, number, number];
}

export type ShelfTab = 'asset' | 'explore' | 'game';
export type ViewportShading = 'material' | 'solid' | 'wireframe' | 'normal' | 'uv' | 'splat';
export type StudioLight = 'studio' | 'rim' | 'sunset' | 'night' | 'flat';

/**
 * Live light intensities, layered on top of whichever preset is selected.
 *
 * There is deliberately no ambient control. Measured against these PBR
 * materials, neither an AmbientLight nor a HemisphereLight moved average
 * luminance at any intensity (48.17 -> 48.16 across a 0-3x sweep), so the
 * slider was inert. The hemisphere light stays in the rig at its preset value;
 * only the dead control is gone.
 */
export interface LightTrim {
  directional: number;
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


/* ---------------------------------------------------------------------------
 * The concept pipeline: photo + words -> written prompt -> render -> mesh.
 *
 * These mirror server/pipelines.py exactly, and both mirror the Firestore
 * documents described in docs/FIREBASE.md. One shape, three places — so moving
 * the store from disk to Firestore is a change of transport, not of model.
 * ------------------------------------------------------------------------- */

export type PipelineStage = 'source' | 'prompt' | 'concept' | 'model3d';
export type NodeStatus = 'pending' | 'running' | 'done' | 'failed';

export interface PipelineNode {
  id: string;
  kind: PipelineStage;
  label: string;
  status: NodeStatus;
  startedAt: number | null;
  finishedAt: number | null;
  error: string | null;

  /** source: the user's words. prompt: what Gemini wrote. */
  text?: string;
  /** source / concept: the image this node holds. */
  imageUrl?: string;
  /** concept: candidate variations in the concept set. */
  images?: { url: string; label: string; isOriginal?: boolean; direction?: Direction }[];
  reconstructionMode?: 'single' | 'multi';
  warnings?: string[];
  validation?: { usable: boolean; issues: string[] };
  /** prompt: the plain subject line handed to the 3D engine. */
  subject?: string;
  /** prompt: one line from Gemini about the call it made. */
  notes?: string;
  /** prompt: the extracted core action/motion/essence of the subject. */
  coreConcept?: string;
  /** prompt: evaluation of image quality and suitability for direct 3D. */
  imageAssessment?: string;
  /** Which model ran, and how long it took. */
  model?: string;
  ms?: number;
  sizeKb?: number;

  /** model3d: live job state while the mesh is being built. */
  jobId?: string;
  progress?: number;
  message?: string;
  stage?: JobStage;
  assetId?: string;
  modelUrl?: string;
  thumbUrl?: string;
  faces?: number;
  provider?: string;
}

export interface PipelineRun {
  id: string;
  ownerId: string;
  title: string;
  status: 'running' | 'done' | 'failed';
  createdAt: number;
  updatedAt: number;
  input: { prompt: string; imageUrl: string | null; sourceRef: string | null };
  settings: Record<string, unknown>;
  nodes: PipelineNode[];
  assetId: string | null;
  error: string | null;
}

/** The denormalised row behind the run-history strip. */
export interface PipelineSummary {
  id: string;
  title: string;
  status: PipelineRun['status'];
  createdAt: number;
  updatedAt: number;
  conceptUrl?: string;
  sourceUrl?: string;
  assetId?: string | null;
}

export interface ConceptImage {
  direction?: Direction;
  id: string;
  url: string;
  label: string;
  isOriginal?: boolean;
}

export interface ConceptSetResult {
  id: string;
  title: string;
  subject: string;
  core_concept?: string;
  image_assessment?: string;
  prompt: string;
  notes: string;
  images: ConceptImage[];
  warnings?: string[];
  validation?: { usable: boolean; issues: string[] };
  total_ms: number;
}
