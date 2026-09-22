import { LegalPage, isLegalPath } from './pages/LegalPages';
import { Showcase } from './pages/Showcase';
import { MobileAuthBridge, isMobileAuthPath } from './pages/MobileAuthBridge';
import { lazy, Suspense } from 'react';
import { isApiAccessPath } from './pages/apiAccessPath';
const ApiAccess = lazy(() => import('./pages/ApiAccess').then(module => ({ default: module.ApiAccess })));
const GameHub = lazy(() => import('./components/games/GameHub').then(module => ({ default: module.GameHub })));
const NativeGameEntry = lazy(() => import('./components/games/NativeGameEntry').then(module => ({ default: module.NativeGameEntry })));

const isIosGamePath = (path: string) => path === '/ios-game' || path === '/ios-game/' || path.startsWith('/ios-game');

// The creation workspace remains in LegacyStudioApp.tsx for a future release.
// No public route or URL parameter enables web generation or checkout.
export const App = () => {
  if (isMobileAuthPath(window.location.pathname)) return <MobileAuthBridge />;
  if (isLegalPath(window.location.pathname)) return <LegalPage />;
  if (isApiAccessPath(window.location.pathname)) return <Suspense fallback={<p role="status">Loading your account…</p>}><ApiAccess /></Suspense>;
  if (isIosGamePath(window.location.pathname)) {
    return (
      <Suspense fallback={<main style={{ minHeight: '100dvh', display: 'grid', placeContent: 'center', background: '#f8f6fc', color: '#282334' }}>Loading game…</main>}>
        <NativeGameEntry />
      </Suspense>
    );
  }
  if (window.location.pathname === '/play') return <Suspense fallback={<p role="status">Loading games…</p>}><GameHub /></Suspense>;
  return <Showcase />;
};
export default App;
