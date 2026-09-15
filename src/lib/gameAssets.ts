import type { Asset } from '../types';
import { API_BASE } from './api';
import { prepareGameAssetWithBases, type GameAssetKind } from './gameAssetRules';
export { compatibleGameIds, suggestGameAssetKind } from './gameAssetRules';
export type { CustomGameAsset, GameAssetKind } from './gameAssetRules';
export function prepareGameAsset(asset: Asset, kind: GameAssetKind, yaw: number) {
  return prepareGameAssetWithBases(asset, kind, yaw, window.location.origin, API_BASE);
}
