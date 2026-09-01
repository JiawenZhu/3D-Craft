import React, { useCallback, useRef, useState } from 'react';
import {
  ArrowLeft, Box, Camera, Copy, Download, Expand, Grid3x3, Heart, Info, Layers, Lightbulb,
  Maximize2, RefreshCw, RotateCw, Trash2, ZoomIn, ZoomOut,
} from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';
import { Viewport, type ViewportHandle } from './Viewport';
import { Popover, Slider, Tip } from '../ui/primitives';
import { engineById } from '../../data/engines';
import { API_BASE } from '../../lib/api';
import { AssetThumb } from '../AssetThumb';
import { ago, compact } from '../../lib/format';
import type { LightTrim, StudioLight, ViewportShading } from '../../types';

const SHADING: { id: ViewportShading; label: string }[] = [
  { id: 'material', label: 'Material' },
  { id: 'solid', label: 'Solid' },
  { id: 'wireframe', label: 'Wire' },
  { id: 'normal', label: 'Normal' },
  { id: 'uv', label: 'UV' },
];
const LIGHTS: StudioLight[] = ['studio', 'rim', 'sunset', 'night', 'flat'];

/** Only what the server can genuinely convert to — see EXPORT_FORMATS there. */
const EXPORT_FORMATS = [
  { ext: 'glb', label: '.glb', note: 'textured · recommended' },
  { ext: 'obj', label: '.obj', note: 'zip · with mtl + texture' },
  { ext: 'ply', label: '.ply', note: 'vertex colour' },
  { ext: 'stl', label: '.stl', note: 'geometry only' },
] as const;

/** Prompts make lousy filenames. */
const slug = (name: string) =>
  name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 48) || 'model';

