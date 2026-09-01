import React, { useState, useRef } from 'react';
import { 
  CharacterPreset, 
  AIModelType, 
  GenerationJob, 
  GenerationSpeed, 
  CharacterStyle 
} from '../types';
import { RodinExamplesGrid } from './RodinExamplesGrid';
import { RodinShowcaseItem } from '../data/rodinExamples';
import { 
  Image as ImageIcon, 
  Wand2, 
  Globe2, 
  Plus, 
  Check, 
  Sliders, 
  Lock, 
  Unlock, 
  ChevronLeft, 
  ChevronRight, 
  ChevronDown, 
  ChevronUp, 
  Sparkles, 
  Layers, 
  Box, 
  Clock, 
  RefreshCw, 
  X, 
  Upload, 
  Eye, 
  Menu,
  Maximize2,
  Grid,
  ChevronDown as ChevronDownIcon
} from 'lucide-react';

interface RodinHeroHubProps {
  onStartGeneration: (job: GenerationJob) => void;
  isGenerating: boolean;
  activeJob: GenerationJob | null;
  selectedCharacter: CharacterPreset;
  onOpenStudioViewport: () => void;
  credits: number;
}

export const RodinHeroHub: React.FC<RodinHeroHubProps> = ({
  onStartGeneration,
  isGenerating,
  activeJob,
  selectedCharacter,
  onOpenStudioViewport,
  credits
}) => {
  // Navigation tabs
  const [topTab, setTopTab] = useState<'avatar' | '3d' | 'video'>('3d');
  const [leftNav, setLeftNav] = useState<'image-to-3d' | '3d-editing' | 'world-gen'>('image-to-3d');
  const [inputSubMode, setInputSubMode] = useState<'image' | 'text'>('image');
  
  // Right tool style icons
  const [selectedStyleFilter, setSelectedStyleFilter] = useState<number>(0);
  
  // Model version & settings
  const [modelVersion, setModelVersion] = useState<'Gen-2.5' | 'Gen-2.0' | 'TRELLIS-2'>('Gen-2.5');
  const [qualityTier, setQualityTier] = useState<'High' | 'Ultra 4K' | 'Fast'>('High');
  const [batchCount, setBatchCount] = useState<number>(1);
  const [isLocked, setIsLocked] = useState<boolean>(false);
  const [showExamplesGrid, setShowExamplesGrid] = useState<boolean>(false);
  const [selectedExampleId, setSelectedExampleId] = useState<string | undefined>(undefined);

  // Input states
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [promptText, setPromptText] = useState<string>(
    'Full body cybernetic samurai in carbon-fiber battle armor, photon katana, ultra-detailed 3D game asset'
  );
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleImageSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      const url = URL.createObjectURL(file);
      setImagePreview(url);
    }
  };

  const handleSelectExample = (item: RodinShowcaseItem) => {
    setSelectedExampleId(item.id);
    setPromptText(item.prompt);
    setImagePreview(item.imageUrl);
    setInputSubMode('image');
    setShowExamplesGrid(false);
  };

  const handleGenerateClick = () => {
    const job: GenerationJob = {
      id: 'rodin-job-' + Date.now(),
      prompt: promptText,
      referenceImage: imagePreview || undefined,
      model: modelVersion === 'TRELLIS-2' ? 'trellis-2.0' : 'hybrid-pipeline',
      style: 'cyberpunk',
      speed: qualityTier === 'Fast' ? 'speedy' : qualityTier === 'Ultra 4K' ? 'extreme-4k' : 'default',
      seed: 42,
      symmetry: true,
      textureRes: qualityTier === 'Ultra 4K' ? '4096x4096' : '2048x2048',
      targetPolyBudget: 48000,
      status: 'generating-multiview',
      progress: 15,
      createdAt: new Date()
    };
    onStartGeneration(job);
  };

  return (
    <div className="relative w-full h-full min-h-screen flex flex-col items-center justify-between px-4 py-6 select-none overflow-y-auto overflow-x-hidden bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-[#3A2935] via-[#1E1720] to-[#0D0A10] text-slate-100 font-sans">
      {/* Background Ambient Glows */}
      <div className="absolute top-1/4 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[350px] bg-gradient-to-r from-pink-500/10 via-purple-600/15 to-indigo-500/10 blur-[130px] pointer-events-none rounded-full" />
      <div className="absolute bottom-10 left-1/2 -translate-x-1/2 w-[700px] h-[220px] bg-gradient-to-r from-purple-900/20 via-pink-900/25 to-rose-900/20 blur-[140px] pointer-events-none rounded-full" />

      {/* TOP NAVIGATION BAR PILL */}
      <header className="z-30 flex items-center justify-between w-full max-w-5xl">
        <button
          onClick={() => setShowExamplesGrid(!showExamplesGrid)}
          className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold transition-all border ${
            showExamplesGrid 
              ? 'bg-[#3E293B] border-pink-500/50 text-pink-300 shadow-md' 
              : 'bg-[#282329]/80 border-white/10 text-slate-400 hover:text-slate-200'
          }`}
          title="Browse 12 Archetype Examples"
        >
          <Grid className="w-3.5 h-3.5 text-pink-400" />
          <span>Examples</span>
        </button>

        {/* Center Pill Menu (Matching Screenshot) */}
        <div className="flex items-center p-1 bg-[#282329]/80 backdrop-blur-xl rounded-full border border-white/10 shadow-lg shadow-black/40 text-xs font-semibold">
          <button
            onClick={() => setTopTab('avatar')}
            className={`px-4 py-1.5 rounded-full transition-all ${
              topTab === 'avatar' ? 'bg-[#48424A] text-white shadow-sm' : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            Avatar
          </button>
          
          <button
            onClick={() => setTopTab('3d')}
            className={`px-5 py-1.5 rounded-full transition-all ${
              topTab === '3d' ? 'bg-[#48424A] text-white shadow-sm' : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            3D
          </button>

          <button
            onClick={() => setTopTab('video')}
            className={`px-4 py-1.5 rounded-full flex items-center gap-1.5 transition-all ${
              topTab === 'video' ? 'bg-[#48424A] text-white shadow-sm' : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <span>Video</span>
            <span className="w-1.5 h-1.5 rounded-full bg-rose-500 animate-pulse" />
            <Menu className="w-3 h-3 text-slate-400 ml-0.5" />
          </button>
        </div>

        {/* Right Credits & 3D Viewport Launcher */}
        <div className="flex items-center gap-2">
          <button
            onClick={onOpenStudioViewport}
            className="flex items-center gap-1.5 px-3.5 py-1.5 bg-[#282329]/80 hover:bg-[#38313A] border border-white/10 rounded-full text-xs font-medium text-slate-300 transition-colors shadow-md"
            title="Open Full 3D Viewport Studio"
          >
            <Box className="w-3.5 h-3.5 text-pink-400" />
            <span className="hidden sm:inline">Studio View</span>
          </button>
        </div>
      </header>

      {/* CONDITIONAL VIEW: 12-EXAMPLES GRID (SCREENSHOT 2) vs HERO HUB (SCREENSHOT 1) */}
      {showExamplesGrid ? (
        <div className="z-20 my-6 w-full flex justify-center">
          <RodinExamplesGrid
            onSelectExample={handleSelectExample}
            selectedExampleId={selectedExampleId}
          />
        </div>
      ) : (
        <>
          {/* CENTER HERO TITLE & SLOGAN */}
          <div className="z-20 flex flex-col items-center text-center mt-2 mb-4 max-w-2xl">
            {/* Rodin Serif Title */}
            <h1 className="text-7xl sm:text-8xl md:text-9xl font-serif font-black tracking-tight text-white drop-shadow-[0_4px_24px_rgba(0,0,0,0.6)]">
              Rodin
            </h1>

            {/* Subtitle Version Tag */}
            <div className="flex items-center gap-1.5 mt-1 mb-3 text-xs font-mono font-bold text-slate-300 tracking-wider">
              <span>Gen-2.5 (0702)</span>
              <span className="w-1.5 h-1.5 rounded-full bg-rose-500" />
            </div>

            {/* Philosophical Slogan */}
            <p className="text-xs sm:text-sm text-slate-300/80 font-normal leading-relaxed max-w-md">
              The best way to understand is to create.<br />
              What I cannot create, I do not understand.
            </p>
          </div>

          {/* MAIN GENERATIVE INTERACTIVE HUB (Center Component Matrix) */}
          <div className="z-20 flex items-center justify-center gap-3 sm:gap-4 my-auto w-full max-w-4xl">
            {/* LEFT VERTICAL TOOLBAR */}
            <div className="flex flex-col gap-2 p-1.5 bg-[#251F26]/70 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl shrink-0">
              <button
                onClick={() => {
                  setLeftNav('image-to-3d');
                  setInputSubMode('image');
                }}
                className={`p-2.5 rounded-xl flex flex-col items-center gap-1 transition-all ${
                  leftNav === 'image-to-3d'
                    ? 'bg-[#3E293B] border border-pink-500/60 text-pink-200 shadow-md shadow-pink-950/50'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-[#322834]'
                }`}
              >
                <ImageIcon className="w-4 h-4 text-pink-300" />
                <span className="text-[10px] font-bold">Image to 3D</span>
              </button>

              <button
                onClick={() => {
                  setLeftNav('3d-editing');
                  setInputSubMode('text');
                }}
                className={`p-2.5 rounded-xl flex flex-col items-center gap-1 transition-all ${
                  leftNav === '3d-editing'
                    ? 'bg-[#3E293B] border border-pink-500/60 text-pink-200 shadow-md'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-[#322834]'
                }`}
              >
                <Wand2 className="w-4 h-4 text-purple-300" />
                <span className="text-[10px] font-bold">3D Editing</span>
              </button>

              <button
                onClick={() => setLeftNav('world-gen')}
                className={`p-2.5 rounded-xl flex flex-col items-center gap-1 transition-all ${
                  leftNav === 'world-gen'
                    ? 'bg-[#3E293B] border border-pink-500/60 text-pink-200 shadow-md'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-[#322834]'
                }`}
              >
                <Globe2 className="w-4 h-4 text-cyan-300" />
                <span className="text-[10px] font-bold">WorldGen</span>
              </button>
            </div>

            {/* CENTER MAIN CARD (Image / Text Dropzone) */}
            <div className="relative w-64 sm:w-72 h-64 sm:h-72 bg-[#241D25]/90 backdrop-blur-2xl border border-white/10 rounded-3xl p-4 flex flex-col justify-between items-center shadow-2xl shadow-black/60 group">
              {/* Card Header Label */}
              <div className="flex items-center gap-1.5 text-xs font-bold text-white tracking-wide">
                {inputSubMode === 'image' ? (
                  <>
                    <ImageIcon className="w-3.5 h-3.5 text-pink-400" />
                    <span>Image to 3D</span>
                  </>
                ) : (
                  <>
                    <Wand2 className="w-3.5 h-3.5 text-purple-400" />
                    <span>Text to 3D</span>
                  </>
                )}
              </div>

              {/* Central Upload / Dropzone or Prompt Box */}
              {inputSubMode === 'image' ? (
                <div 
                  onClick={() => fileInputRef.current?.click()}
                  className="flex-1 w-full flex flex-col items-center justify-center cursor-pointer my-2"
                >
                  {imagePreview ? (
                    <div className="relative w-full h-full rounded-2xl overflow-hidden border border-pink-500/40 group/preview">
                      <img src={imagePreview} alt="Reference" className="w-full h-full object-cover" />
                      <div className="absolute inset-0 bg-black/60 opacity-0 group-hover/preview:opacity-100 flex items-center justify-center text-xs font-bold text-white transition-opacity">
                        Click to Change Image
                      </div>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          setImagePreview(null);
                        }}
                        className="absolute top-2 right-2 p-1 rounded-full bg-black/70 text-white hover:bg-rose-600 transition-colors"
                      >
                        <X className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  ) : (
                    <div className="w-16 h-16 rounded-2xl bg-[#322734] border border-white/10 flex items-center justify-center text-slate-300 hover:text-white hover:border-pink-500/60 hover:scale-105 transition-all shadow-lg">
                      <Plus className="w-8 h-8 stroke-[1.5]" />
                    </div>
                  )}
                  <input
                    ref={fileInputRef}
                    type="file"
                    accept="image/*"
                    onChange={handleImageSelect}
                    className="hidden"
                  />
                </div>
              ) : (
                <div className="flex-1 w-full flex flex-col justify-center my-2">
                  <textarea
                    value={promptText}
                    onChange={(e) => setPromptText(e.target.value)}
                    rows={4}
                    className="w-full bg-[#1A141C] border border-white/10 rounded-2xl p-3 text-xs text-slate-100 placeholder-slate-500 focus:outline-none focus:border-pink-500/60 resize-none font-sans leading-relaxed"
                    placeholder="Describe character pose, armor, materials, and geometry..."
                  />
                </div>
              )}

              {/* Bottom Card Pill Toggle */}
              <button
                onClick={() => setInputSubMode(inputSubMode === 'image' ? 'text' : 'image')}
                className="w-full py-2 px-4 rounded-2xl bg-gradient-to-r from-[#4A3245] via-[#3F2B3D] to-[#362638] hover:from-[#5A3B54] hover:to-[#453046] border border-pink-500/30 text-pink-200 text-xs font-bold tracking-wide transition-all shadow-md active:scale-98"
              >
                {inputSubMode === 'image' ? 'Text to Image/3D' : 'Switch to Image Input'}
              </button>
            </div>

            {/* RIGHT VERTICAL STYLE / SHADER ICON BUTTONS */}
            <div className="flex flex-col gap-2 p-1.5 bg-[#251F26]/70 backdrop-blur-xl border border-white/10 rounded-2xl shadow-2xl shrink-0">
              {[
                { id: 0, icon: 'slash', hasBadge: true },
                { id: 1, icon: 'box' },
                { id: 2, icon: 'cubes' },
                { id: 3, icon: 'mesh' }
              ].map((btn) => (
                <button
                  key={btn.id}
                  onClick={() => setSelectedStyleFilter(btn.id)}
                  className={`w-9 h-9 rounded-xl flex items-center justify-center relative transition-all ${
                    selectedStyleFilter === btn.id
                      ? 'bg-[#432E40] border border-pink-500/60 text-pink-300 shadow-md'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-[#322834]'
                  }`}
                >
                  {btn.icon === 'slash' && (
                    <div className="w-4 h-4 border border-current rounded-full flex items-center justify-center relative">
                      <div className="w-full h-px bg-current rotate-45" />
                    </div>
                  )}
                  {btn.icon === 'box' && <Box className="w-4 h-4" />}
                  {btn.icon === 'cubes' && <Layers className="w-4 h-4" />}
                  {btn.icon === 'mesh' && <Sparkles className="w-4 h-4" />}

                  {/* Orange Checkmark Badge on first icon */}
                  {btn.hasBadge && (
                    <div className="absolute -top-1 -right-1 w-3.5 h-3.5 bg-orange-500 text-white rounded-full flex items-center justify-center ring-2 ring-[#251F26]">
                      <Check className="w-2.5 h-2.5 stroke-[3]" />
                    </div>
                  )}
                </button>
              ))}
            </div>
          </div>
        </>
      )}

      {/* GENERATION PROGRESS INDICATOR (If active) */}
      {isGenerating && activeJob && (
        <div className="z-30 w-full max-w-md bg-[#251C28]/95 backdrop-blur-xl border border-pink-500/50 rounded-2xl p-3.5 flex flex-col gap-2 shadow-2xl shadow-pink-950/80 animate-fade-in my-2">
          <div className="flex items-center justify-between text-xs">
            <span className="font-bold text-pink-200 flex items-center gap-2">
              <RefreshCw className="w-3.5 h-3.5 animate-spin text-pink-400" />
              {activeJob.status === 'generating-multiview' && '1. Synthesizing 2D View Priors...'}
              {activeJob.status === 'synthesizing-latent' && '2. Generating 3D Structured Latent (SLaD)...'}
              {activeJob.status === 'extracting-mesh' && '3. Extracting Quad Mesh Topology...'}
              {activeJob.status === 'baking-pbr' && '4. Baking 4K PBR Texture Maps...'}
            </span>
            <span className="font-mono font-bold text-pink-300">{activeJob.progress}%</span>
          </div>
          <div className="w-full bg-black/50 rounded-full h-1.5 overflow-hidden">
            <div
              className="bg-gradient-to-r from-pink-500 via-purple-500 to-rose-500 h-full transition-all duration-300 shadow-sm"
              style={{ width: `${activeJob.progress}%` }}
            />
          </div>
        </div>
      )}

      {/* BOTTOM GENERATE ACTION BAR & CONTROLS */}
      <footer className="z-20 flex flex-col items-center gap-4 w-full max-w-3xl mb-2">
        {/* Main Action Line */}
        <div className="flex items-center justify-center gap-3 w-full">
          {/* Lock / Preset Pill */}
          <button
            onClick={() => setIsLocked(!isLocked)}
            className={`w-11 h-11 rounded-2xl flex items-center justify-center border transition-all ${
              isLocked
                ? 'bg-[#432E40] border-pink-500 text-pink-300'
                : 'bg-[#29222B]/80 border-white/10 text-slate-300 hover:bg-[#352C38]'
            }`}
            title="Lock Generation Settings"
          >
            {isLocked ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
          </button>

          {/* HUGE GLOWING "GENERATE" BUTTON */}
          <button
            onClick={handleGenerateClick}
            disabled={isGenerating}
            className={`
              relative px-12 sm:px-16 py-3.5 rounded-full font-black text-sm sm:text-base tracking-[0.2em] uppercase transition-all duration-300
              ${isGenerating
                ? 'bg-[#3A2D39] text-slate-500 cursor-not-allowed border border-white/5'
                : 'bg-gradient-to-r from-[#623E59] via-[#8C527B] to-[#623E59] hover:from-[#76486B] hover:via-[#A05C8C] hover:to-[#76486B] text-white shadow-[0_0_35px_rgba(219,39,119,0.35)] hover:shadow-[0_0_50px_rgba(219,39,119,0.55)] border border-pink-400/40 active:scale-95'
              }
            `}
          >
            {isGenerating ? (
              <span className="flex items-center gap-2">
                <RefreshCw className="w-4 h-4 animate-spin" />
                Generating...
              </span>
            ) : (
              <span>GENERATE</span>
            )}
          </button>

          {/* Multiplier & Settings Pill */}
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setBatchCount(batchCount === 1 ? 2 : batchCount === 2 ? 4 : 1)}
              className="px-3 py-2.5 rounded-2xl bg-[#29222B]/80 hover:bg-[#352C38] border border-white/10 text-xs font-bold text-pink-200 flex items-center gap-1 transition-colors"
              title="Batch Output Count"
            >
              <span>×{batchCount}</span>
              <ChevronRight className="w-3 h-3 text-slate-400" />
            </button>

            <button
              onClick={() => setShowExamplesGrid(!showExamplesGrid)}
              className={`p-2.5 rounded-2xl border transition-colors ${
                showExamplesGrid 
                  ? 'bg-pink-500/20 border-pink-500 text-pink-300' 
                  : 'bg-[#29222B]/80 border-white/10 text-slate-300 hover:text-white hover:bg-[#352C38]'
              }`}
              title="Toggle 12 Template Examples"
            >
              <Grid className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* BOTTOM PILLS: MODEL VERSION & QUALITY BADGES */}
        <div className="flex items-center gap-3 text-xs font-semibold">
          {/* Version Picker Pill */}
          <button
            onClick={() => setModelVersion(modelVersion === 'Gen-2.5' ? 'TRELLIS-2' : modelVersion === 'TRELLIS-2' ? 'Gen-2.0' : 'Gen-2.5')}
            className="flex items-center gap-1 px-3.5 py-1 bg-[#261E28]/80 hover:bg-[#332735] border border-pink-500/25 rounded-full text-pink-300 font-bold transition-colors"
          >
            <ChevronLeft className="w-3 h-3 text-slate-400" />
            <span>{modelVersion}</span>
            <ChevronRight className="w-3 h-3 text-slate-400" />
          </button>

          {/* Quality Indicator Pill */}
          <button
            onClick={() => setQualityTier(qualityTier === 'High' ? 'Ultra 4K' : qualityTier === 'Ultra 4K' ? 'Fast' : 'High')}
            className="flex items-center gap-1.5 px-3.5 py-1 bg-[#261E28]/80 hover:bg-[#332735] border border-pink-500/25 rounded-full text-pink-300 font-bold transition-colors"
          >
            <Clock className="w-3 h-3 text-pink-400" />
            <span>{qualityTier}</span>
            <span className="text-[10px] text-slate-400">⇅</span>
          </button>
        </div>
      </footer>
    </div>
  );
};
