import { LegalPage, isLegalPath } from './pages/LegalPages';
import { Showcase } from './pages/Showcase';
import { MobileAuthBridge, isMobileAuthPath } from './pages/MobileAuthBridge';
import { lazy, Suspense } from 'react';
const GameHub = lazy(() => import('./components/games/GameHub').then(module => ({ default: module.GameHub })));

// The creation workspace remains in LegacyStudioApp.tsx for a future release.
// No public route or URL parameter enables web generation or checkout.
export const App = () => {
  if (isMobileAuthPath(window.location.pathname)) return <MobileAuthBridge />;
  if (isLegalPath(window.location.pathname)) return <LegalPage />;
  if (window.location.pathname === '/play') return <Suspense fallback={<p role="status">Loading games…</p>}><GameHub /></Suspense>;
  return <Showcase />;
};
export default App;
