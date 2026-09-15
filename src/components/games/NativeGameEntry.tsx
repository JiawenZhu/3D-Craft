import { useState } from 'react';
import { GamePlayer, getGames } from './GameHub';
import { translator, type GameLocale } from './i18n';
import { decodeNativeGameLaunch } from '../../lib/nativeGameLaunch';

export function NativeGameEntry() {
  const [launch] = useState(() => {
    try { return { request: decodeNativeGameLaunch(window.location.hash, window.location.origin), error: '' }; }
    catch (error) { return { request: null, error: error instanceof Error ? error.message : 'Could not open this game.' }; }
  });
  const [locale, setLocale] = useState<GameLocale>(launch.request?.locale ?? 'en');
  const [closed, setClosed] = useState(false);
  const close = () => {
    setClosed(true);
    // Only the native app registers this message handler; there is no dynamic JS evaluation.
    (window as any).webkit?.messageHandlers?.craftGame?.postMessage({ action: 'close' });
  };
  const game = getGames(translator(locale)).find(game => game.id === launch.request?.game);
  if (closed || launch.error || !game || !launch.request) return <main style={{ minHeight: '100dvh', display: 'grid', placeContent: 'center', gap: 20, padding: 32, textAlign: 'center', color: '#282334', background: '#f8f6fc' }}>
    <h1>{closed ? 'Back to your creation' : 'Unable to open game'}</h1><p>{launch.error || 'Use the back button to return to your model.'}</p>
    {!closed && <button onClick={close}>Back to model</button>}
  </main>;
  return <GamePlayer game={game} vehicle="scout" customAsset={launch.request.asset} locale={locale} onLocaleChange={setLocale} onClose={close}/>;
}
