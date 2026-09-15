import { LegalPage, isLegalPath } from './pages/LegalPages';
import { Showcase } from './pages/Showcase';
import { MobileAuthBridge, isMobileAuthPath } from './pages/MobileAuthBridge';

// The creation workspace remains in LegacyStudioApp.tsx for a future release.
// No public route or URL parameter enables web generation or checkout.
export const App = () => {
  if (isMobileAuthPath(window.location.pathname)) return <MobileAuthBridge />;
  if (isLegalPath(window.location.pathname)) return <LegalPage />;
  return <Showcase />;
};
export default App;
