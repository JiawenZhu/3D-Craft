import React, { useState } from 'react';
import { CharacterPreset } from '../types';
import { Download, X, Check, Box, Sparkles, FileCode, Layers } from 'lucide-react';

interface ExportModalProps {
  isOpen: boolean;
  onClose: () => void;
  character: CharacterPreset;
}

export const ExportModal: React.FC<ExportModalProps> = ({
  isOpen,
  onClose,
  character
}) => {
  const [selectedFormat, setSelectedFormat] = useState<'glb' | 'obj' | 'fbx' | 'usdz' | 'ply'>('glb');
  const [includePbrTextures, setIncludePbrTextures] = useState(true);
  const [targetPolycount, setTargetPolycount] = useState(character.polyCount);
  const [isExporting, setIsExporting] = useState(false);
  const [downloadReady, setDownloadReady] = useState(false);

  if (!isOpen) return null;

  const handleExport = () => {
    setIsExporting(true);
    setTimeout(() => {
      setIsExporting(false);
      setDownloadReady(true);
    }, 1200);
  };

  const handleTriggerDownload = () => {
    // Generate simulated downloadable 3D artifact
    const dummyData = `# Rodin 3D Studio Export: ${character.title} (${selectedFormat.toUpperCase()})\n# Generated with ${character.modelType}\n# Polygons: ${targetPolycount}\n# Textures: ${character.textureRes}\n`;
    const blob = new Blob([dummyData], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${character.title.toLowerCase().replace(/\s+/g, '-')}.${selectedFormat}`;
    a.click();
    URL.revokeObjectURL(url);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-md flex items-center justify-center p-4 animate-fade-in">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-lg w-full p-6 shadow-2xl relative flex flex-col gap-5">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-slate-400 hover:text-white p-1 rounded-lg hover:bg-slate-800 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        <div>
          <div className="text-lg font-bold text-slate-100 flex items-center gap-2">
            <Download className="w-5 h-5 text-cyan-400" />
            Export 3D Game Asset
          </div>
          <div className="text-xs text-slate-400 mt-1">
            Export {character.title} directly into game engines (Unreal Engine 5, Unity, Blender, WebGL).
          </div>
        </div>

        {/* Format Selector */}
        <div>
          <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2">
            Target 3D File Format
          </label>
          <div className="grid grid-cols-3 gap-2">
            {[
              { id: 'glb', name: 'GLB / glTF 2.0', desc: 'Web & Game Standard' },
              { id: 'fbx', name: 'Autodesk FBX', desc: 'Unity & Unreal Rig' },
              { id: 'obj', name: 'Wavefront OBJ', desc: 'Universal Mesh' },
              { id: 'usdz', name: 'Universal USDZ', desc: 'Apple Vision / AR' },
              { id: 'ply', name: 'Gaussian PLY', desc: '3D Splat Point Cloud' }
            ].map((fmt) => (
              <button
                key={fmt.id}
                onClick={() => setSelectedFormat(fmt.id as any)}
                className={`
                  p-2.5 rounded-xl border text-left flex flex-col transition-all
                  ${selectedFormat === fmt.id
                    ? 'bg-cyan-500/20 border-cyan-500 text-cyan-300 shadow-md'
                    : 'bg-slate-950/60 border-slate-800 text-slate-400 hover:border-slate-700 hover:text-slate-200'
                  }
                `}
              >
                <span className="text-xs font-bold text-slate-200">{fmt.name}</span>
                <span className="text-[10px] text-slate-400 mt-0.5">{fmt.desc}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Decimation & Texture Settings */}
        <div className="space-y-3 p-3.5 bg-slate-950/70 border border-slate-800 rounded-xl">
          <div className="flex items-center justify-between text-xs font-medium text-slate-300">
            <span>Target Polygon Decimation</span>
            <span className="font-mono text-cyan-400">{targetPolycount.toLocaleString()} Polys</span>
          </div>
          <input
            type="range"
            min={5000}
            max={character.polyCount}
            step={1000}
            value={targetPolycount}
            onChange={(e) => setTargetPolycount(Number(e.target.value))}
            className="w-full accent-cyan-400"
          />

          <div className="pt-2 border-t border-slate-800/80 flex items-center justify-between">
            <label className="text-xs text-slate-300 flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={includePbrTextures}
                onChange={(e) => setIncludePbrTextures(e.target.checked)}
                className="rounded accent-cyan-500"
              />
              Bake 4K PBR Texture Pack (Albedo, Normal, Roughness, Metalness, AO)
            </label>
          </div>
        </div>

        {/* Actions */}
        <div className="flex items-center justify-end gap-3 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2.5 rounded-xl border border-slate-700 text-xs font-semibold text-slate-300 hover:bg-slate-800 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={downloadReady ? handleTriggerDownload : handleExport}
            disabled={isExporting}
            className="px-6 py-2.5 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-white text-xs font-bold uppercase tracking-wider transition-all shadow-lg shadow-cyan-900/30 flex items-center gap-2"
          >
            {isExporting ? (
              <>Processing Mesh & Textures...</>
            ) : downloadReady ? (
              <>
                <Check className="w-4 h-4" />
                Download {selectedFormat.toUpperCase()} File
              </>
            ) : (
              <>
                <Download className="w-4 h-4" />
                Prepare Download
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
