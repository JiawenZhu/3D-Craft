import type { Asset } from '../types';

export type GameAssetKind = 'vehicle' | 'character' | 'flying';
export type CustomGameAsset = {
  id: string;
  name: string;
  url: string;
  kind: GameAssetKind;
  /** User-selected correction for a model whose front does not face +Z. */
  yaw: number;
  thumbUrl?: string;
};

const modes: Record<GameAssetKind, readonly string[]> = {
  vehicle: ['arena', 'race'],
  character: ['survivor', 'ruins'],
  flying: ['dragon', 'survivor', 'ruins'],
};
export const compatibleGameIds = (kind: GameAssetKind) => modes[kind];

/** A suggestion, never an unchangeable classification of the user's creation. */
export function suggestGameAssetKind(asset: Asset): GameAssetKind {
  const name = asset.name.toLowerCase();
  if (asset.seedShape === 'vehicle' || /\b(car|truck|van|camper|taxi|bus|buggy|kart|vehicle)\b|汽车|赛车|小车|卡车|战车|露营车/.test(name)) return 'vehicle';
  if (/\b(dragon|bird|phoenix|griffin|pegasus|bat)\b|飞龙|幼龙|凤凰|飞鸟/.test(name)) return 'flying';
  return 'character';
}

export function resolveGameAssetUrl(raw: string, pageOrigin: string, apiBase: string): string {
  const value = raw.trim();
  if (!value || value.startsWith('//') || value.includes('\\')) throw new Error('This model does not have a supported download link.');
  const base = value.startsWith('/models/') || value.startsWith('/images/') ? pageOrigin : apiBase;
  const resolvedBase = new URL(base, pageOrigin).href;
  const url = new URL(value.startsWith('/') ? value.slice(1) : value, resolvedBase.replace(/\/$/, '') + '/');
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('This model does not have a supported download link.');
  url.hash = '';
  return url.href;
}

export function prepareGameAssetWithBases(asset: Asset, kind: GameAssetKind, yaw: number, pageOrigin: string, apiBase: string): CustomGameAsset {
  if (!asset.modelUrl) throw new Error('Generate a 3D model before playing.');
  if (!Object.prototype.hasOwnProperty.call(modes, kind)) throw new Error('Choose a supported character type.');
  if (!Number.isFinite(yaw) || yaw % 90 !== 0) throw new Error('Choose a valid model direction.');
  if (asset.fileSizeMb > 100) throw new Error('This model is too large for the game. Export a GLB under 100 MB.');
  let thumbUrl: string | undefined;
  if (asset.thumbUrl) {
    try { thumbUrl = resolveGameAssetUrl(asset.thumbUrl, pageOrigin, apiBase); } catch { /* Missing preview does not block the model. */ }
  }
  return {
    id: asset.id,
    name: asset.name,
    url: resolveGameAssetUrl(asset.modelUrl, pageOrigin, apiBase),
    kind,
    yaw: ((yaw % 360) + 360) % 360,
    thumbUrl,
  };
}
