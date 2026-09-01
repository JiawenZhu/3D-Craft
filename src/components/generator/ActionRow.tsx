import React, { useState } from 'react';
import { ChevronRight, Loader2, Lock, SlidersHorizontal, Square, Unlock } from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';
import { Popover, Tip } from '../ui/primitives';
import { AdvancedPanel } from './AdvancedPanel';
import { elapsed } from '../../lib/format';

const BATCHES = [1, 2, 4, 10];

/** Circular determinate ring drawn over the GENERATE pill while a job runs. */
const Ring: React.FC<{ value: number }> = ({ value }) => {
  const r = 12, c = 2 * Math.PI * r;
  return (
    <svg viewBox="0 0 30 30" className="h-[26px] w-[26px] -rotate-90">
      <circle cx="15" cy="15" r={r} fill="none" stroke="rgba(255,255,255,.15)" strokeWidth="2.5" />
      <circle
        cx="15" cy="15" r={r} fill="none" stroke="#d8a1f1" strokeWidth="2.5" strokeLinecap="round"
        strokeDasharray={c} strokeDashoffset={c * (1 - value / 100)}
        style={{ transition: 'stroke-dashoffset .35s linear' }}
      />
    </svg>
  );
};

export const ActionRow: React.FC = () => {
  const {
    settings, patch, generate, cancel, job, images, runCost,
    usePipeline, geminiReady, startPipeline, pipeline,
  } = useStudio();
  const [advOpen, setAdvOpen] = useState(false);
  const running = !!job && job.stage !== 'done' && job.stage !== 'failed';
  // A concept run is four stages on the server with no cancel endpoint, so it
  // is shown as busy rather than as a stop button that would lie.
  const piping = pipeline?.status === 'running';
  const viaPipeline = usePipeline && geminiReady;
  const ready = settings.inputMode === 'text' || settings.mode === 'worldgen'
    ? settings.prompt.trim().length > 0
    : images.length > 0 || settings.prompt.trim().length > 0;

  /** Which stage of the concept run the button should be narrating. */
  const stageNow = piping
    ? pipeline!.nodes.find((n) => n.status === 'running') ?? pipeline!.nodes[0]
    : null;

  return (
    <div className="relative mt-[6px] flex w-[191px] items-center justify-center">
      {/* private / public ------------------------------------------------ */}
      <div className="absolute right-full top-1/2 mr-[37px] -translate-y-1/2">
      <Tip label={settings.isPrivate ? 'Private — hidden from the shelf' : 'Public — visible in your asset shelf'}>
        <button
          onClick={() => patch({ isPrivate: !settings.isPrivate })}
          className="grid h-[60px] w-[60px] place-items-center rounded-full border border-white/10 transition-all duration-300 hover:border-white/30"
          style={{ background: 'rgba(255,255,255,.05)', backdropFilter: 'blur(14px)' }}
        >
          <span className="grid h-[36px] w-[36px] place-items-center rounded-full bg-white/[0.15] backdrop-blur-xl">
            {settings.isPrivate
              ? <Lock className="h-[17px] w-[17px] text-white" strokeWidth={1.7} />
              : <Unlock className="h-[17px] w-[17px] text-chalk" strokeWidth={1.7} />}
          </span>
        </button>
      </Tip>
      </div>

      {/* GENERATE -------------------------------------------------------- */}
      <div className="rd-generate-halo relative">
        <button
          onClick={running ? cancel : viaPipeline ? startPipeline : generate}
          disabled={piping || (!ready && !running)}
          className={cn(
            'group relative flex h-[60px] w-[191px] items-center justify-center overflow-hidden rounded-full border transition-all duration-300',
            running || piping
              ? 'border-white/25 bg-white/[0.10]'
              : ready
                ? 'border-white/20 bg-white/[0.07] hover:border-white/45 hover:bg-white/[0.12] active:scale-[0.985]'
                : 'cursor-not-allowed border-white/8 bg-white/[0.03] opacity-55',
          )}
          style={{ backdropFilter: 'blur(14px)' }}
        >
          {/* progress fill */}
          {running && !piping && (
            <span
              className="absolute inset-y-0 left-0 bg-white/[0.10] transition-[width] duration-500"
              style={{ width: `${job!.progress}%` }}
            />
          )}
          {piping ? (
            <span className="relative flex items-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin text-lilac" />
              <span className="text-left">
                <span className="block text-[11px] font-semibold leading-tight text-white">
                  {stageNow?.label ?? 'Running'}
                </span>
                <span className="block font-mono text-[9px] leading-tight text-chalk-faint">
                  {elapsed(Date.now() - pipeline!.createdAt)}
                </span>
              </span>
            </span>
          ) : running ? (
            <span className="relative flex items-center gap-2.5">
              <Ring value={job!.progress} />
              <span className="text-left">
                <span className="block text-[11px] font-semibold leading-tight text-white">{Math.round(job!.progress)}%</span>
                <span className="block font-mono text-[9px] leading-tight text-chalk-faint">{elapsed(Date.now() - job!.startedAt)}</span>
              </span>
              <Square className="h-3 w-3 fill-current text-chalk-faint" />
            </span>
          ) : (
            <>
              <span className="text-[18px] font-bold tracking-[0.01em] text-white transition-opacity duration-300 group-hover:opacity-0">
                GENERATE
              </span>
              <span className="absolute inset-0 grid place-items-center text-[18px] font-bold text-white opacity-0 transition-opacity duration-300 group-hover:opacity-100">
                {runCost > 0 ? `$${runCost.toFixed(2)}` : 'Free · local'}
              </span>
            </>
          )}
        </button>
      </div>

      <div className="absolute left-full top-1/2 ml-[26px] flex -translate-y-1/2 items-center gap-[5px]">
      {/* batch count ----------------------------------------------------- */}
      <Tip label="Results per run">
        <button
          onClick={() => patch({ batch: BATCHES[(BATCHES.indexOf(settings.batch) + 1) % BATCHES.length] })}
          className="flex h-[29px] w-[57px] items-center justify-center gap-0.5 rounded-full transition-all duration-200 hover:brightness-125"
          style={{ background: 'rgba(216,161,241,.12)' }}
        >
          <span className="text-[13px] font-medium text-lilac">×{settings.batch}</span>
          <ChevronRight className="h-3 w-3 text-lilac/70" />
        </button>
      </Tip>

      {/* advanced options ------------------------------------------------ */}
      <div className="relative">
        <Tip label="Advanced options">
          <button
            onClick={() => setAdvOpen((v) => !v)}
            className={cn(
              'grid h-[29px] w-[29px] place-items-center rounded-full transition-all duration-200',
              advOpen ? 'bg-white/15 text-white' : 'text-chalk-dim hover:bg-white/10 hover:text-white',
            )}
          >
            <SlidersHorizontal className="h-[15px] w-[15px]" strokeWidth={1.7} />
          </button>
        </Tip>
        <Popover open={advOpen} onClose={() => setAdvOpen(false)} className="right-0 w-[330px]">
          <AdvancedPanel />
        </Popover>
      </div>
      </div>
    </div>
  );
};
