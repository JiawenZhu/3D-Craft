import React, { useState } from 'react';
import { 
  CharacterStyle, 
  AIModelType, 
  GenerationJob, 
  GenerationInputMode, 
  GenerationSpeed,
  MultiViewImages
} from '../types';
import { 
  Sparkles, 
  Wand2, 
  Image as ImageIcon, 
  Sliders, 
  Play, 
  RefreshCw, 
  Upload, 
  ShieldCheck, 
  Layers, 
  Compass, 
  Zap, 
  Settings2, 
  ChevronDown, 
  ChevronUp, 
  Check,
  Camera,
  X
} from 'lucide-react';

interface GenerationPanelProps {
  selectedModel: AIModelType;
  speed: GenerationSpeed;
  onGenerate: (job: GenerationJob) => void;
  isGenerating: boolean;
  activeJob: GenerationJob | null;
}

const STYLE_OPTIONS: { id: CharacterStyle; label: string; icon: string }[] = [
  { id: 'cyberpunk', label: 'Cyberpunk', icon: '⚡' },
  { id: 'stylized-anime', label: 'Anime Stylized', icon: '✨' },
  { id: 'aaa-photorealistic', label: 'AAA Realistic', icon: '🎮' },
  { id: 'fantasy-rpg', label: 'Fantasy RPG', icon: '🛡️' },
  { id: 'scifi-mech', label: 'Sci-Fi Mech', icon: '🤖' },
  { id: 'clay-sculpt', label: 'Clay Sculpt', icon: '🗿' },
  { id: 'figurine-chibi', label: 'Figurine / Chibi', icon: '🧸' },
  { id: 'low-poly', label: 'Low-Poly Game', icon: '💎' }
];

const PROMPT_TOKENS = [
  '#Cyberpunk',
  '#HardSurface',
  '#PBR-4K',
  '#Quad-Topology',
  '#T-Pose',
  '#MechArmor',
  '#GenshinStyle',
  '#DarkFantasy'
];

