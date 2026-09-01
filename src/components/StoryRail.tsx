import React, { useState } from 'react';
import { ArrowUpRight, Cpu, KeyRound, Terminal } from 'lucide-react';
import { cn } from '../lib/cn';
import { ENGINES } from '../data/engines';
import { useStudio } from '../store/StudioContext';

const TABS = ['Engines', 'Setup', 'Tips'] as const;

const Card: React.FC<{ children: React.ReactNode; className?: string }> = ({ children, className }) => (
  <div className={cn('rounded-2xl border border-white/[0.07] bg-white/[0.03] p-4', className)}>{children}</div>
);

/**
 * The right-hand column of the Rodin shelf. On the live site it carries STORY
 * posts; here it carries the two engines, the local setup state and tips —
 * same footprint (300px), content that actually helps you run this thing.
 */
export const StoryRail: React.FC = () => {
  const { health } = useStudio();
  const [tab, setTab] = useState<(typeof TABS)[number]>('Engines');

  return (
    <aside className="hidden w-[300px] shrink-0 rounded-3xl border border-white/[0.07] bg-white/[0.04] p-4 xl:block">
      <h3 className="mb-3 text-[20px] font-semibold tracking-wide text-white">STORY</h3>
      <div className="mb-4 flex flex-wrap gap-1.5">
        {TABS.map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={cn('rounded-lg px-2.5 py-1.5 text-[12px] transition-colors', tab === t ? 'bg-white/[0.10] text-white' : 'bg-white/[0.03] text-chalk-dim hover:text-white')}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'Engines' && (
        <div className="space-y-3">
          {ENGINES.filter((e) => e.id !== 'hybrid').map((e) => (
            <Card key={e.id}>
              <div className="mb-1.5 flex items-center justify-between">
                <span className="rd-grad-text text-[14px] font-bold">{e.label}</span>
                <span className="rounded-full border border-white/10 px-1.5 py-0.5 font-mono text-[9px] text-chalk-faint">{e.vendor}</span>
              </div>
              <p className="mb-3 text-[11px] leading-relaxed text-chalk-dim">{e.blurb}</p>
              <div className="mb-3 flex flex-wrap gap-1">
                {e.outputs.map((o) => (
                  <span key={o} className="rounded-full bg-white/[0.05] px-1.5 py-0.5 font-mono text-[9px] text-chalk-faint">{o}</span>
                ))}
              </div>
              <a href={e.spaceUrl} target="_blank" rel="noreferrer" className="flex items-center gap-1 text-[11px] text-chalk-dim transition-colors hover:text-white">
                Hugging Face Space <ArrowUpRight className="h-3 w-3" />
              </a>
            </Card>
          ))}
        </div>
      )}

      {tab === 'Setup' && (
        <div className="space-y-3">
          <Card>
            <div className="mb-2 flex items-center gap-2 text-[12px] font-medium text-white">
              <Cpu className="h-3.5 w-3.5 text-lilac" /> Inference server
            </div>
            {health ? (
              <>
                <p className="mb-2 font-mono text-[11px] text-emerald-400">online · {health.device}</p>
                <div className="space-y-1">
                  {ENGINES.filter((e) => e.id !== 'hybrid').map((e) => {
                    const h = health.engines?.[e.id];
                    return (
                      <div key={e.id} className="flex items-center justify-between text-[11px]">
                        <span className="text-chalk-dim">{e.label}</span>
                        <span className={cn('font-mono text-[10px]', h?.loaded ? 'text-emerald-400' : h?.installed ? 'text-amber' : 'text-chalk-ghost')}>
                          {h?.loaded ? 'loaded' : h?.installed ? 'installed' : 'missing'}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </>
            ) : (
              <p className="text-[11px] leading-relaxed text-chalk-dim">
                Offline — generations are simulated so you can still drive the whole UI.
              </p>
            )}
          </Card>
          <Card>
            <div className="mb-2 flex items-center gap-2 text-[12px] font-medium text-white">
              <Terminal className="h-3.5 w-3.5 text-lilac" /> Start it
            </div>
            {['./scripts/setup.sh --local', 'python scripts/fetch_weights.py', 'npm run server'].map((c) => (
              <code key={c} className="mb-1.5 block rounded-lg bg-black/40 px-2.5 py-1.5 font-mono text-[10px] text-chalk">{c}</code>
            ))}
            <p className="mt-2 text-[10px] leading-relaxed text-chalk-ghost">
              Weights land in <span className="font-mono">server/weights</span> (~3 GB).
            </p>
          </Card>
          <Card>
            <div className="mb-2 flex items-center gap-2 text-[12px] font-medium text-white">
              <KeyRound className="h-3.5 w-3.5 text-lilac" /> Hosted Spaces
            </div>
            <p className="mb-2 text-[11px] leading-relaxed text-chalk-dim">
              Engines without a native path fall back to their Hugging Face Space. Those run on
              ZeroGPU, and anonymous quota is tiny — set a token first:
            </p>
            <code className="block rounded-lg bg-black/40 px-2.5 py-1.5 font-mono text-[10px] text-chalk">export HF_TOKEN=hf_…</code>
          </Card>
        </div>
      )}

      {tab === 'Tips' && (
        <div className="space-y-2">
          {[
            'Drop 2–4 views and switch to Multi-view — TRELLIS.2 is pose-free.',
            'Only Hunyuan3D-2.1 paints real PBR maps; TRELLIS gives vertex colour.',
            'Extreme-Low is genuinely usable for silhouette iteration.',
            'Tag each reference with a direction to sharpen the back side.',
            'Quad remesh before export if the asset will be rigged.',
          ].map((t) => (
            <Card key={t} className="p-3">
              <p className="text-[11px] leading-relaxed text-chalk-dim">{t}</p>
            </Card>
          ))}
        </div>
      )}
    </aside>
  );
};
