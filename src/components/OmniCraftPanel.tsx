import React, { useState } from 'react';
import { 
  CharacterPreset, 
  RenderMode, 
  OmniCraftTab, 
  MeshSegment, 
  AnimationPose 
} from '../types';
import { 
  Sliders, 
  Scissors, 
  Bone, 
  Layers, 
  Sparkles, 
  Activity, 
  Wand2, 
  RefreshCw, 
  Check, 
  Play, 
  Square, 
  ShieldCheck,
  Palette,
  Eye,
  Hash,
  Download,
  Flame
} from 'lucide-react';

interface OmniCraftPanelProps {
  character: CharacterPreset;
  onUpdateCharacter: (char: CharacterPreset) => void;
  activeTab: OmniCraftTab;
  onSelectTab: (tab: OmniCraftTab) => void;
  renderMode: RenderMode;
  onSetRenderMode: (mode: RenderMode) => void;
  wireframe: boolean;
  onToggleWireframe: () => void;
  highlightSegment: MeshSegment;
  onSetHighlightSegment: (segment: MeshSegment) => void;
  activePose: AnimationPose;
  onSetPose: (pose: AnimationPose) => void;
}

export const OmniCraftPanel: React.FC<OmniCraftPanelProps> = ({
  character,
  onUpdateCharacter,
  activeTab,
  onSelectTab,
  renderMode,
  onSetRenderMode,
  wireframe,
  onToggleWireframe,
  highlightSegment,
  onSetHighlightSegment,
  activePose,
  onSetPose
}) => {
  // OmniCraft inpainting state
  const [selectedPart, setSelectedPart] = useState<MeshSegment>('weapon');
  const [inpaintPrompt, setInpaintPrompt] = useState('Change katana to dual plasma energy blades with cyan lightning aura');
  const [isInpainting, setIsInpainting] = useState(false);

  // Remesh state
  const [targetQuads, setTargetQuads] = useState(character.polyCount);
  const [isRemeshing, setIsRemeshing] = useState(false);
  const [isWatertight, setIsWatertight] = useState(false);

  // Material adjustments
  const [metallic, setMetallic] = useState(character.metallic);
  const [roughness, setRoughness] = useState(character.roughness);
  const [emissive, setEmissive] = useState(character.emissiveIntensity || 2.5);

  const handleApplyMaterialChanges = () => {
    onUpdateCharacter({
      ...character,
      metallic,
      roughness,
      emissiveIntensity: emissive
    });
  };

  const handleExecuteInpaint = () => {
    setIsInpainting(true);
    setTimeout(() => {
      setIsInpainting(false);
      onUpdateCharacter({
        ...character,
        title: `${character.title} (Omni Modified)`,
        geometryColor: '#06B6D4',
        polyCount: character.polyCount + 1200
      });
    }, 1500);
  };

  const handleExecuteRemesh = () => {
    setIsRemeshing(true);
    setTimeout(() => {
      setIsRemeshing(false);
      onUpdateCharacter({
        ...character,
        polyCount: targetQuads,
        vertexCount: Math.round(targetQuads * 0.52)
      });
    }, 1200);
  };

  return (
    <div className="flex flex-col gap-4">
      {/* OmniCraft Navigation Tabs */}
      <div className="grid grid-cols-3 p-1 bg-[#0A0E18] rounded-xl border border-[#1A2234]">
        <button
          onClick={() => onSelectTab('omnicraft')}
          className={`
            py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
            ${activeTab === 'omnicraft'
              ? 'bg-gradient-to-r from-purple-500/25 to-indigo-500/25 border border-purple-500/50 text-purple-300 shadow-sm'
              : 'text-slate-400 hover:text-slate-200'
            }
          `}
        >
          <Sliders className="w-3.5 h-3.5" />
          <span>OmniCraft</span>
        </button>

        <button
          onClick={() => onSelectTab('materials')}
          className={`
            py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
            ${activeTab === 'materials'
              ? 'bg-gradient-to-r from-cyan-500/25 to-blue-500/25 border border-cyan-500/50 text-cyan-300 shadow-sm'
              : 'text-slate-400 hover:text-slate-200'
            }
          `}
        >
          <Palette className="w-3.5 h-3.5" />
          <span>Material Lab</span>
        </button>

        <button
          onClick={() => onSelectTab('rigging')}
          className={`
            py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
            ${activeTab === 'rigging'
              ? 'bg-gradient-to-r from-amber-500/25 to-orange-500/25 border border-amber-500/50 text-amber-300 shadow-sm'
              : 'text-slate-400 hover:text-slate-200'
            }
          `}
        >
          <Bone className="w-3.5 h-3.5" />
          <span>Auto-Rig</span>
        </button>
      </div>

      {/* Tab 1: OmniCraft Suite */}
      {activeTab === 'omnicraft' && (
        <div className="flex flex-col gap-4">
          {/* Tool 1: AI Prompt-Based Inpainting / Region Edit */}
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-purple-300 flex items-center gap-1.5">
                <Wand2 className="w-3.5 h-3.5 text-purple-400" />
                Prompt-to-Edit (Inpainting)
              </span>
              <span className="text-[10px] font-mono bg-purple-500/10 text-purple-300 px-1.5 py-0.5 rounded border border-purple-500/20">
                Region AI
              </span>
            </div>

            {/* Select Target Segment */}
            <div>
              <label className="text-[11px] text-slate-400 block mb-1.5">Target Mesh Region</label>
              <div className="grid grid-cols-3 gap-1">
                {(['head', 'torso', 'arms', 'legs', 'weapon', 'accessories'] as MeshSegment[]).map((seg) => (
                  <button
                    key={seg}
                    onClick={() => {
                      setSelectedPart(seg);
                      onSetHighlightSegment(seg);
                    }}
                    className={`
                      py-1.5 px-2 text-[10px] uppercase font-bold rounded-lg border capitalize transition-all
                      ${selectedPart === seg
                        ? 'bg-purple-500/20 border-purple-500 text-purple-300'
                        : 'bg-slate-900 border-slate-800 text-slate-400 hover:border-slate-700'
                      }
                    `}
                  >
                    {seg}
                  </button>
                ))}
              </div>
            </div>

            {/* Inpaint Prompt */}
            <textarea
              value={inpaintPrompt}
              onChange={(e) => setInpaintPrompt(e.target.value)}
              rows={2}
              className="w-full bg-[#0A0D14] border border-[#1E293B] rounded-lg p-2.5 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-purple-500 resize-none font-sans"
              placeholder="Describe modification for selected mesh region..."
            />

            <button
              onClick={handleExecuteInpaint}
              disabled={isInpainting}
              className="w-full py-2 rounded-lg bg-gradient-to-r from-purple-500 to-indigo-600 hover:from-purple-400 hover:to-indigo-500 text-white text-xs font-bold uppercase tracking-wider flex items-center justify-center gap-1.5 transition-all shadow-md shadow-purple-950/40"
            >
              {isInpainting ? (
                <>
                  <RefreshCw className="w-3.5 h-3.5 animate-spin" />
                  Neural Inpainting in Progress...
                </>
              ) : (
                <>
                  <Sparkles className="w-3.5 h-3.5" />
                  Inpaint {selectedPart.toUpperCase()}
                </>
              )}
            </button>
          </div>

          {/* Tool 2: Bang-to-Parts (Mesh Segmentation) */}
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-2.5">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-amber-300 flex items-center gap-1.5">
                <Scissors className="w-3.5 h-3.5 text-amber-400" />
                Bang-to-Parts (Segmentation)
              </span>
              <span className="text-[10px] font-mono bg-amber-500/10 text-amber-300 px-1.5 py-0.5 rounded border border-amber-500/20">
                Modular 3D
              </span>
            </div>

            <p className="text-[11px] text-slate-400 leading-relaxed">
              Splits single unified character mesh into isolated hierarchical sub-components (Head, Torso, Limbs, Gear) for customization and game armor swapping.
            </p>

            <div className="flex items-center gap-2">
              <button
                onClick={() => onSetHighlightSegment(highlightSegment === 'weapon' ? 'all' : 'weapon')}
                className={`flex-1 py-1.5 px-2 rounded-lg text-[11px] font-bold border transition-colors ${
                  highlightSegment === 'weapon'
                    ? 'bg-amber-500/20 text-amber-300 border-amber-500/50'
                    : 'bg-slate-900 border-slate-800 text-slate-300 hover:border-slate-700'
                }`}
              >
                Isolate Gear & Katana
              </button>

              <button
                onClick={() => onSetHighlightSegment(highlightSegment === 'torso' ? 'all' : 'torso')}
                className={`flex-1 py-1.5 px-2 rounded-lg text-[11px] font-bold border transition-colors ${
                  highlightSegment === 'torso'
                    ? 'bg-amber-500/20 text-amber-300 border-amber-500/50'
                    : 'bg-slate-900 border-slate-800 text-slate-300 hover:border-slate-700'
                }`}
              >
                Isolate Chestplate
              </button>
            </div>
          </div>

          {/* Tool 3: Quad Remesh & Watertight Fix */}
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-cyan-300 flex items-center gap-1.5">
                <Layers className="w-3.5 h-3.5 text-cyan-400" />
                Quad Remeshing & Topology
              </span>
              <span className="text-[10px] font-mono text-cyan-400">
                {(targetQuads / 1000).toFixed(0)}k Quads
              </span>
            </div>

            <input
              type="range"
              min={10000}
              max={100000}
              step={2000}
              value={targetQuads}
              onChange={(e) => setTargetQuads(Number(e.target.value))}
              className="w-full accent-cyan-400"
            />

            <div className="flex items-center justify-between pt-1">
              <label className="text-xs text-slate-300 flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={isWatertight}
                  onChange={(e) => setIsWatertight(e.target.checked)}
                  className="rounded accent-cyan-500"
                />
                Watertight STL (3D Print Ready)
              </label>

              <button
                onClick={handleExecuteRemesh}
                disabled={isRemeshing}
                className="px-3 py-1 rounded bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 text-xs font-bold hover:bg-cyan-500/30 transition-colors"
              >
                {isRemeshing ? 'Remeshing...' : 'Execute Remesh'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Material Lab */}
      {activeTab === 'materials' && (
        <div className="flex flex-col gap-4">
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-cyan-300 flex items-center gap-1.5">
                <Palette className="w-3.5 h-3.5 text-cyan-400" />
                PBR Surface Tuning
              </span>
              <button
                onClick={onToggleWireframe}
                className={`text-[10px] px-2 py-0.5 rounded border transition-colors ${
                  wireframe
                    ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/50 font-bold'
                    : 'bg-slate-900 text-slate-400 border-slate-800'
                }`}
              >
                Wireframe: {wireframe ? 'ON' : 'OFF'}
              </button>
            </div>

            {/* Metallic Slider */}
            <div>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-slate-400">Metallic Factor</span>
                <span className="font-mono text-cyan-400">{metallic.toFixed(2)}</span>
              </div>
              <input
                type="range"
                min={0}
                max={1}
                step={0.05}
                value={metallic}
                onChange={(e) => {
                  setMetallic(Number(e.target.value));
                  onUpdateCharacter({ ...character, metallic: Number(e.target.value) });
                }}
                className="w-full accent-cyan-400"
              />
            </div>

            {/* Roughness Slider */}
            <div>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-slate-400">Roughness Factor</span>
                <span className="font-mono text-cyan-400">{roughness.toFixed(2)}</span>
              </div>
              <input
                type="range"
                min={0}
                max={1}
                step={0.05}
                value={roughness}
                onChange={(e) => {
                  setRoughness(Number(e.target.value));
                  onUpdateCharacter({ ...character, roughness: Number(e.target.value) });
                }}
                className="w-full accent-cyan-400"
              />
            </div>

            {/* Emissive Glow Intensity */}
            <div>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-slate-400">Emissive Conduit Glow</span>
                <span className="font-mono text-cyan-400">{emissive.toFixed(1)}x</span>
              </div>
              <input
                type="range"
                min={0}
                max={5}
                step={0.2}
                value={emissive}
                onChange={(e) => {
                  setEmissive(Number(e.target.value));
                  onUpdateCharacter({ ...character, emissiveIntensity: Number(e.target.value) });
                }}
                className="w-full accent-cyan-400"
              />
            </div>
          </div>

          {/* Shader Channel Swatches */}
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-2">
            <span className="text-xs font-bold uppercase tracking-wider text-slate-300">
              Texture Map Channels (4K 16-Bit)
            </span>
            <div className="grid grid-cols-2 gap-2 text-[11px] font-mono">
              <div className="bg-[#0A0D14] p-2 rounded-lg border border-slate-800 flex items-center justify-between">
                <span className="text-slate-400">Albedo (Base)</span>
                <span className="w-3.5 h-3.5 rounded" style={{ backgroundColor: character.geometryColor }} />
              </div>
              <div className="bg-[#0A0D14] p-2 rounded-lg border border-slate-800 flex items-center justify-between">
                <span className="text-slate-400">Normal Map</span>
                <span className="w-3.5 h-3.5 rounded bg-gradient-to-tr from-purple-500 to-cyan-500" />
              </div>
              <div className="bg-[#0A0D14] p-2 rounded-lg border border-slate-800 flex items-center justify-between">
                <span className="text-slate-400">Roughness</span>
                <span className="w-3.5 h-3.5 rounded bg-slate-400" />
              </div>
              <div className="bg-[#0A0D14] p-2 rounded-lg border border-slate-800 flex items-center justify-between">
                <span className="text-slate-400">Metallic</span>
                <span className="w-3.5 h-3.5 rounded bg-slate-200" />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Tab 3: Auto-Rigging & Skeletal Animation */}
      {activeTab === 'rigging' && (
        <div className="flex flex-col gap-4">
          <div className="p-3.5 bg-[#0E1320] border border-[#1A2234] rounded-xl flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-amber-300 flex items-center gap-1.5">
                <Bone className="w-3.5 h-3.5 text-amber-400" />
                Humanoid Biped Skeleton
              </span>
              <span className="text-[10px] font-mono bg-emerald-500/10 text-emerald-400 px-2 py-0.5 rounded border border-emerald-500/20">
                52 Joints Rigged
              </span>
            </div>

            <p className="text-[11px] text-slate-400 leading-relaxed">
              Standard Mixamo & Unreal Engine 5 compatible humanoid rig. Test live animation poses in the 3D viewport:
            </p>

            {/* Animation Clips */}
            <div className="grid grid-cols-2 gap-2">
              {[
                { id: 't-pose', label: 'T-Pose (Rest)', desc: 'Engine Standard' },
                { id: 'idle', label: 'Idle Stance', desc: 'Breathing Motion' },
                { id: 'walk', label: 'Combat Walk', desc: 'Forward Locomotion' },
                { id: 'combat', label: 'Battle Ready', desc: 'Dual Katana Guard' }
              ].map((pose) => (
                <button
                  key={pose.id}
                  onClick={() => onSetPose(pose.id as AnimationPose)}
                  className={`
                    p-2.5 rounded-xl border text-left flex flex-col transition-all
                    ${activePose === pose.id
                      ? 'bg-amber-500/20 border-amber-500 text-amber-300 shadow-sm'
                      : 'bg-slate-900/70 border-slate-800 text-slate-400 hover:border-slate-700 hover:text-slate-200'
                    }
                  `}
                >
                  <span className="text-xs font-bold">{pose.label}</span>
                  <span className="text-[9px] text-slate-500 font-mono mt-0.5">{pose.desc}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
