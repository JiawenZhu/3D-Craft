import React, { useState } from 'react';
import { Calculator } from 'lucide-react';
import { CostCalculator } from './CostCalculator';
import { useStudio } from '../../store/StudioContext';
import { ENGINES } from '../../data/engines';
import { usd } from '../../lib/pricing';
import type { ModelPrice } from '../../lib/api';

function rateLabel(rate: ModelPrice) {
  if (rate.unit === 'account') return 'Account allowance · limits apply';
  if (rate.unit === 'tokens') {
    return rate.inputPerMillion == null || rate.outputPerMillion == null
      ? 'Token rate pending'
      : `${usd(rate.inputPerMillion)} input / ${usd(rate.outputPerMillion)} output per 1M tokens`;
  }
  return `${usd(rate.unitUsd)}${rate.unitUsd == null ? '' : ` / ${rate.unit}`}`;
}

/** Visible before generation; totals are estimates, separate from wallet credits. */
export function PricingSummary() {
  const { pricing, settings, images, price, runCost, usePipeline, geminiReady, showPricingDetails, setShowPricingDetails } = useStudio();
  const [calculatorOpen, setCalculatorOpen] = useState(false);
  const viaPipeline = usePipeline && geminiReady;
  const selected = pricing?.models[settings.engine];
  const textureExtra = selected?.texturedUsd != null && selected.unitUsd != null
    ? selected.texturedUsd - selected.unitUsd : null;
  const inputCount = images.filter((image) => image.file).length;
  const engines = settings.compare && settings.compareWith !== settings.engine
    ? [settings.engine, settings.compareWith] : [settings.engine];
  return (
    <div className="mt-4 w-[min(420px,calc(100vw-32px))] text-[11px] text-chalk-dim">
      <div className="flex items-center justify-center gap-5">
        <button type="button" role="switch" aria-checked={showPricingDetails} onClick={() => setShowPricingDetails(!showPricingDetails)} className="flex items-center gap-2 rounded-full py-2 hover:text-white focus-visible:outline focus-visible:outline-lilac">
          <span className={`relative h-4 w-7 rounded-full transition-colors ${showPricingDetails ? 'bg-lilac/70' : 'bg-white/15'}`}><span className={`absolute top-0.5 h-3 w-3 rounded-full bg-white transition-transform ${showPricingDetails ? 'translate-x-3.5' : 'translate-x-0.5'}`} /></span>
          Pricing details
        </button>
        <button type="button" onClick={() => setCalculatorOpen(true)} className="flex items-center gap-1.5 rounded-full border border-white/10 px-3 py-2 text-lilac transition-colors hover:bg-white/5"><Calculator className="h-3.5 w-3.5" /> Cost calculator</button>
      </div>
      {calculatorOpen && <CostCalculator onClose={() => setCalculatorOpen(false)} />}
      {showPricingDetails && <div className="mt-3 rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3">
      <div className="flex items-center justify-between gap-3" aria-live="polite">
        <span>{viaPipeline ? 'Concept + 3D estimate' : 'Estimated generation cost'}</span>
        <strong className="text-lilac">{viaPipeline ? 'Based on usage' : usd(runCost)} USD</strong>
      </div>
      <div className="mt-2 space-y-1 text-[10px] leading-relaxed">
        {(viaPipeline ? [settings.engine] : engines).map((id) => (
          <p key={id}>{ENGINES.find((engine) => engine.id === id)?.label} · {usd(price(id))} / result{viaPipeline ? ' base' : ` × ${settings.batch}`}</p>
        ))}
        {textureExtra !== null && textureExtra > 0 && (
          <p>PBR texture: +{usd(textureExtra)} / result{settings.texture ? ' · included above' : ' · not selected'}</p>
        )}
        {!viaPipeline && inputCount > 1 && <p>{inputCount} reference images · multi-view pricing applied where supported.</p>}
        {viaPipeline && <p>Concepts are billed per image; planning and validation use tokens. The current flow requests up to four views and one 3D result. Actual views and retries can change the total; batch and A/B do not apply to this route.</p>}
      </div>
      <details className="mt-2 border-t border-white/10 pt-2">
        <summary className="cursor-pointer font-medium text-chalk hover:text-white">All model prices & add-ons</summary>
        {!pricing ? (
          <p className="mt-3">Prices are temporarily unavailable. An unknown price does not mean free.</p>
        ) : (
          <>
            <div className="mt-3 space-y-3">
              {Object.entries(pricing.models).map(([id, rate]) => (
                <div key={id} className="border-b border-white/[0.06] pb-2 last:border-0">
                  <div className="font-medium text-chalk">{rate.name}</div>
                  <div className="mt-0.5 text-lilac">{rateLabel(rate)}</div>
                  {rate.unit === 'image' && rate.inputPerMillion != null && rate.outputPerMillion != null && <p>Plus {usd(rate.inputPerMillion)} input / {usd(rate.outputPerMillion)} text output per 1M tokens</p>}
                  {rate.fourKUsd != null && <p>4K image output: {usd(rate.fourKUsd)} / image · additional input/token usage applies</p>}
                  {id !== "hunyuan3d-2-white" && rate.texturedUsd != null && <p>With texture: {usd(rate.texturedUsd)} / generation{rate.unitUsd != null ? ` (+${usd(rate.texturedUsd - rate.unitUsd)})` : ''}</p>}
                  {rate.multiUnitUsd != null && <p>Multi-view: {usd(rate.multiUnitUsd)} / generation</p>}
                  {id !== "hunyuan3d-2-white" && rate.multiTexturedUsd != null && <p>Multi-view + texture: {usd(rate.multiTexturedUsd)} / generation</p>}
                  {rate.highPackUsd != null && <p>HighPack: {usd(rate.highPackUsd)} total{rate.unitUsd != null ? ` (+${usd(rate.highPackUsd - rate.unitUsd)})` : ''} · not enabled in this generator</p>}
                  <p className="mt-1 text-[10px] leading-relaxed text-chalk-faint">{rate.note}</p>
                  {rate.source && <a href={rate.source} target="_blank" rel="noreferrer" className="mt-1 inline-block text-[10px] text-chalk underline underline-offset-2">Provider pricing</a>}
                </div>
              ))}
            </div>
            <p className="mt-2 text-[10px] leading-relaxed text-chalk-faint">USD provider estimates · verified {pricing.verifiedAt}. Final billing depends on actual usage and provider rates. Unpriced or future models show “Price pending”.</p>
          </>
        )}
      </details>
      </div>}
    </div>
  );
}
