import React from 'react';
import { SUPPORTED_MODELS } from '../data/models';
import { AIModelType, GenerationSpeed } from '../types';
import { Cpu, Zap, Layers, Sparkles, ExternalLink, Gauge } from 'lucide-react';

interface ModelSelectorProps {
  selectedModel: AIModelType;
  onSelectModel: (model: AIModelType) => void;
  speed: GenerationSpeed;
  onSelectSpeed: (speed: GenerationSpeed) => void;
}

export const ModelSelector: React.FC<ModelSelectorProps> = ({
  selectedModel,
  onSelectModel,
  speed,
  onSelectSpeed
}) => {
  return (
    <div className="flex flex-col gap-3">
      {/* Section Header */}
      <div className="flex items-center justify-between px-1">
        <label className="text-xs font-bold uppercase tracking-wider text-slate-300 flex items-center gap-1.5">
          <Cpu className="w-3.5 h-3.5 text-cyan-400" />
          Foundation Engine
        </label>
        <span className="text-[10px] text-cyan-400 bg-cyan-500/10 px-2 py-0.5 rounded font-mono border border-cyan-500/30">
          Rodin v2
        </span>
      </div>

      {/* Engine Cards */}
      <div className="grid grid-cols-1 gap-2">
        {SUPPORTED_MODELS.map((model) => {
          const isSelected = selectedModel === model.id;
          return (
            <div
              key={model.id}
              onClick={() => onSelectModel(model.id)}
              className={`
                p-3 rounded-xl border transition-all duration-200 cursor-pointer relative overflow-hidden group
                ${isSelected
                  ? 'bg-gradient-to-r from-cyan-950/40 via-[#0F172A] to-blue-950/40 border-cyan-500/80 shadow-md shadow-cyan-950/60 ring-1 ring-cyan-500/30'
                  : 'bg-[#0E1320]/70 border-[#1A2234] hover:border-slate-700 hover:bg-[#121828]'
                }
              `}
            >
              {isSelected && (
                <div className="absolute top-0 right-0 w-24 h-24 bg-cyan-500/10 blur-xl pointer-events-none" />
              )}

              <div className="flex items-start justify-between gap-2 mb-1.5">
                <div className="flex items-center gap-2">
                  <div className={`p-1.5 rounded-lg ${
                    isSelected ? 'bg-cyan-500/20 text-cyan-400' : 'bg-slate-800 text-slate-400'
                  }`}>
                    {model.id === 'hybrid-pipeline' ? (
                      <Sparkles className="w-4 h-4" />
                    ) : model.id === 'trellis-2.0' ? (
                      <Zap className="w-4 h-4" />
                    ) : (
                      <Layers className="w-4 h-4" />
                    )}
                  </div>
                  <div>
                    <div className="text-xs font-bold text-slate-100 flex items-center gap-1.5">
                      {model.name}
                    </div>
                    <div className="text-[10px] text-cyan-400/90 font-medium">{model.badge}</div>
                  </div>
                </div>

                <span className="text-[10px] font-mono text-slate-400 bg-slate-900 px-1.5 py-0.5 rounded border border-slate-800 shrink-0">
                  ~{model.latencySec}s
                </span>
              </div>

              <p className="text-[11px] text-slate-400 leading-snug line-clamp-2">
                {model.tagline}
              </p>
            </div>
          );
        })}
      </div>

      {/* Speed & Quality Tier Selector (Inspired by Hyper3D Speedy vs Extreme) */}
      <div>
        <label className="text-[11px] font-semibold uppercase tracking-wider text-slate-400 block mb-1.5 flex items-center justify-between">
          <span className="flex items-center gap-1">
            <Gauge className="w-3 h-3 text-cyan-400" />
            Generation Mode
          </span>
        </label>

        <div className="grid grid-cols-3 gap-1 p-1 bg-[#0A0E18] rounded-xl border border-[#1A2234]">
          {[
            { id: 'speedy', label: 'Speedy', time: '15s' },
            { id: 'default', label: 'Default', time: '30s' },
            { id: 'extreme-4k', label: 'Extreme 4K', time: '50s' }
          ].map((tier) => (
            <button
              key={tier.id}
              onClick={() => onSelectSpeed(tier.id as GenerationSpeed)}
              className={`
                py-1.5 px-2 rounded-lg text-center transition-all flex flex-col items-center
                ${speed === tier.id
                  ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 border border-cyan-500/50 text-cyan-300 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-900/50'
                }
              `}
            >
              <span className="text-[11px] font-bold">{tier.label}</span>
              <span className="text-[9px] font-mono text-slate-500">{tier.time}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
