import React, { useState } from 'react';
import { ChevronDown, ChevronLeft, ChevronRight, Columns2, Gauge, Rabbit, Sparkles } from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';
import { EFFORTS, ENGINES, engineById } from '../../data/engines';
import { Popover, Tip } from '../ui/primitives';
import { seconds } from '../../lib/format';
import type { CreationMode, EffortId } from '../../types';

const CREATION: { id: CreationMode; label: string; sub: string; tag: string }[] = [
  { id: 'build-myself', label: 'Create Manually', sub: 'Generate objects', tag: 'Manual' },
  { id: 'ai-assist', label: 'Generate Objects', sub: '3D objects', tag: 'AI Assist' },
  { id: 'full-ai', label: 'Complete Scene', sub: '3D gaussian environment', tag: 'Full AI' },
];

export const EngineRow: React.FC = () => {
  const { settings, patch, estimate, price } = useStudio();
  const [effortOpen, setEffortOpen] = useState(false);
  const [creationOpen, setCreationOpen] = useState(false);
  const engine = engineById(settings.engine);
  const { health, backendOnline } = useStudio();
  const idx = ENGINES.findIndex((e) => e.id === settings.engine);
  const effort = EFFORTS.find((e) => e.id === settings.effort)!;
  const creation = CREATION.find((c) => c.id === settings.creation)!;

  const step = (d: number) => {
    const next = ENGINES[(idx + d + ENGINES.length) % ENGINES.length];
    patch({ engine: next.id, steps: EFFORTS.find((e) => e.id === settings.effort)!.steps });
  };

  return (
    <div className="relative mt-[27px] flex w-[168px] items-center justify-center">
      {/* ‹ engine › ------------------------------------------------------ */}
      <Tip label={`${engine.vendor} · ${engine.blurb}`}>
        <div
          className="flex h-[35px] w-[168px] items-center justify-between rounded-[37px] px-1"
          style={{ background: 'rgba(255,255,255,.1)', backdropFilter: 'blur(14px)' }}
        >
          <button onClick={() => step(-1)} className="grid h-[27px] w-[27px] place-items-center rounded-full text-chalk-faint transition-colors hover:bg-white/10 hover:text-white">
            <ChevronLeft className="h-[15px] w-[15px]" />
          </button>
          <span className="rd-grad-text-engine text-[15px] font-bold leading-none">{engine.label}</span>
          <button onClick={() => step(1)} className="grid h-[27px] w-[27px] place-items-center rounded-full text-chalk-faint transition-colors hover:bg-white/10 hover:text-white">
            <ChevronRight className="h-[15px] w-[15px]" />
          </button>
        </div>
      </Tip>

      <div className="absolute right-full top-1/2 mr-[6px] flex -translate-y-1/2 items-center gap-1">
        {settings.compare && (
          <button
            onClick={() => {
              const others = ENGINES.filter((e) => e.id !== settings.engine);
              const i = others.findIndex((e) => e.id === settings.compareWith);
              patch({ compareWith: others[(i + 1) % others.length].id });
            }}
            className="rd-grad-text-engine whitespace-nowrap rounded-full bg-white/[0.05] px-2 py-1 text-[11px] font-semibold transition-all hover:bg-white/[0.10]"
          >
            vs {engineById(settings.compareWith).label}
          </button>
        )}
        <Tip label="Run this input through two engines and compare them side by side">
          <button
            onClick={() => patch({ compare: !settings.compare, compareWith: settings.compareWith === settings.engine ? 'trellis-2' : settings.compareWith })}
            className={cn(
              'flex h-[29px] items-center gap-1.5 rounded-full px-2.5 text-[13px] transition-all',
              settings.compare ? 'bg-lilac/15 text-lilac' : 'text-chalk-faint hover:bg-white/[0.06] hover:text-white',
            )}
          >
            <Columns2 className="h-[14px] w-[14px]" /> A/B
          </button>
        </Tip>
      </div>

      <div className="absolute left-full top-1/2 ml-[6px] flex -translate-y-1/2 items-center gap-[4px]">
      {/* creation mode — WorldGen only, as on the live workspace ---------- */}
      {settings.mode === 'worldgen' && (
        <div className="relative">
          <button
            onClick={() => setCreationOpen((v) => !v)}
            className="flex h-[29px] items-center gap-1.5 rounded-full px-2.5 transition-colors hover:bg-white/[0.06]"
          >
            <Sparkles className="h-[14px] w-[14px] text-coral" />
            <span className="rd-grad-text text-[13px]">{creation.tag}</span>
            <ChevronDown className={cn('h-3 w-3 text-chalk-faint transition-transform', creationOpen && 'rotate-180')} />
          </button>
          <Popover open={creationOpen} onClose={() => setCreationOpen(false)} className="left-1/2 w-[239px] -translate-x-1/2 p-2">
            <div className="mb-1.5 px-1 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">Creation mode</div>
            {CREATION.map((c) => (
              <button
                key={c.id}
                onClick={() => { patch({ creation: c.id }); setCreationOpen(false); }}
                className={cn(
                  'flex w-full items-center justify-between rounded-[17px] px-3 py-2 text-left transition-colors',
                  settings.creation === c.id ? 'bg-white/[0.07]' : 'hover:bg-white/[0.04]',
                )}
              >
                <span>
                  <span className="block text-[13px] font-medium text-white/95">{c.label}</span>
                  <span className="block text-[10px] text-chalk-faint">{c.sub}</span>
                </span>
                <span className="rounded-full bg-white/[0.07] px-2 py-0.5 text-[9px] font-bold text-white/95">{c.tag}</span>
              </button>
            ))}
          </Popover>
        </div>
      )}

      {/* effort ----------------------------------------------------------- */}
      <div className="relative">
        <button
          onClick={() => setEffortOpen((v) => !v)}
          className="flex h-[29px] items-center gap-1.5 rounded-full px-2.5 transition-colors hover:bg-white/[0.06]"
        >
          {settings.quality === 'speedy'
            ? <Rabbit className="h-[15px] w-[15px] text-speedy" />
            : <Gauge className="h-[15px] w-[15px] text-coral" />}
          <span className="rd-grad-text text-[13px]">{effort.label}</span>
          <ChevronDown className={cn('h-3 w-3 text-chalk-faint transition-transform', effortOpen && 'rotate-180')} />
        </button>

        <Popover open={effortOpen} onClose={() => setEffortOpen(false)} className="left-1/2 w-[236px] -translate-x-1/2 p-[10px]">
          {/* Default / Speedy */}
          <div className="mb-2 grid grid-cols-2 gap-1 rounded-[18px] p-1" style={{ background: 'rgba(217,217,217,.08)' }}>
            {([['default', 'Default', Gauge], ['speedy', 'Speedy', Rabbit]] as const).map(([id, label, Icon]) => (
              <button
                key={id}
                onClick={() => patch({ quality: id })}
                className={cn(
                  'flex h-[34px] items-center justify-center gap-1.5 rounded-[16px] text-[13px] font-bold transition-all',
                  settings.quality === id
                    ? id === 'speedy' ? 'bg-speedy/15 text-speedy' : 'text-[#efccff]'
                    : 'text-chalk-faint hover:text-chalk',
                )}
              >
                <Icon className="h-[14px] w-[14px]" /> {label}
              </button>
            ))}
          </div>

          <div className="mb-1.5 flex items-center justify-center">
            <span className="rounded-lg border border-white/20 px-2.5 py-1 text-[11px] text-white/60" style={{ background: 'rgb(58,52,57)' }}>
              Select Effort
            </span>
          </div>

          <div className="space-y-0.5">
            {EFFORTS.map((e) => {
              const active = settings.effort === e.id;
              const secs = Math.round(estimate(settings.engine, e.id) * (settings.quality === 'speedy' ? 0.55 : 1));
              return (
                <button
                  key={e.id}
                  onClick={() => { patch({ effort: e.id, steps: e.steps }); setEffortOpen(false); }}
                  className={cn('flex h-[28px] w-full items-center justify-between rounded-[18px] px-2.5 transition-colors', active ? 'bg-black/30' : 'hover:bg-white/[0.04]')}
                >
                  <span className={cn('text-[13px]', active ? 'rd-grad-text font-medium' : 'text-white/80')}>{e.label}</span>
                  <span
                    className={cn('rounded-full px-2 py-0.5 text-[11px]', active ? 'text-lilac' : 'text-white/50')}
                    style={{ background: active ? 'rgba(216,161,241,.12)' : 'rgba(255,255,255,.03)' }}
                  >
                    {seconds(secs)}
                  </span>
                </button>
              );
            })}
          </div>
          <p className="mt-2 px-1 text-[10px] leading-relaxed text-chalk-ghost">
            {backendOnline ? (
              <>
                {engine.label} on <span className="font-mono text-chalk">{health!.engines?.[engine.id]?.provider ?? '—'}</span>
                {price(settings.engine) > 0
                  ? <> · <span className="text-lilac">${price(settings.engine).toFixed(2)}</span> per result</>
                  : <> · free</>}
              </>
            ) : (
              <>Rough estimates · start the server for numbers from your actual device.</>
            )}
          </p>
        </Popover>
      </div>
      </div>
    </div>
  );
};
