import React from 'react';
import { Dices } from 'lucide-react';
import { useStudio } from '../../store/StudioContext';
import { FieldLabel, Slider, Switch } from '../ui/primitives';
import { engineById } from '../../data/engines';
import { compact } from '../../lib/format';

const PRESETS = [
  { label: 'Game asset', patch: { targetFaces: 20_000, quadRemesh: true, texture: true } },
  { label: 'Hero prop', patch: { targetFaces: 120_000, quadRemesh: false, texture: true } },
  { label: 'Sculpt', patch: { targetFaces: 400_000, quadRemesh: false, texture: false } },
  { label: 'Print', patch: { targetFaces: 250_000, quadRemesh: false, texture: false } },
] as const;

export const AdvancedPanel: React.FC = () => {
  const { settings, patch } = useStudio();
  const engine = engineById(settings.engine);

  return (
    <div className="space-y-4">
      <div>
        <FieldLabel>Presets</FieldLabel>
        <div className="grid grid-cols-4 gap-1">
          {PRESETS.map((p) => (
            <button
              key={p.label}
              onClick={() => patch(p.patch)}
              className="rounded-lg border border-white/8 bg-white/[0.03] py-1.5 text-[10px] text-chalk-dim transition-all hover:border-white/25 hover:text-white"
            >
              {p.label}
            </button>
          ))}
        </div>
      </div>

      <div className="rd-hairline" />

      <Slider
        label="Target faces" min={5_000} max={500_000} step={5_000}
        value={settings.targetFaces} onChange={(v) => patch({ targetFaces: v })}
        format={compact}
      />
      <Slider
        label="Guidance" min={1} max={20} step={0.5}
        value={settings.guidance} onChange={(v) => patch({ guidance: v })}
        format={(v) => v.toFixed(1)}
      />
      <Slider
        label="Sampling steps" min={4} max={100} step={1}
        value={settings.steps} onChange={(v) => patch({ steps: v })}
      />

      <div className="rd-hairline" />

      <div>
        <FieldLabel>Negative prompt</FieldLabel>
        <textarea
          rows={2}
          value={settings.negativePrompt}
          onChange={(e) => patch({ negativePrompt: e.target.value })}
          placeholder="blurry, low poly, extra limbs…"
          className="w-full resize-none rounded-lg border border-white/8 bg-white/[0.03] p-2 text-[11px] text-chalk placeholder:text-chalk-ghost focus:border-white/25"
        />
      </div>

      <div>
        <FieldLabel>Seed</FieldLabel>
        <div className="flex items-center gap-2">
          <input
            value={settings.seed ?? ''}
            placeholder="random"
            onChange={(e) => patch({ seed: e.target.value ? Number(e.target.value.replace(/\D/g, '')) : null })}
            className="h-8 flex-1 rounded-lg border border-white/8 bg-white/[0.03] px-2.5 font-mono text-[11px] text-chalk placeholder:text-chalk-ghost focus:border-white/25"
          />
          <button
            onClick={() => patch({ seed: Math.floor(Math.random() * 2 ** 31) })}
            className="grid h-8 w-8 place-items-center rounded-lg border border-white/8 bg-white/[0.03] text-chalk-dim transition-colors hover:border-white/25 hover:text-white"
          >
            <Dices className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      <div className="rd-hairline" />

      <div className="space-y-2.5">
        <Switch checked={settings.removeBackground} onChange={(v) => patch({ removeBackground: v })} label="Remove background (rembg)" />
        <Switch
          checked={settings.texture && engine.supports.pbr}
          onChange={(v) => patch({ texture: v })}
          label={engine.supports.pbr ? 'Paint PBR texture' : 'Vertex colour only (engine has no PBR)'}
        />
        <Switch checked={settings.quadRemesh} onChange={(v) => patch({ quadRemesh: v })} label="Quad remesh on export" />
      </div>

      <p className="text-[10px] leading-relaxed text-chalk-ghost">
        Outputs: {engine.outputs.join(' · ')}
      </p>
    </div>
  );
};