export const Workbench: React.FC = () => {
  const { activeAsset, closeAsset, assets, exploreAssets, openAsset, toggleLike, removeAsset, patch, settings } = useStudio();
  const [shading, setShading] = useState<ViewportShading>('material');
  const [light, setLight] = useState<StudioLight>('studio');
  const [autoRotate, setAutoRotate] = useState(true);
  const [grid, setGrid] = useState(true);
  const [lightOpen, setLightOpen] = useState(false);
  const [exportOpen, setExportOpen] = useState(false);
  const [infoOpen, setInfoOpen] = useState(true);
  const [trim, setTrim] = useState<LightTrim>({ directional: 1, ambient: 1, environment: 1, exposure: 1 });
  const view = useRef<ViewportHandle>(null);
  const stage = useRef<HTMLElement>(null);


  const fullscreen = () => {
    const el = stage.current;
    if (!el) return;
    if (document.fullscreenElement) document.exitFullscreen();
    else el.requestFullscreen?.();
  };

  if (!activeAsset) return null;
  const a = activeAsset;
  const engine = engineById(a.engine);
  const siblings = [...assets, ...exploreAssets].filter((x) => x.id !== a.id).slice(0, 8);

  const stat = (k: string, v: string) => (
    <div className="flex items-center justify-between border-b border-white/[0.06] py-2 last:border-0">
      <span className="text-[11px] uppercase tracking-[0.14em] text-chalk-faint">{k}</span>
      <span className="font-mono text-[12px] text-chalk">{v}</span>
    </div>
  );

  return (
    <div className="fixed inset-0 z-[120] flex animate-popIn flex-col bg-ink/90 backdrop-blur-2xl">
      {/* top bar -------------------------------------------------------- */}
      <div className="flex h-14 shrink-0 items-center justify-between px-6">
        <button onClick={closeAsset} className="flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.03] px-3.5 py-1.5 text-[12px] text-chalk backdrop-blur-xl transition-colors hover:border-white/25 hover:text-white">
          <ArrowLeft className="h-3.5 w-3.5" /> Back
        </button>
        <div className="truncate px-4 text-[13px] font-semibold text-white">{a.name}</div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => toggleLike(a.id)}
            className={cn('grid h-9 w-9 place-items-center rounded-full border transition-all', a.liked ? 'border-rose/40 bg-rose/15 text-rose' : 'border-white/10 bg-white/[0.03] text-chalk-dim hover:text-white')}
          >
            <Heart className={cn('h-4 w-4', a.liked && 'fill-current')} />
          </button>
          <div className="relative">
            <button
              onClick={() => setExportOpen((v) => !v)}
              className="flex items-center gap-2 rounded-full px-4 py-2 text-[12px] font-semibold text-ink transition-all hover:brightness-110"
              style={{ backgroundImage: 'var(--g-accent)' }}
            >
              <Download className="h-3.5 w-3.5" /> Export
            </button>
            <Popover open={exportOpen} onClose={() => setExportOpen(false)} anchor="bottom" className="right-0 w-52">
              <div className="mb-2 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">Download</div>
              {EXPORT_FORMATS.map((f) => (
                <a
                  key={f.ext}
                  // Absolute, and pointed at the API: a relative href resolves
                  // against the Vite origin, whose SPA fallback hands back
                  // index.html renamed to .glb.
                  href={a.modelUrl ? `${API_BASE}/api/assets/${a.id}/export?format=${f.ext}` : undefined}
                  download={a.modelUrl ? `${slug(a.name)}${f.ext === 'obj' ? '-obj.zip' : `.${f.ext}`}` : undefined}
                  onClick={(e) => { if (!a.modelUrl) e.preventDefault(); }}
                  className={cn(
                    'flex items-center justify-between rounded-lg px-2.5 py-2 text-[12px] transition-colors',
                    a.modelUrl ? 'text-chalk hover:bg-white/[0.06] hover:text-white' : 'cursor-not-allowed text-chalk-ghost',
                  )}
                >
                  <span>
                    {f.label}
                    <span className="ml-2 text-[10px] text-chalk-ghost">{f.note}</span>
                  </span>
                  <Download className="h-3 w-3" />
                </a>
              ))}
              <p className="mt-2 text-[10px] leading-relaxed text-chalk-ghost">
                {a.modelUrl
                  ? 'Converted on demand from the GLB. FBX and USDZ are not offered — they cannot be written faithfully here.'
                  : 'This is a preview asset. Start the inference server and regenerate to get real files.'}
              </p>
            </Popover>
          </div>
        </div>
      </div>

      {/* body ----------------------------------------------------------- */}
      <div className="flex min-h-0 flex-1 gap-4 px-6 pb-6">
        {/* left: parameters (504px on the live workbench) --------------- */}
        <aside className="rd-scroll hidden w-[340px] shrink-0 overflow-y-auto rounded-3xl border border-white/[0.07] bg-white/[0.025] p-5 xl:block">
          <div className="mb-1 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">Prompt</div>
          <p className="mb-5 text-[13px] leading-relaxed text-chalk">{a.prompt}</p>

          <div className="mb-5 rounded-2xl border border-white/[0.07] bg-black/20 p-3">
            {stat('Engine', engine.label)}
            {stat('Faces', compact(a.faces))}
            {stat('Vertices', compact(a.vertices))}
            {stat('Texture', a.textureRes ? `${a.textureRes}²` : 'vertex colour')}
            {stat('Size', `${a.fileSizeMb} MB`)}
            {stat('Created', ago(a.createdAt))}
            {a.provider && stat('Ran on', a.provider)}
          </div>

          {a.note && (
            <p className="mb-5 rounded-xl border border-white/[0.07] bg-black/20 px-3 py-2 text-[11px] leading-relaxed text-chalk-faint">
              {a.note}
            </p>
          )}

          <div className="space-y-2">
            <button
              onClick={() => { patch({ prompt: a.prompt, engine: a.engine }); closeAsset(); }}
              className="flex w-full items-center justify-center gap-2 rounded-full border border-white/12 bg-white/[0.05] py-2.5 text-[12px] font-medium text-white transition-all hover:border-white/30"
            >
              <RefreshCw className="h-3.5 w-3.5" /> Reuse these settings
            </button>
            <button
              onClick={() => { patch({ prompt: `${a.prompt}, variation`, engine: settings.engine }); closeAsset(); }}
              className="flex w-full items-center justify-center gap-2 rounded-full border border-white/10 py-2.5 text-[12px] text-chalk-dim transition-all hover:border-white/25 hover:text-white"
            >
              <Copy className="h-3.5 w-3.5" /> Fork a copy
            </button>
            {a.local && (
              <button
                onClick={() => removeAsset(a.id)}
                className="flex w-full items-center justify-center gap-2 rounded-full border border-red-500/20 py-2.5 text-[12px] text-red-400/80 transition-all hover:border-red-500/40 hover:text-red-300"
              >
                <Trash2 className="h-3.5 w-3.5" /> Delete
              </button>
            )}
          </div>
        </aside>

        {/* centre: viewport --------------------------------------------- */}
        <main ref={stage} className="relative min-w-0 flex-1 overflow-hidden rounded-3xl border border-white/[0.07]">
          <Viewport
            ref={view}
            asset={a}
            shading={shading}
            light={light}
            autoRotate={autoRotate}
            showGrid={grid}
            trim={trim}
          />

          {/* model info, mirroring what any GLB viewer shows */}
          {infoOpen && (
            <div className="absolute left-4 top-16 w-[208px] rounded-2xl border border-white/10 bg-ink-900/85 p-3.5 backdrop-blur-xl">
              <div className="mb-2 text-[12px] font-semibold text-white">Model info</div>
              {[
                ['Triangles', a.faces ? a.faces.toLocaleString() : '—'],
                ['Vertices', a.vertices ? a.vertices.toLocaleString() : '—'],
                ['Meshes', a.meshes ? String(a.meshes) : '—'],
                ['Materials', a.materials ? String(a.materials) : '—'],
                ['Dimensions', a.dimensions ? a.dimensions.map((d) => d.toFixed(2)).join(' × ') : '—'],
                ['File size', `${a.fileSizeMb} MB`],
              ].map(([k, v]) => (
                <div key={k} className="flex items-baseline justify-between gap-2 py-[3px]">
                  <span className="text-[11px] text-chalk-faint">{k}</span>
                  <span className="text-right font-mono text-[11px] text-chalk">{v}</span>
                </div>
              ))}
            </div>
          )}

          {/* shading segmented, floating bottom-centre */}
          <div className="absolute bottom-4 left-1/2 flex -translate-x-1/2 items-center gap-0.5 rounded-full border border-white/10 bg-ink-900/80 p-1 backdrop-blur-xl">
            {SHADING.map((s) => (
              <button
                key={s.id}
                onClick={() => setShading(s.id)}
                className={cn('rounded-full px-3 py-1.5 text-[11px] transition-all', shading === s.id ? 'bg-white/90 font-medium text-ink' : 'text-chalk-dim hover:text-white')}
              >
                {s.label}
              </button>
            ))}
          </div>

          {/* viewport tools, floating top-right */}
          <div className="absolute right-4 top-4 flex flex-col gap-1.5 rounded-2xl border border-white/10 bg-ink-900/80 p-1.5 backdrop-blur-xl">
            <Tip side="left" label="Zoom in"><button onClick={() => view.current?.zoom(0.8)} className="grid h-8 w-8 place-items-center rounded-lg text-chalk-dim transition-colors hover:text-white"><ZoomIn className="h-4 w-4" /></button></Tip>
            <Tip side="left" label="Zoom out"><button onClick={() => view.current?.zoom(1.25)} className="grid h-8 w-8 place-items-center rounded-lg text-chalk-dim transition-colors hover:text-white"><ZoomOut className="h-4 w-4" /></button></Tip>
            <Tip side="left" label="Reset view"><button onClick={() => view.current?.fit()} className="grid h-8 w-8 place-items-center rounded-lg text-chalk-dim transition-colors hover:text-white"><Expand className="h-4 w-4" /></button></Tip>
            <div className="mx-1 h-px bg-white/10" />
            <Tip side="left" label="Turntable"><button onClick={() => setAutoRotate((v) => !v)} className={cn('grid h-8 w-8 place-items-center rounded-lg transition-colors', autoRotate ? 'bg-white/12 text-white' : 'text-chalk-dim hover:text-white')}><RotateCw className="h-4 w-4" /></button></Tip>
            <Tip side="left" label="Ground grid"><button onClick={() => setGrid((v) => !v)} className={cn('grid h-8 w-8 place-items-center rounded-lg transition-colors', grid ? 'bg-white/12 text-white' : 'text-chalk-dim hover:text-white')}><Grid3x3 className="h-4 w-4" /></button></Tip>
            <div className="relative">
              <Tip side="left" label="Lighting rig"><button onClick={() => setLightOpen((v) => !v)} className={cn('grid h-8 w-8 place-items-center rounded-lg transition-colors', lightOpen ? 'bg-white/12 text-white' : 'text-chalk-dim hover:text-white')}><Lightbulb className="h-4 w-4" /></button></Tip>
              <Popover open={lightOpen} onClose={() => setLightOpen(false)} anchor="bottom" className="right-0 w-[248px] p-3">
                <div className="mb-2 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">Rig</div>
                <div className="mb-4 grid grid-cols-3 gap-1">
                  {LIGHTS.map((l) => (
                    <button
                      key={l}
                      onClick={() => setLight(l)}
                      className={cn('rounded-lg py-1.5 text-[11px] capitalize transition-colors',
                        light === l ? 'bg-white/[0.12] text-white' : 'bg-white/[0.03] text-chalk-dim hover:text-white')}
                    >
                      {l}
                    </button>
                  ))}
                </div>

                <div className="space-y-3.5">
                  <Slider label="Directional" min={0} max={3} step={0.05}
                          value={trim.directional} onChange={(v) => setTrim((t) => ({ ...t, directional: v }))}
                          format={(v) => `${v.toFixed(2)}×`} />
                  <Slider label="Ambient" min={0} max={3} step={0.05}
                          value={trim.ambient} onChange={(v) => setTrim((t) => ({ ...t, ambient: v }))}
                          format={(v) => `${v.toFixed(2)}×`} />
                  <Slider label="Environment" min={0} max={3} step={0.05}
                          value={trim.environment} onChange={(v) => setTrim((t) => ({ ...t, environment: v }))}
                          format={(v) => `${v.toFixed(2)}×`} />
                  <Slider label="Exposure" min={0.4} max={2.5} step={0.05}
                          value={trim.exposure} onChange={(v) => setTrim((t) => ({ ...t, exposure: v }))}
                          format={(v) => `${v.toFixed(2)}×`} />
                </div>

                <button
                  onClick={() => setTrim({ directional: 1, ambient: 1, environment: 1, exposure: 1 })}
                  className="mt-4 w-full rounded-lg border border-white/10 py-1.5 text-[11px] text-chalk-dim transition-colors hover:border-white/25 hover:text-white"
                >
                  Reset to preset
                </button>
                <p className="mt-2 text-[10px] leading-relaxed text-chalk-ghost">
                  Sliders scale the preset, so switching rig keeps your balance.
                </p>
              </Popover>
            </div>
            <Tip side="left" label="Model info">
              <button onClick={() => setInfoOpen((v) => !v)} className={cn('grid h-8 w-8 place-items-center rounded-lg transition-colors', infoOpen ? 'bg-white/12 text-white' : 'text-chalk-dim hover:text-white')}>
                <Info className="h-4 w-4" />
              </button>
            </Tip>
            <Tip side="left" label="Save PNG">
              <button onClick={() => view.current?.screenshot(a.name.replace(/[^a-z0-9]+/gi, '-').toLowerCase() || 'render')}
                      className="grid h-8 w-8 place-items-center rounded-lg text-chalk-dim transition-colors hover:text-white">
                <Camera className="h-4 w-4" />
              </button>
            </Tip>
            <Tip side="left" label="Fullscreen">
              <button onClick={fullscreen} className="grid h-8 w-8 place-items-center rounded-lg text-chalk-dim transition-colors hover:text-white">
                <Maximize2 className="h-4 w-4" />
              </button>
            </Tip>
          </div>

          {/* engine badge, floating top-left */}
          <div className="absolute left-4 top-4 flex items-center gap-2 rounded-full border border-white/10 bg-ink-900/80 px-3 py-1.5 text-[11px] backdrop-blur-xl">
            <Box className="h-3.5 w-3.5 text-lilac" />
            <span className="rd-grad-text font-semibold">{engine.label}</span>
            <span className="text-chalk-ghost">·</span>
            <span className="font-mono text-chalk-faint">{compact(a.faces)} tris</span>
          </div>
        </main>

        {/* right: variant gallery (337px on the live workbench) ---------- */}
        <aside className="rd-scroll hidden w-[176px] shrink-0 overflow-y-auto rounded-3xl border border-white/[0.07] bg-white/[0.025] p-3 lg:block">
          <div className="mb-2.5 flex items-center gap-1.5 px-1 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">
            <Layers className="h-3 w-3" /> Related
          </div>
          <div className="grid grid-cols-2 gap-2">
            {siblings.map((s) => (
              <button
                key={s.id}
                onClick={() => openAsset(s)}
                className="aspect-square overflow-hidden rounded-xl border border-white/[0.06] transition-all hover:border-white/30"
              >
                <AssetThumb asset={s} className="h-full w-full" />
              </button>
            ))}
          </div>
        </aside>
      </div>
    </div>
  );
};
