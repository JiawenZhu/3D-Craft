import React, { Suspense, lazy } from 'react';
import { AccountGate } from './components/auth/AccountGate';
import { StudioProvider, useStudio } from './store/StudioContext';
import { AmbientGlow } from './components/AmbientGlow';
import { TopBar } from './components/TopBar';
import { RightRail } from './components/RightRail';
import { Hero } from './components/Hero';
import { GeneratorCard } from './components/generator/GeneratorCard';
import { AssetShelf } from './components/AssetShelf';
import { LegalPage, LegalFooter, isLegalPath } from './pages/LegalPages';
import { PipelineBoard } from './components/pipeline/PipelineBoard';

// three.js only matters once you open an asset — keep it out of the landing bundle.
const NativeGameEntry = lazy(() => import('./components/games/NativeGameEntry').then(m => ({ default: m.NativeGameEntry })));
const Workbench = lazy(() => import('./components/workbench/Workbench').then((m) => ({ default: m.Workbench })));
const CompareView = lazy(() => import('./components/workbench/CompareView').then((m) => ({ default: m.CompareView })));

const Overlay: React.FC = () => (
  <div className="fixed inset-0 z-[150] grid place-items-center bg-ink/80 backdrop-blur-xl">
    <span className="rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-[12px] text-chalk-dim">
      loading viewport…
    </span>
  </div>
);

const Studio: React.FC = () => {
  const { activeAsset, comparison } = useStudio();
  // The workbench is its own page, not an overlay: while it is open the shelf,
  // the hero and every gallery image are unmounted, so one WebGL context and one
  // texture set are live instead of a canvas layered over 20 decoded JPEGs.
  const onStage = !!activeAsset || !!comparison;

  return (
    <div className="relative min-h-screen">
      {!onStage && (
        <>
          <AmbientGlow />
          <TopBar />
          <main className="relative z-10 pt-[148px]">
            <Hero />
            <GeneratorCard />
            <PipelineBoard />
            <AssetShelf />
          </main>
          <RightRail />
          <LegalFooter />
        </>
      )}
      <Suspense fallback={<Overlay />}>
        {activeAsset && <Workbench />}
        {comparison && <CompareView />}
      </Suspense>
    </div>
  );
};

export const LegacyStudioApp: React.FC = () => isLegalPath(window.location.pathname) ? <LegalPage /> : window.location.pathname === '/ios-game' ? (
  <Suspense fallback={<Overlay />}><NativeGameEntry /></Suspense>
) : (
  <StudioProvider>
    <AccountGate><Studio /></AccountGate>
  </StudioProvider>
);

export default LegacyStudioApp;
