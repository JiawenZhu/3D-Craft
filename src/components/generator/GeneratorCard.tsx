import React from 'react';
import { useStudio } from '../../store/StudioContext';
import { ModeRail } from './ModeRail';
import { InputCard } from './InputCard';
import { OptionRail } from './OptionRail';
import { ActionRow } from './ActionRow';
import { EngineRow } from './EngineRow';
import { PricingSummary } from './PricingSummary';
import { JobBanner } from './JobBanner';
import { RouteToggle } from './RouteToggle';
import { Info } from 'lucide-react';

/**
 * The centrepiece of the Rodin workspace: a 180×180 input card flanked by the
 * mode rail and the option rail, with the GENERATE row and engine row beneath.
 */
export const GeneratorCard: React.FC = () => {
  const { job, settings, patch, images, notice, dismissNotice, usePipeline, geminiReady } = useStudio();
  // The engines are image-conditioned, but the concept pass is not: with it on,
  // a prompt alone is enough because Gemini renders the image the engines need.
  const needsImage = images.length === 0 && settings.prompt.trim().length > 0
    && !(usePipeline && geminiReady);

  return (
    <section className="relative z-10 mt-[164px] flex flex-col items-center animate-riseIn" style={{ animationDelay: '.15s' }}>
      {/* The live workspace centres the *card* on the viewport and hangs both
          rails off its edges, so the cluster never drifts as rails change width. */}
      <div className="relative flex w-[180px] justify-center">
        <div className="absolute right-full top-1/2 mr-[9px] -translate-y-1/2">
          <ModeRail value={settings.mode} onChange={(m) => patch({ mode: m, inputMode: m === 'worldgen' ? 'text' : settings.inputMode })} />
        </div>
        <InputCard />
        <div className="absolute left-full top-1/2 ml-[9px] -translate-y-1/2">
          <OptionRail />
        </div>
      </div>

      <ActionRow />
      <EngineRow />
      <RouteToggle />
      <PricingSummary />

      {/* Neither model does text→3D directly; say so rather than letting a run fail. */}
      {needsImage && !job && (
        <p className="mt-4 flex max-w-[420px] items-start gap-1.5 text-center text-[11px] leading-relaxed text-chalk-ghost">
          <Info className="mt-px h-3 w-3 shrink-0" />
          <span>
            Both engines are image-conditioned — drop a reference image to generate.
            A prompt on its own only names the result.
          </span>
        </p>
      )}

      {notice && (
        <button
          onClick={dismissNotice}
          className="mt-4 flex max-w-[440px] items-start gap-2 rounded-xl border border-amber/30 bg-amber/10 px-3 py-2 text-left text-[11px] leading-relaxed text-amber"
        >
          <Info className="mt-px h-3 w-3 shrink-0" />
          <span>{notice}</span>
        </button>
      )}

      {job && <JobBanner />}
    </section>
  );
};
