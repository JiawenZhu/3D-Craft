import React, { useState } from 'react';
import { ArrowLeft, Download, Link2, Link2Off, Trophy } from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';
import { Viewport } from './Viewport';
import { Segmented } from '../ui/primitives';
import { engineById } from '../../data/engines';
import { compact } from '../../lib/format';
import type { StudioLight, ViewportShading } from '../../types';

const SHADING: { value: ViewportShading; label: string }[] = [
  { value: 'material', label: 'Material' },
  { value: 'solid', label: 'Solid' },
  { value: 'wireframe', label: 'Wire' },
  { value: 'normal', label: 'Normal' },
];

/** Side-by-side A/B of one input run through both engines. */
export const CompareView: React.FC = () => {
  const { comparison, closeComparison, openAsset } = useStudio();
  const [shading, setShading] = useState<ViewportShading>('material');
  const [light, setLight] = useState<StudioLight>('studio');
  const [linked, setLinked] = useState(true);
  const [spin, setSpin] = useState(true);

  if (!comparison || comparison.length < 2) return null;
  const [a, b] = comparison;

  // Cheap, honest heuristics — the visual read is still the real judgement.
  const denser = a.faces === b.faces ? null : a.faces > b.faces ? a : b;
  const textured = [a, b].filter((x) => x.textureRes > 0);

  const Pane: React.FC<{ asset: typeof a; side: 'A' | 'B' }> = ({ asset, side }) => {
    const engine = engineById(asset.engine);
    return (
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <div className="flex items-center justify-between px-1">
          <div className="flex items-center gap-2">
            <span className="grid h-5 w-5 place-items-center rounded-md bg-white/10 text-[10px] font-bold text-white">{side}</span>
            <span className="rd-grad-text text-[14px] font-bold">{engine.label}</span>
            {denser?.id === asset.id && (
              <span className="flex items-center gap-1 rounded-full bg-lilac/15 px-2 py-0.5 text-[9px] text-lilac">
                <Trophy className="h-2.5 w-2.5" /> denser
              </span>
            )}
          </div>
          <button
            onClick={() => { closeComparison(); openAsset(asset); }}
            className="rounded-full border border-white/10 px-2.5 py-1 text-[10px] text-chalk-dim transition-colors hover:border-white/30 hover:text-white"
          >
            Open
          </button>
        </div>

        <div className="relative min-h-0 flex-1 overflow-hidden rounded-2xl border border-white/[0.07]">
          <Viewport asset={asset} shading={shading} light={light} autoRotate={spin} showGrid={false} showGizmo={false} />
        </div>

        <div className="grid grid-cols-4 gap-1.5 px-1">
          {[
            ['faces', compact(asset.faces)],
            ['verts', compact(asset.vertices)],
            ['texture', asset.textureRes ? `${asset.textureRes}²` : '—'],
            ['size', `${asset.fileSizeMb}MB`],
          ].map(([k, v]) => (
            <div key={k} className="rounded-lg border border-white/[0.06] bg-white/[0.03] px-2 py-1.5">
              <div className="text-[9px] uppercase tracking-[0.12em] text-chalk-ghost">{k}</div>
              <div className="font-mono text-[12px] text-chalk">{v}</div>
            </div>
          ))}
        </div>
        {asset.provider && (
          <p className="truncate px-1 font-mono text-[10px] text-chalk-ghost">{asset.provider} · {asset.note}</p>
        )}
      </div>
    );
  };

  return (
    <div className="fixed inset-0 z-[130] flex animate-popIn flex-col bg-ink/95 backdrop-blur-2xl">
      <div className="flex h-14 shrink-0 items-center justify-between px-6">
        <button onClick={closeComparison} className="flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3.5 py-1.5 text-[12px] text-chalk transition-colors hover:border-white/25 hover:text-white">
          <ArrowLeft className="h-3.5 w-3.5" /> Back
        </button>

        <div className="flex items-center gap-2">
          <Segmented size="sm" value={shading} onChange={setShading} options={SHADING} />
          <Segmented
            size="sm" value={light} onChange={setLight}
            options={(['studio', 'rim', 'sunset', 'flat'] as StudioLight[]).map((l) => ({
              value: l, label: <span className="capitalize">{l}</span>,
            }))}
          />
          <button
            onClick={() => setLinked((v) => !v)}
            title={linked ? 'Cameras spin together' : 'Cameras independent'}
            className={cn('grid h-8 w-8 place-items-center rounded-full border transition-all', linked ? 'border-white/30 bg-white/10 text-white' : 'border-white/10 text-chalk-dim hover:text-white')}
          >
            {linked ? <Link2 className="h-4 w-4" /> : <Link2Off className="h-4 w-4" />}
          </button>
          <button
            onClick={() => setSpin((v) => !v)}
            className={cn('rounded-full border px-3 py-1.5 text-[11px] transition-all', spin ? 'border-white/30 bg-white/10 text-white' : 'border-white/10 text-chalk-dim hover:text-white')}
          >
            Turntable
          </button>
        </div>

        <div className="text-[12px] text-chalk-dim">
          {textured.length === 1
            ? `Only ${engineById(textured[0].engine).label} produced a texture`
            : `${a.prompt.slice(0, 46)}${a.prompt.length > 46 ? '…' : ''}`}
        </div>
      </div>

      <div className="flex min-h-0 flex-1 gap-4 px-6 pb-6">
        <Pane asset={a} side="A" />
        <Pane asset={b} side="B" />
      </div>
    </div>
  );
};
