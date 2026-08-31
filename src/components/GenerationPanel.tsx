import React, { useState } from 'react';
import { CharacterStyle, AIModelType, GenerationJob } from '../types';
import { Sparkles, Wand2, Image as ImageIcon, Sliders, Play, RefreshCw, Upload, ShieldCheck } from 'lucide-react';

interface GenerationPanelProps {
  selectedModel: AIModelType;
  onGenerate: (job: GenerationJob) => void;
  isGenerating: boolean;
  activeJob: GenerationJob | null;
}

const STYLE_OPTIONS: { id: CharacterStyle; label: string; icon: string }[] = [
  { id: 'cyberpunk', label: 'Cyberpunk', icon: '⚡' },
  { id: 'stylized-anime', label: 'Anime Style', icon: '✨' },
  { id: 'aaa-photorealistic', label: 'AAA Realistic', icon: '🎮' },
  { id: 'fantasy-rpg', label: 'Fantasy RPG', icon: '🛡️' },
  { id: 'scifi-mech', label: 'Sci-Fi Mech', icon: '🤖' },
  { id: 'low-poly', label: 'Low-Poly', icon: '💎' }
];

export const GenerationPanel: React.FC<GenerationPanelProps> = ({
  selectedModel,
  onGenerate,
  isGenerating,
  activeJob
}) => {
  const [activeTab, setActiveTab] = useState<'text' | 'image'>('text');
  const [prompt, setPrompt] = useState('Full body female cyberpunk assassin in nano-carbon combat armor, glowing dual energy blades, dynamic tactical pose, unreal engine 5');
  const [selectedStyle, setSelectedStyle] = useState<CharacterStyle>('cyberpunk');
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [enhancePrompt, setEnhancePrompt] = useState(true);

  const handleImageUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setImagePreview(url);
    }
  };

  const handleStartGeneration = () => {
    const newJob: GenerationJob = {
      id: 'job-' + Date.now(),
      prompt,
      referenceImage: imagePreview || undefined,
      model: selectedModel,
      style: selectedStyle,
      status: 'generating-multiview',
      progress: 10,
      createdAt: new Date()
    };
    onGenerate(newJob);
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Mode Switcher: Text-to-3D vs Image-to-3D */}
      <div className="grid grid-cols-2 p-1 bg-slate-900/80 rounded-xl border border-slate-800">
        <button
          onClick={() => setActiveTab('text')}
          className={`
            py-2 text-xs font-semibold rounded-lg flex items-center justify-center gap-1.5 transition-all
            ${activeTab === 'text'
              ? 'bg-gradient-to-r from-cyan-500 to-blue-600 text-white shadow-md'
              : 'text-slate-400 hover:text-slate-200'
            }
          `}
        >
          <Wand2 className="w-3.5 h-3.5" />
          Text to 3D Character
        </button>
        <button
          onClick={() => setActiveTab('image')}
          className={`
            py-2 text-xs font-semibold rounded-lg flex items-center justify-center gap-1.5 transition-all
            ${activeTab === 'image'
              ? 'bg-gradient-to-r from-cyan-500 to-blue-600 text-white shadow-md'
              : 'text-slate-400 hover:text-slate-200'
            }
          `}
        >
          <ImageIcon className="w-3.5 h-3.5" />
          Image to 3D Model
        </button>
      </div>

      {/* Style Chips */}
      <div>
        <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-2">
          Character Style & Art Direction
        </label>
        <div className="grid grid-cols-3 gap-1.5">
          {STYLE_OPTIONS.map((style) => (
            <button
              key={style.id}
              onClick={() => setSelectedStyle(style.id)}
              className={`
                px-2 py-2 rounded-lg text-xs font-medium border text-left flex items-center gap-1.5 transition-all
                ${selectedStyle === style.id
                  ? 'bg-cyan-500/20 border-cyan-500 text-cyan-300 shadow-sm'
                  : 'bg-slate-900/50 border-slate-800 text-slate-400 hover:border-slate-700 hover:text-slate-200'
                }
              `}
            >
              <span>{style.icon}</span>
              <span className="truncate">{style.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Prompt / Input Box */}
      {activeTab === 'text' ? (
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <label className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              3D Character Prompt
            </label>
            <button
              onClick={() => setEnhancePrompt(!enhancePrompt)}
              className={`text-[11px] flex items-center gap-1 transition-colors ${
                enhancePrompt ? 'text-cyan-400' : 'text-slate-500'
              }`}
            >
              <Sparkles className="w-3 h-3" />
              Auto-Enhance 3D Details
            </button>
          </div>
          <textarea
            value={prompt}
            onChange={(e) => setPrompt(e.target.value)}
            rows={3}
            className="w-full bg-slate-950/80 border border-slate-800 rounded-xl p-3 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-cyan-500 focus:ring-1 focus:ring-cyan-500 resize-none font-sans"
            placeholder="Describe armor, pose, weapon, topology, and aesthetic details..."
          />
        </div>
      ) : (
        <div>
          <label className="text-xs font-semibold uppercase tracking-wider text-slate-400 block mb-1.5">
            Reference Concept Art (Front / Multi-View)
          </label>
          <label className="border-2 border-dashed border-slate-800 hover:border-cyan-500/60 rounded-xl p-4 flex flex-col items-center justify-center gap-2 cursor-pointer bg-slate-950/50 transition-colors">
            {imagePreview ? (
              <div className="relative w-full h-32 rounded-lg overflow-hidden border border-slate-800">
                <img src={imagePreview} alt="Reference" className="w-full h-full object-cover" />
                <div className="absolute inset-0 bg-black/40 flex items-center justify-center text-xs font-semibold text-white">
                  Click to Replace Image
                </div>
              </div>
            ) : (
              <>
                <div className="p-3 bg-slate-900 rounded-full text-slate-400">
                  <Upload className="w-5 h-5" />
                </div>
                <div className="text-xs font-medium text-slate-300">
                  Drop reference image or <span className="text-cyan-400">browse</span>
                </div>
                <div className="text-[10px] text-slate-500 font-mono">
                  PNG, JPG, WebP up to 25MB
                </div>
              </>
            )}
            <input type="file" accept="image/*" onChange={handleImageUpload} className="hidden" />
          </label>
        </div>
      )}

      {/* Generation Progress Indicator */}
      {isGenerating && activeJob && (
        <div className="bg-slate-900/90 border border-cyan-500/40 rounded-xl p-3.5 flex flex-col gap-2.5 animate-pulse">
          <div className="flex items-center justify-between text-xs">
            <span className="font-semibold text-cyan-400 flex items-center gap-1.5">
              <RefreshCw className="w-3.5 h-3.5 animate-spin" />
              {activeJob.status === 'generating-multiview' && 'Synthesizing Multi-View Priors...'}
              {activeJob.status === 'synthesizing-latent' && 'Generating 3D Structured Latent...'}
              {activeJob.status === 'extracting-mesh' && 'Extracting High-Poly Quad Mesh...'}
              {activeJob.status === 'baking-pbr' && 'Baking 4K PBR Albedo & Normal Maps...'}
            </span>
            <span className="text-slate-400 font-mono">{activeJob.progress}%</span>
          </div>
          <div className="w-full bg-slate-950 rounded-full h-1.5 overflow-hidden">
            <div
              className="bg-gradient-to-r from-cyan-500 to-blue-500 h-full transition-all duration-300"
              style={{ width: `${activeJob.progress}%` }}
            />
          </div>
          <div className="text-[10px] text-slate-400 flex items-center justify-between font-mono">
            <span>Model: {selectedModel}</span>
            <span>Est: ~25s</span>
          </div>
        </div>
      )}

      {/* Primary Action Button */}
      <button
        onClick={handleStartGeneration}
        disabled={isGenerating}
        className={`
          w-full py-3 px-4 rounded-xl font-bold text-xs uppercase tracking-wider flex items-center justify-center gap-2 transition-all shadow-xl
          ${isGenerating
            ? 'bg-slate-800 text-slate-500 cursor-not-allowed'
            : 'bg-gradient-to-r from-cyan-500 via-blue-600 to-purple-600 hover:from-cyan-400 hover:to-purple-500 text-white shadow-cyan-900/30 hover:shadow-cyan-500/20 active:scale-[0.99]'
          }
        `}
      >
        <Play className="w-4 h-4 fill-current" />
        {isGenerating ? 'Generating 3D Asset...' : 'Generate 3D Game Character'}
      </button>

      <div className="text-[10px] text-slate-500 text-center flex items-center justify-center gap-1">
        <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
        Zero-egress local PyTorch or direct Hugging Face Space API
      </div>
    </div>
  );
};