export const GenerationPanel: React.FC<GenerationPanelProps> = ({
  selectedModel,
  speed,
  onGenerate,
  isGenerating,
  activeJob
}) => {
  const [inputMode, setInputMode] = useState<GenerationInputMode>('text');
  const [prompt, setPrompt] = useState('Full body cyber samurai operative in obsidian nanite armor, glowing photon katana, cybernetic optics, tactical gear, unreal engine 5 game-ready asset');
  const [selectedStyle, setSelectedStyle] = useState<CharacterStyle>('cyberpunk');
  const [singleImage, setSingleImage] = useState<string | null>(null);
  const [multiViews, setMultiViews] = useState<MultiViewImages>({});
  const [activeMultiSlot, setActiveMultiSlot] = useState<'front' | 'left' | 'right' | 'back'>('front');
  
  // Advanced parameters
  const [isAdvancedOpen, setIsAdvancedOpen] = useState<boolean>(false);
  const [seed, setSeed] = useState<number>(42);
  const [symmetry, setSymmetry] = useState<boolean>(true);
  const [textureRes, setTextureRes] = useState<'2048x2048' | '4096x4096'>('4096x4096');
  const [polyBudget, setPolyBudget] = useState<number>(45000);

  const handleSingleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setSingleImage(url);
    }
  };

  const handleMultiViewUpload = (slot: 'front' | 'left' | 'right' | 'back', e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setMultiViews(prev => ({ ...prev, [slot]: url }));
    }
  };

  const handleAppendToken = (token: string) => {
    if (!prompt.includes(token)) {
      setPrompt(prev => prev.trim() + ` ${token}`);
    }
  };

  const handleAiEnhancePrompt = () => {
    const enhancements = [
      ', highly detailed PBR textures, clean quad remeshed topology, symmetric T-pose, raytraced subsurface scattering, 4K normal maps, cinematic studio lighting',
      ', intricate mechanical joints, metallic carbon armor, emissive power conduit trim, crisp silhouette, Unreal Engine 5 Nanite mesh',
      ', stylized hand-painted anime aesthetics, vibrant cel-shaded color palette, crisp contour edges, game ready low draw-call asset'
    ];
    const picked = enhancements[Math.floor(Math.random() * enhancements.length)];
    setPrompt(prev => prev.replace(/, highly detailed.*/, '') + picked);
  };

  const handleStartGeneration = () => {
    const newJob: GenerationJob = {
      id: 'job-' + Date.now(),
      prompt,
      referenceImage: inputMode === 'image' ? singleImage || undefined : undefined,
      multiViewImages: inputMode === 'multiview' ? multiViews : undefined,
      model: selectedModel,
      style: selectedStyle,
      speed,
      seed,
      symmetry,
      textureRes,
      targetPolyBudget: polyBudget,
      status: 'generating-multiview',
      progress: 10,
      createdAt: new Date()
    };
    onGenerate(newJob);
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Input Mode Selector: Text vs Single Image vs Multi-View */}
      <div>
        <label className="text-xs font-bold uppercase tracking-wider text-slate-300 block mb-2">
          Input Modality
        </label>
        <div className="grid grid-cols-3 p-1 bg-[#0A0E18] rounded-xl border border-[#1A2234]">
          <button
            onClick={() => setInputMode('text')}
            className={`
              py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
              ${inputMode === 'text'
                ? 'bg-gradient-to-r from-cyan-500 to-blue-600 text-white shadow-md shadow-cyan-950/50'
                : 'text-slate-400 hover:text-slate-200'
              }
            `}
          >
            <Wand2 className="w-3.5 h-3.5" />
            <span>Text to 3D</span>
          </button>
          
          <button
            onClick={() => setInputMode('image')}
            className={`
              py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
              ${inputMode === 'image'
                ? 'bg-gradient-to-r from-cyan-500 to-blue-600 text-white shadow-md shadow-cyan-950/50'
                : 'text-slate-400 hover:text-slate-200'
              }
            `}
          >
            <ImageIcon className="w-3.5 h-3.5" />
            <span>Single Image</span>
          </button>

          <button
            onClick={() => setInputMode('multiview')}
            className={`
              py-2 text-[11px] font-bold rounded-lg flex items-center justify-center gap-1.5 transition-all
              ${inputMode === 'multiview'
                ? 'bg-gradient-to-r from-cyan-500 to-blue-600 text-white shadow-md shadow-cyan-950/50'
                : 'text-slate-400 hover:text-slate-200'
              }
            `}
          >
            <Compass className="w-3.5 h-3.5" />
            <span>Multi-View</span>
          </button>
        </div>
      </div>

      {/* Input Area based on Selected Mode */}
      {inputMode === 'text' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <label className="text-xs font-bold uppercase tracking-wider text-slate-300">
              3D Prompt Description
            </label>
            <button
              onClick={handleAiEnhancePrompt}
              className="text-[11px] font-semibold text-cyan-400 hover:text-cyan-300 flex items-center gap-1 transition-colors px-2 py-0.5 rounded bg-cyan-500/10 border border-cyan-500/20"
              title="Enhance prompt with 3D production tokens"
            >
              <Sparkles className="w-3 h-3 text-cyan-400" />
              <span>AI Auto-Enhance</span>
            </button>
          </div>

          <textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            rows={3}
            className="w-full bg-[#0A0D14] border border-[#1E293B] rounded-xl p-3 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 resize-none font-sans leading-relaxed shadow-inner"
            placeholder="Describe armor, pose, weapon, topology, and aesthetic details..."
          />

          {/* Quick Prompt Tokens */}
          <div className="flex items-center gap-1.5 flex-wrap">
            {PROMPT_TOKENS.map((tok) => (
              <button
                key={tok}
                onClick={() => handleAppendToken(tok)}
                className="text-[10px] px-2 py-0.5 rounded-full bg-[#121826] border border-[#1E293B] text-slate-400 hover:text-cyan-300 hover:border-cyan-500/50 transition-colors font-mono"
              >
                {tok}
              </button>
            ))}
          </div>
        </div>
      )}

      {inputMode === 'image' && (
        <div className="flex flex-col gap-2">
          <label className="text-xs font-bold uppercase tracking-wider text-slate-300">
            Reference Concept Image
          </label>
          <label className="border-2 border-dashed border-[#1E293B] hover:border-cyan-500/60 rounded-xl p-4 flex flex-col items-center justify-center gap-2 cursor-pointer bg-[#0A0D14] transition-colors relative group">
            {singleImage ? (
              <div className="relative w-full h-36 rounded-lg overflow-hidden border border-[#1E293B]">
                <img src={singleImage} alt="Reference" className="w-full h-full object-cover" />
                <div className="absolute inset-0 bg-black/60 opacity-0 group-hover:opacity-100 flex items-center justify-center text-xs font-bold text-white transition-opacity">
                  Click to Replace Concept Art
                </div>
              </div>
            ) : (
              <>
                <div className="p-3 bg-[#121826] rounded-full text-slate-400 group-hover:text-cyan-400 group-hover:scale-110 transition-all">
                  <Upload className="w-5 h-5" />
                </div>
                <div className="text-xs font-medium text-slate-300 text-center">
                  Drop concept art image or <span className="text-cyan-400 font-bold">browse</span>
                </div>
                <div className="text-[10px] text-slate-500 font-mono">
                  PNG, JPG, WebP (Auto-Removes Background)
                </div>
              </>
            )}
            <input type="file" accept="image/*" onChange={handleSingleImageUpload} className="hidden" />
          </label>
        </div>
      )}

      {inputMode === 'multiview' && (
        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between">
            <label className="text-xs font-bold uppercase tracking-wider text-slate-300">
              Multi-View Turnaround (4 Angles)
            </label>
            <span className="text-[10px] text-slate-400 font-mono">
              {Object.keys(multiViews).length}/4 Angles
            </span>
          </div>

          <div className="grid grid-cols-4 gap-2">
            {(['front', 'left', 'right', 'back'] as const).map((slot) => {
              const img = multiViews[slot];
              return (
                <label
                  key={slot}
                  className={`
                    border border-dashed rounded-xl p-2 flex flex-col items-center justify-center gap-1.5 cursor-pointer relative transition-all h-24
                    ${img
                      ? 'border-cyan-500/70 bg-cyan-950/20'
                      : 'border-[#1E293B] bg-[#0A0D14] hover:border-slate-700'
                    }
                  `}
                >
                  {img ? (
                    <img src={img} alt={slot} className="w-full h-14 object-cover rounded" />
                  ) : (
                    <Camera className="w-4 h-4 text-slate-500" />
                  )}
                  <span className="text-[10px] uppercase font-bold text-slate-400 font-mono">{slot}</span>
                  <input
                    type="file"
                    accept="image/*"
                    onChange={(e) => handleMultiViewUpload(slot, e)}
                    className="hidden"
                  />
                </label>
              );
            })}
          </div>
        </div>
      )}

      {/* Style Matrix */}
      <div>
        <label className="text-xs font-bold uppercase tracking-wider text-slate-300 block mb-2">
          Art Direction & Aesthetic
        </label>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-1.5">
          {STYLE_OPTIONS.map((style) => (
            <button
              key={style.id}
              onClick={() => setSelectedStyle(style.id)}
              className={`
                p-2 rounded-xl text-left border flex items-center gap-2 transition-all
                ${selectedStyle === style.id
                  ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 border-cyan-500 text-cyan-300 shadow-sm shadow-cyan-950/50'
                  : 'bg-[#0E1320] border-[#1A2234] text-slate-400 hover:border-slate-700 hover:text-slate-200'
                }
              `}
            >
              <span className="text-sm shrink-0">{style.icon}</span>
              <span className="text-[11px] font-bold truncate">{style.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Collapsible Advanced Parameters */}
      <div className="border border-[#1A2234] rounded-xl overflow-hidden bg-[#0A0E18]">
        <button
          onClick={() => setIsAdvancedOpen(!isAdvancedOpen)}
          className="w-full p-3 flex items-center justify-between text-xs font-bold text-slate-300 hover:text-white transition-colors"
        >
          <span className="flex items-center gap-1.5">
            <Settings2 className="w-3.5 h-3.5 text-cyan-400" />
            Advanced Production Parameters
          </span>
          {isAdvancedOpen ? <ChevronUp className="w-4 h-4" /> : <ChevronDown className="w-4 h-4" />}
        </button>

        {isAdvancedOpen && (
          <div className="p-3 pt-0 border-t border-[#1A2234] space-y-3">
            {/* Random Seed */}
            <div className="flex items-center justify-between text-xs">
              <span className="text-slate-400">Random Seed</span>
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  value={seed}
                  onChange={(e) => setSeed(Number(e.target.value))}
                  className="w-20 bg-[#121826] border border-slate-800 rounded px-2 py-1 text-xs font-mono text-cyan-400 text-right focus:outline-none focus:border-cyan-500"
                />
                <button
                  onClick={() => setSeed(Math.floor(Math.random() * 999999))}
                  className="p-1 rounded bg-[#121826] border border-slate-800 hover:text-cyan-300 text-slate-400"
                  title="Randomize"
                >
                  <RefreshCw className="w-3 h-3" />
                </button>
              </div>
            </div>

            {/* Symmetry Constraint */}
            <div className="flex items-center justify-between text-xs">
              <span className="text-slate-400">X-Axis Bilateral Symmetry</span>
              <button
                onClick={() => setSymmetry(!symmetry)}
                className={`px-2.5 py-1 rounded text-[11px] font-bold font-mono border transition-colors ${
                  symmetry ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/50' : 'bg-slate-900 text-slate-500 border-slate-800'
                }`}
              >
                {symmetry ? 'ENABLED' : 'DISABLED'}
              </button>
            </div>

            {/* PBR Texture Res */}
            <div className="flex items-center justify-between text-xs">
              <span className="text-slate-400">PBR Texture Resolution</span>
              <div className="flex items-center gap-1">
                {(['2048x2048', '4096x4096'] as const).map(res => (
                  <button
                    key={res}
                    onClick={() => setTextureRes(res)}
                    className={`px-2 py-0.5 rounded text-[10px] font-mono border ${
                      textureRes === res ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/50' : 'bg-slate-900 text-slate-500 border-slate-800'
                    }`}
                  >
                    {res.split('x')[0]}
                  </button>
                ))}
              </div>
            </div>

            {/* Target Polycount Slider */}
            <div>
              <div className="flex items-center justify-between text-xs mb-1">
                <span className="text-slate-400">Target Poly Budget</span>
                <span className="font-mono text-cyan-400 text-[11px]">{(polyBudget / 1000).toFixed(0)}k Quads</span>
              </div>
              <input
                type="range"
                min={10000}
                max={100000}
                step={5000}
                value={polyBudget}
                onChange={(e) => setPolyBudget(Number(e.target.value))}
                className="w-full accent-cyan-400"
              />
            </div>
          </div>
        )}
      </div>

      {/* Real-time Multi-Stage Progress Card */}
      {isGenerating && activeJob && (
        <div className="bg-[#0D1424] border border-cyan-500/60 rounded-xl p-3.5 flex flex-col gap-2.5 shadow-lg shadow-cyan-950/80 animate-fade-in">
          <div className="flex items-center justify-between text-xs">
            <span className="font-bold text-cyan-300 flex items-center gap-2">
              <RefreshCw className="w-3.5 h-3.5 animate-spin text-cyan-400" />
              {activeJob.status === 'generating-multiview' && 'Synthesizing Multi-View Priors...'}
              {activeJob.status === 'synthesizing-latent' && 'Sampling 3D Structured Latents (SLaD)...'}
              {activeJob.status === 'extracting-mesh' && 'Extracting Quad Mesh & Marching Cubes...'}
              {activeJob.status === 'baking-pbr' && 'Baking 4K PBR Albedo, Normal & Roughness...'}
            </span>
            <span className="text-cyan-400 font-mono font-bold">{activeJob.progress}%</span>
          </div>

          <div className="w-full bg-[#050810] rounded-full h-2 overflow-hidden border border-slate-800">
            <div
              className="bg-gradient-to-r from-cyan-500 via-blue-500 to-purple-500 h-full transition-all duration-300 shadow-sm shadow-cyan-400"
              style={{ width: `${activeJob.progress}%` }}
            />
          </div>

          <div className="grid grid-cols-4 gap-1 text-[9px] font-mono text-center pt-1">
            <div className={`py-1 rounded ${activeJob.progress >= 25 ? 'text-cyan-300 font-bold bg-cyan-950/40' : 'text-slate-600'}`}>
              1. MultiView
            </div>
            <div className={`py-1 rounded ${activeJob.progress >= 50 ? 'text-cyan-300 font-bold bg-cyan-950/40' : 'text-slate-600'}`}>
              2. Latent 3D
            </div>
            <div className={`py-1 rounded ${activeJob.progress >= 75 ? 'text-cyan-300 font-bold bg-cyan-950/40' : 'text-slate-600'}`}>
              3. Quad Mesh
            </div>
            <div className={`py-1 rounded ${activeJob.progress >= 95 ? 'text-cyan-300 font-bold bg-cyan-950/40' : 'text-slate-600'}`}>
              4. 4K PBR
            </div>
          </div>
        </div>
      )}

      {/* Generate Action Button */}
      <button
        onClick={handleStartGeneration}
        disabled={isGenerating}
        className={`
          w-full py-3.5 px-4 rounded-xl font-black text-xs uppercase tracking-wider flex items-center justify-center gap-2 transition-all shadow-xl
          ${isGenerating
            ? 'bg-slate-800 text-slate-500 cursor-not-allowed border border-slate-700'
            : 'bg-gradient-to-r from-cyan-500 via-blue-600 to-indigo-600 hover:from-cyan-400 hover:to-indigo-500 text-white shadow-cyan-950/70 hover:shadow-cyan-500/20 active:scale-[0.99] border border-cyan-400/40'
          }
        `}
      >
        <Zap className="w-4 h-4 fill-current text-amber-300" />
        {isGenerating ? (
          <span>Generating 3D Character ({activeJob?.progress || 10}%)...</span>
        ) : (
          <span className="flex items-center gap-1.5">
            Generate 3D Model <span className="text-amber-300 text-[10px] font-mono">• 10 Credits</span>
          </span>
        )}
      </button>

      <div className="text-[10px] text-slate-500 text-center flex items-center justify-center gap-1 font-medium">
        <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
        Production-grade 3D assets ready for Unreal 5, Unity, Blender & WebGL
      </div>
    </div>
  );
};
