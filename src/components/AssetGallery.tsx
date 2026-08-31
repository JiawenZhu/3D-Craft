import React from 'react';
import { SAMPLE_CHARACTERS } from '../data/presets';
import { CharacterPreset } from '../types';
import { Box, Layers, Download } from 'lucide-react';

interface AssetGalleryProps {
  selectedCharacter: CharacterPreset;
  onSelectCharacter: (character: CharacterPreset) => void;
}

export const AssetGallery: React.FC<AssetGalleryProps> = ({
  selectedCharacter,
  onSelectCharacter
}) => {
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between px-1">
        <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 flex items-center gap-1.5">
          <Box className="w-3.5 h-3.5 text-cyan-400" />
          Recent Generated Assets
        </label>
        <span className="text-[10px] text-slate-500 font-mono">{SAMPLE_CHARACTERS.length} Models</span>
      </div>

      <div className="grid grid-cols-1 gap-2 max-h-[340px] overflow-y-auto pr-1">
        {SAMPLE_CHARACTERS.map((char) => {
          const isSelected = selectedCharacter.id === char.id;
          return (
            <div
              key={char.id}
              onClick={() => onSelectCharacter(char)}
              className={`
                p-2.5 rounded-xl border flex items-center gap-3 transition-all cursor-pointer
                ${isSelected
                  ? 'bg-gradient-to-r from-cyan-950/40 to-slate-900 border-cyan-500/70 shadow-md shadow-cyan-950/40'
                  : 'bg-slate-900/40 border-slate-800/80 hover:border-slate-700 hover:bg-slate-900/70'
                }
              `}
            >
              <div
                className="w-12 h-12 rounded-lg bg-slate-800 border border-slate-700/60 overflow-hidden flex items-center justify-center shrink-0"
                style={{
                  background: `radial-gradient(circle, ${char.geometryColor}33 0%, #0F172A 100%)`
                }}
              >
                <div
                  className="w-6 h-6 rounded-full"
                  style={{ backgroundColor: char.geometryColor, boxShadow: `0 0 12px ${char.geometryColor}` }}
                />
              </div>

              <div className="flex-1 min-w-0">
                <div className="text-xs font-bold text-slate-100 truncate">{char.title}</div>
                <div className="text-[10px] text-slate-400 capitalize flex items-center gap-2 mt-0.5">
                  <span className="text-cyan-400 font-medium">{char.style}</span>
                  <span>•</span>
                  <span className="font-mono">{(char.polyCount / 1000).toFixed(1)}k Polys</span>
                </div>
              </div>

              <div className="text-[10px] px-2 py-1 bg-slate-950/80 rounded border border-slate-800 font-mono text-slate-400 shrink-0">
                {char.modelType === 'trellis-2.0' ? 'TRELLIS' : 'Hunyuan'}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
