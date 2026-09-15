import type { PricingCatalog } from './api';
import type { EngineId } from '../types';

export const usd = (amount: number | null | undefined) =>
  amount == null || !Number.isFinite(amount) ? 'Price pending' : `$${amount.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 6 })}`;

/** Match the hosted reconstruction route, without guessing unknown add-ons. */
export function generationPrice(catalog: PricingCatalog | null, engine: EngineId, texture: boolean, inputs: number, effort = 'high'): number | null {
  if (!catalog) return null;
  if (engine === 'hybrid') {
    const shape = generationPrice(catalog, 'trellis-2', texture, inputs, effort);
    if (!texture) return shape;
    const paint = generationPrice(catalog, 'hunyuan3d-2.1', true, inputs, effort);
    return shape === null || paint === null ? null : shape + paint;
  }
  const rate = catalog.models[engine];
  if (!rate) return null;
  if (inputs > 1 && engine !== 'rodin') {
    return (texture && engine === 'hunyuan3d-2.1' ? rate.multiTexturedUsd : rate.multiUnitUsd) ?? null;
  }
  if (inputs === 1) {
    const effortPrice = (texture ? rate.effortTexturedUsd : rate.effortUsd)?.[effort];
    if (effortPrice != null) return effortPrice;
  }
  return (texture ? rate.texturedUsd ?? rate.unitUsd : rate.unitUsd) ?? null;
}
