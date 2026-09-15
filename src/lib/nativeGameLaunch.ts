import { compatibleGameIds, type CustomGameAsset, type GameAssetKind } from './gameAssetRules';

export type NativeGameLaunch = { game: string; locale: 'en' | 'zh'; asset: CustomGameAsset };
const loopback = (host: string) => ['localhost', '127.0.0.1', '[::1]'].includes(host);

/** Local simulator review only. No credentials or remote download URLs enter this bridge. */
export function decodeNativeGameLaunch(fragment: string, pageOrigin: string): NativeGameLaunch {
  const page = new URL(pageOrigin);
  if (!loopback(page.hostname) || !['http:', 'https:'].includes(page.protocol)) throw new Error('Native game preview is only available on the local review server.');
  if (fragment.length > 12000) throw new Error('The game request is too large.');
  let payload: any;
  try { payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(fragment.replace(/^#/, '')), c => c.charCodeAt(0)))); }
  catch { throw new Error('The game request could not be read. Return to your model and try again.'); }
  const localURL = (raw: unknown, model: boolean) => {
    if (typeof raw !== 'string' || raw.length > 4096) throw new Error('The asset link is missing.');
    const url = new URL(raw);
    if (!loopback(url.hostname) || url.username || url.password || !['http:', 'https:'].includes(url.protocol)
      || ![page.port, '8000', '8001'].includes(url.port) || url.search || url.hash) throw new Error('Only local workspace assets can enter this preview.');
    if (model ? !/^\/(models|files)\/.+\.glb$/i.test(url.pathname) : !/^\/(images|files)\//.test(url.pathname)) throw new Error('This asset path is not supported.');
    return url.href;
  };
  const asset = payload?.asset;
  const kind = asset?.kind as GameAssetKind;
  if (payload?.version !== 1 || !['vehicle', 'character', 'flying'].includes(kind)) throw new Error('Choose a supported model type.');
  if (typeof payload.game !== 'string' || !compatibleGameIds(kind).includes(payload.game)) throw new Error('Choose a game compatible with this model.');
  if (typeof asset.id !== 'string' || !asset.id || asset.id.length > 200 || typeof asset.name !== 'string' || !asset.name || asset.name.length > 200) throw new Error('The selected asset is invalid.');
  if (![0, 90, 180, 270].includes(asset.yaw)) throw new Error('The model direction is invalid.');
  return { game: payload.game, locale: payload.locale === 'zh' ? 'zh' : 'en', asset: {
    id: asset.id, name: asset.name, kind, yaw: asset.yaw,
    url: localURL(asset.url, true),
    ...(asset.thumbUrl ? { thumbUrl: localURL(asset.thumbUrl, false) } : {}),
  } };
}
