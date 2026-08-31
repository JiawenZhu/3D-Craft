import React from 'react';
import { SUPPORTED_MODELS } from '../data/models';
import { AIModelType } from '../types';
import { Cpu, Zap, Layers, Sparkles, ExternalLink } from 'lucide-react';

interface ModelSelectorProps {
  selectedModel: AIModelType;
  onSelectModel: (model: AIModelType) => void;
}

export const ModelSelector: React.FC<ModelSelectorProps> = ({
  selectedModel,
  onSelectModel
}) => {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between px-1">
        <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
          <Cpu className="w-3.5 h-3.5 text-cyan-400" />
          3D Generative Engine
        </label>
        <span className="text-[10px] text-slate-500 font-mono">Local / HF Spaces</span>
      </div>

      <div className="grid grid-cols-1 gap-2">
        {SUPPORTED_MODELS.map((model) => {
          const isSelected = selectedModel === model.id;
          return (
            <div
              key={model.id}
              onClick={() => onSelectModel(model.id)}
              className={`
                p-3 rounded-xl border transition-all duration-200 cursor-pointer relative overflow-hidden
                ${isSelected
                  ? 'bg-gradient-to-r from-cyan-950/40 via-slate-900/80 to-blue-950/40 border-cyan-500/60 shadow-lg shadow-cyan-950/50'
                  : 'bg-slate-900/40 border-slate-800/80 hover:border-slate-700 hover:bg-slate-900/70'
                }
              `}
            >
              {isSelected && (
                <div className="absolute top-0 right-0 w-24 h-24 bg-cyan-500/10 blur-2xl pointer-events-none" />
              )}

              <div className="flex items-start justify-between gap-2 mb-1.5">
                <div className="flex items-center gap-2">
                  <div className={`p-1.5 rounded-lg ${isSelected ? 'bg-cyan-500/20 text-cyan-400' : 'bg-slate-800 text-slate-400'}`}>
                    {model.id === 'hunyuan3d-2.1' ? (
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
                      <span className={`text-[10px] px-1.5 py-0.2 rounded font-medium ${
                        model.id === 'trellis-2.0'
                          ? 'bg-purple-500/20 text-purple-300 border border-purple-500/30'
                          : 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/30'
                      }`}>
                        {model.badge}
                      </span>
                    </div>
                    <div className="text-[11px] text-slate-400">{model.creator}</div>
                  </div>
                </div>

                <a
                  href={model.hfSpaceUrl}
                  target="_blank"
                  rel="noreferrer"
                  onClick={(e) => e.stopPropagation()}
                  className="text-slate-500 hover:text-cyan-400 transition-colors p-1"
                  title="Open on Hugging Face / Official Workspace"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                </a>
              </div>

              <p className="text-[11px] text-slate-300 leading-relaxed mb-2.5">
                {model.tagline}
              </p>

              <div className="grid grid-cols-3 gap-1.5 text-[10px] font-mono pt-2 border-t border-slate-800/80">
                <div className="bg-slate-950/60 rounded px-2 py-1 text-slate-400">
                  <span className="text-slate-500 block">Latency</span>
                  ~{model.latencySec}s
                </div>
                <div className="bg-slate-950/60 rounded px-2 py-1 text-slate-400">
                  <span className="text-slate-500 block">VRAM</span>
                  {model.minVramGb}GB+
                </div>
                <div className="bg-slate-950/60 rounded px-2 py-1 text-slate-400">
                  <span className="text-slate-500 block">Output</span>
                  {model.outputFormats[0]}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
