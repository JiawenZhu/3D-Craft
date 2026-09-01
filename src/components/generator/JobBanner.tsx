import React from 'react';
import { AlertTriangle, Check, Loader2, X } from 'lucide-react';
import { useStudio } from '../../store/StudioContext';
import { engineById } from '../../data/engines';
import { cn } from '../../lib/cn';

const ORDER = ['preprocessing', 'sparse-structure', 'multiview', 'latent', 'mesh', 'texture', 'packaging'] as const;

/** Turn a raw backend error into something the user can act on. */
function hint(error: string): string | null {
  const e = error.toLowerCase();
  if (e.includes('zerogpu') || e.includes('quota') || e.includes('gpu duration')) {
    return 'The hosted Space is rate-limited for anonymous users. Export HF_TOKEN=… before starting the server, or switch that engine to a local provider.';
  }
  if (e.includes('image-conditioned') || e.includes('provide a reference')) {
    return 'Both engines start from an image. Drop a reference into the card above.';
  }
  if (e.includes('connect') || e.includes('timeout') || e.includes('connection')) {
    return 'Could not reach the inference server. Check that `npm run server` is still running.';
  }
  return null;
}

export const JobBanner: React.FC = () => {
  const { job, backendOnline, cancel } = useStudio();
  if (!job) return null;
  const engine = engineById(job.engine);
  const failed = job.stage === 'failed';
  const done = job.stage === 'done';
  const tip = failed ? hint(job.error ?? job.message) : null;

  return (
    <div className="mt-4 flex w-full max-w-[560px] animate-popIn flex-col items-center gap-2">
      <div
        className={cn(
          'flex max-w-full items-center gap-2 rounded-full border px-3.5 py-1.5 text-[11px] backdrop-blur-xl',
          failed ? 'border-red-500/30 bg-red-500/10 text-red-300'
            : done ? 'border-emerald-400/25 bg-emerald-400/10 text-emerald-300'
              : 'border-white/10 bg-white/[0.04] text-chalk',
        )}
      >
        {failed ? <AlertTriangle className="h-3 w-3 shrink-0" />
          : done ? <Check className="h-3 w-3 shrink-0" />
            : <Loader2 className="h-3 w-3 shrink-0 animate-spin text-lilac" />}
        <span className="truncate font-medium">{job.message}</span>
        <span className="text-chalk-ghost">·</span>
        <span className="shrink-0 font-mono text-[10px] text-chalk-faint">{engine.label}</span>
        {!backendOnline && !failed && (
          <>
            <span className="text-chalk-ghost">·</span>
            <span className="shrink-0 text-[10px] text-amber">preview</span>
          </>
        )}
        {failed && (
          <button onClick={cancel} className="ml-1 shrink-0 text-red-300/70 transition-colors hover:text-white">
            <X className="h-3 w-3" />
          </button>
        )}
      </div>

      {tip && (
        <p className="max-w-[520px] px-4 text-center text-[11px] leading-relaxed text-chalk-faint">{tip}</p>
      )}

      {!done && !failed && (
        <div className="flex items-center gap-1.5">
          {ORDER.filter((s) => s !== 'multiview' || job.engine !== 'trellis-2').map((s) => {
            const reached = ORDER.indexOf(job.stage as any) >= ORDER.indexOf(s);
            const current = job.stage === s;
            return (
              <span
                key={s}
                title={s}
                className={cn(
                  'h-1 rounded-full transition-all duration-500',
                  current ? 'w-5 bg-lilac' : reached ? 'w-2.5 bg-white/45' : 'w-2.5 bg-white/12',
                )}
              />
            );
          })}
        </div>
      )}
    </div>
  );
};
