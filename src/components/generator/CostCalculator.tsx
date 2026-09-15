import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowRight, Box, Calculator, Image, X } from 'lucide-react';
import { useStudio } from '../../store/StudioContext';
import { ENGINES } from '../../data/engines';
import { generationPrice, usd } from '../../lib/pricing';
import type { EngineId } from '../../types';

const inputClass = 'mt-1 w-full rounded-xl border border-white/10 bg-white/[0.05] px-3 py-2.5 text-[12px] text-chalk focus:outline-none focus:ring-1 focus:ring-lilac';

/** A planning sandbox: inputs never mutate generation settings or submit work. */
export function CostCalculator({ onClose }: { onClose: () => void }) {
  const { pricing, settings, images, usePipeline, geminiReady } = useStudio();
  const viaPipeline = usePipeline && geminiReady;
  const [imageCount, setImageCount] = useState(viaPipeline ? 4 : 0);
  const [imageModel, setImageModel] = useState('gemini-3-pro-image');
  const [fourK, setFourK] = useState(false);
  const [engine, setEngine] = useState<EngineId>(settings.engine);
  const [results, setResults] = useState(viaPipeline ? 1 : settings.batch);
  const [views, setViews] = useState(viaPipeline ? 1 : Math.max(1, images.filter(image => image.file).length));
  const [texture, setTexture] = useState(settings.texture);
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const node = dialog.current;
    node?.showModal();
    return () => node?.close();
  }, []);
  const imageRates = Object.entries(pricing?.models ?? {}).filter(([id, rate]) =>
    rate.unit === 'image' || rate.unit === 'account' || (rate.unit === 'unknown' && id.includes('image')));
  const imageRate = pricing?.models[imageModel];
  const imageUnit = fourK ? imageRate?.fourKUsd : imageRate?.unitUsd;
  const imageCost = imageCount === 0 ? 0 : imageUnit == null ? null : imageUnit * imageCount;
  const modelUnit = generationPrice(pricing, engine, texture, views);
  const modelCost = modelUnit == null ? null : modelUnit * results;
  const subtotal = imageCost == null || modelCost == null ? null : imageCost + modelCost;
  const knownSubtotal = modelCost != null || (imageCount > 0 && imageCost != null)
    ? (imageCost ?? 0) + (modelCost ?? 0) : null;

  return createPortal(
    <dialog ref={dialog} onCancel={onClose} onClick={event => { if (event.target === event.currentTarget) onClose(); }} aria-labelledby="cost-calculator-title" className="fixed inset-0 m-auto max-h-[90dvh] w-[min(520px,calc(100vw-24px))] overflow-y-auto rounded-[28px] border border-white/15 bg-ink-900 p-0 text-chalk shadow-2xl backdrop:bg-black/60 backdrop:backdrop-blur-sm">
      <div className="p-5 sm:p-6">
        <div className="flex items-start justify-between gap-3">
          <div><div className="mb-2 flex items-center gap-2 text-[10px] uppercase tracking-[0.18em] text-lilac"><Calculator className="h-3.5 w-3.5" /> Plan your creation</div><h2 id="cost-calculator-title" className="text-xl font-semibold text-white">From image to 3D</h2><p className="mt-1 text-[11px] text-chalk-faint">Explore costs. Your generation settings stay the same.</p></div>
          <button type="button" autoFocus onClick={onClose} aria-label="Close cost calculator" className="rounded-full border border-white/10 p-2 text-chalk-dim hover:bg-white/10"><X className="h-4 w-4" /></button>
        </div>
        <div className="my-5 flex items-center justify-center gap-3 text-[11px] text-lilac"><Image className="h-4 w-4" /> Concept images <ArrowRight className="h-3 w-3 text-chalk-faint" /><Box className="h-4 w-4" /> 3D objects</div>
        <section className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
          <div className="mb-3 flex items-center justify-between"><h3 className="text-sm font-medium">01 · Create images</h3><span className="text-xs text-lilac">{imageCount > 0 && imageRate?.unit === 'account' ? 'Account allowance' : usd(imageCost)}</span></div>
          <label className="block text-[10px] text-chalk-faint">Image model<select value={imageModel} onChange={event => { setImageModel(event.target.value); setFourK(false); }} className={inputClass}>{imageRates.length === 0 && <option value="gemini-3-pro-image">Gemini · pricing unavailable</option>}{imageRates.map(([id, rate]) => <option key={id} value={id} className="bg-ink-900">{rate.name}</option>)}</select></label>
          <div className="mt-3 grid grid-cols-2 gap-3"><label className="text-[10px] text-chalk-faint">Images to generate<input type="number" min={0} max={100} value={imageCount} onChange={event => setImageCount(Math.min(100, Math.max(0, Math.trunc(Number(event.target.value)) || 0)))} className={inputClass} /></label><label className="text-[10px] text-chalk-faint">Image size<select value={fourK ? '4k' : '2k'} onChange={event => setFourK(event.target.value === '4k')} disabled={imageRate?.fourKUsd == null} className={inputClass}><option value="2k" className="bg-ink-900">{imageRate?.unit === 'account' ? 'Account default' : '2K'}</option>{imageRate?.fourKUsd != null && <option value="4k" className="bg-ink-900">4K</option>}</select></label></div>
          <p className="mt-2 text-[10px] leading-relaxed text-chalk-faint">{imageCount === 0 ? 'Using an existing image: no new image generation included.' : imageRate?.unit === 'account' ? 'Uses your account allowance. Availability and limits apply.' : 'Image output only. Planning, input tokens and retries are additional.'}</p>
        </section>
        <section className="mt-3 rounded-2xl border border-white/10 bg-white/[0.03] p-4">
          <div className="mb-3 flex items-center justify-between"><h3 className="text-sm font-medium">02 · Build 3D objects</h3><span className="text-xs text-lilac">{usd(modelCost)}</span></div>
          <label className="block text-[10px] text-chalk-faint">3D model<select value={engine} onChange={event => setEngine(event.target.value as EngineId)} className={inputClass}>{ENGINES.map(model => <option key={model.id} value={model.id} className="bg-ink-900">{model.label}</option>)}</select></label>
          <div className="mt-3 grid grid-cols-2 gap-3"><label className="text-[10px] text-chalk-faint">Objects to generate<input type="number" min={1} max={100} value={results} onChange={event => setResults(Math.min(100, Math.max(1, Math.trunc(Number(event.target.value)) || 1)))} className={inputClass} /></label><label className="text-[10px] text-chalk-faint">Views per object<input type="number" min={1} max={8} value={views} onChange={event => setViews(Math.min(8, Math.max(1, Math.trunc(Number(event.target.value)) || 1)))} className={inputClass} /></label></div>
          <label className="mt-3 flex items-center gap-2 text-xs"><input type="checkbox" checked={texture} onChange={event => setTexture(event.target.checked)} className="accent-[#d8a1f1]" /> Include texture</label>
          {modelCost === null && <p className="mt-2 text-[10px] text-chalk-faint">The provider rate for this configuration is not confirmed.</p>}
        </section>
        <div className="mt-5 rounded-2xl border border-lilac/20 bg-lilac/[0.08] p-4" aria-live="polite"><div className="flex items-center justify-between"><span className="text-xs text-chalk">{subtotal == null ? 'Known portion of estimate' : 'Estimated subtotal'}</span><strong className="text-2xl font-semibold text-lilac">{usd(subtotal ?? knownSubtotal)}<span className="ml-1 text-[10px] font-normal">USD</span></strong></div><p className="mt-2 text-[10px] leading-relaxed text-chalk-dim">{subtotal == null ? 'Some charges remain unpriced or use account allowance. This is not a complete total. ' : ''}Excludes token usage and retries. This is a planning estimate, not recorded spending.</p></div>
        <p className="mt-3 text-center text-[10px] text-chalk-faint">{pricing ? `Provider rates checked ${pricing.verifiedAt}` : 'Connect to the studio to load current pricing.'}</p>
      </div>
    </dialog>, document.body,
  );
}
