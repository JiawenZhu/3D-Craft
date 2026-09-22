import { compatibleGameIds, type CustomGameAsset, type GameAssetKind } from './gameAssetRules';

export type NativeGameLaunch = { game: string; locale: 'en' | 'zh'; asset: CustomGameAsset };

const isAllowedPageHost = (host: string) =>
  ['localhost', '127.0.0.1', '[::1]', '3d-craft.web.app', '3d-craft.firebaseapp.com', 'forma-studio-2026.web.app', 'forma-studio-2026.firebaseapp.com'].includes(host) ||
  host.endsWith('.web.app') ||
  host.endsWith('.firebaseapp.com');

const isAllowedAssetHost = (host: string) =>
  isAllowedPageHost(host) ||
  ['firebasestorage.googleapis.com', 'storage.googleapis.com'].includes(host) ||
  host.endsWith('.googleapis.com');

/** Local review and cloud production native game launch bridge. */
export function decodeNativeGameLaunch(fragment: string, pageOrigin: string): NativeGameLaunch {
  const page = new URL(pageOrigin);
  if (!isAllowedPageHost(page.hostname) || !['http:', 'https:'].includes(page.protocol)) {
    throw new Error('Native game preview is not available on this origin.');
  }
  if (fragment.length > 24000) throw new Error('The game request is too large.');
  let payload: any;
  try {
    payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(fragment.replace(/^#/, '')), c => c.charCodeAt(0))));
  } catch {
    throw new Error('The game request could not be read. Return to your model and try again.');
  }

  const parseURL = (raw: unknown, model: boolean) => {
    if (typeof raw !== 'string' || raw.length > 8192) throw new Error('The asset link is missing.');
    const url = new URL(raw, pageOrigin);
    if (!isAllowedAssetHost(url.hostname) || url.username || url.password || !['http:', 'https:'].includes(url.protocol)) {
      throw new Error('Asset host is not allowed.');
    }
    return url.href;
  };

  const asset = payload?.asset;
  const kind = asset?.kind as GameAssetKind;
  if (payload?.version !== 1 || !['vehicle', 'character', 'flying'].includes(kind)) throw new Error('Choose a supported model type.');
  if (typeof payload.game !== 'string' || !compatibleGameIds(kind).includes(payload.game)) throw new Error('Choose a game compatible with this model.');
  if (typeof asset.id !== 'string' || !asset.id || asset.id.length > 200 || typeof asset.name !== 'string' || !asset.name || asset.name.length > 200) throw new Error('The selected asset is invalid.');
  if (![0, 90, 180, 270].includes(asset.yaw)) throw new Error('The model direction is invalid.');
  return {
    game: payload.game,
    locale: payload.locale === 'zh' ? 'zh' : 'en',
    asset: {
      id: asset.id,
      name: asset.name,
      kind,
      yaw: asset.yaw,
      url: parseURL(asset.url, true),
      ...(asset.thumbUrl ? { thumbUrl: parseURL(asset.thumbUrl, false) } : {}),
    }
  };
}

