import React from 'react';
import { CharacterPreset, RenderMode } from '../types';
import { Layers, Eye, Activity, Shield, Hash, Image as ImageIcon } from 'lucide-react';

interface MaterialInspectorProps {
  character: CharacterPreset;
  renderMode: RenderMode;
  onSetRenderMode: (mode: RenderMode) => void;
  wireframe: boolean;
  onToggleWireframe: () => void;
}

const SHADER_MODES: { id: RenderMode; label: string }[] = [
  { id: 'pbr', label: 'Full PBR' },
  { id: 'wireframe', label: 'Wireframe' },
  { id: 'normal', label: 'Normal Map' },
  { id: 'roughness', label: 'Roughness' },
  { id: 'metallic', label: 'Metallic' },
  { id: 'matcap', label: 'Studio MatCap' }
];

export const MaterialInspector: React.FC<MaterialInspectorProps> = ({
  character,
  renderMode,
  onSetRenderMode,
  wireframe,
  onToggleWireframe
}) => {
  return (
    <div className="flex flex-col gap-3">
      {/* Geometry Stats */}
      <div className="p-3 bg-slate-900/60 border border-slate-800 rounded-xl flex flex-col gap-2">
        <div className="flex items-center justify-between text-xs font-semibold text-slate-300">
          <span className="flex items-center gap-1.5">
            <Activity className="w-3.5 h-3.5 text-cyan-400" />
            Mesh Topology Metrics
          </span>
          <span className="text-[10px] text-emerald-400 bg-emerald-500/10 px-1.5 py-0.5 rounded border border-emerald-500/20 font-mono">
            Clean Quads
          </span>
        </div>

        <div className="grid grid-cols-2 gap-2 text-[11px] font-mono">
          <div className="bg-slate-950/70 p-2 rounded border border-slate-800/80">
            <span className="text-slate-500 block text-[10px]">Triangles</span>
            <span className="text-slate-200 font-semibold">{character.polyCount.toLocaleString()}</span>
          </div>
          <div className="bg-slate-950/70 p-2 rounded border border-slate-800/80">
            <span className="text-slate-500 block text-[10px]">Vertices</span>
            <span className="text-slate-200 font-semibold">{(character.polyCount * 0.52).toFixed(0)}</span>
          </div>
          <div className="bg-slate-950/70 p-2 rounded border border-slate-800/80">
            <span className="text-slate-500 block text-[10px]">Texture UV</span>
            <span className="text-slate-200 font-semibold">{character.textureRes}</span>
          </div>
          <div className="bg-slate-950/70 p-2 rounded border border-slate-800/80">
            <span className="text-slate-500 block text-[10px]">Draw Calls</span>
            <span className="text-slate-200 font-semibold">1 (Batched)</span>
          </div>
        </div>
      </div>

      {/* Render / Shader Channel Inspection */}
      <div>
        <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2 flex items-center justify-between">
          <span>Shader Inspection Pass</span>
          <button
            onClick={onToggleWireframe}
            className={`text-[10px] px-2 py-0.5 rounded border transition-colors ${
              wireframe
                ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40'
                : 'bg-slate-800 text-slate-400 border-slate-700'
            }`}
          >
            Wireframe: {wireframe ? 'ON' : 'OFF'}
          </button>
        </label>

        <div className="grid grid-cols-3 gap-1.5">
          {SHADER_MODES.map((mode) => (
            <button
              key={mode.id}
              onClick={() => onSetRenderMode(mode.id)}
              className={`
                py-2 px-1 text-[11px] font-medium rounded-lg border text-center transition-all
                ${renderMode === mode.id
                  ? 'bg-cyan-500/20 border-cyan-500 text-cyan-300 shadow-sm'
                  : 'bg-slate-900/50 border-slate-800 text-slate-400 hover:border-slate-700 hover:text-slate-200'
                }
              `}
            >
              {mode.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};
