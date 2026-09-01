import React, { useState } from 'react';
import { ModelSelector } from './components/ModelSelector';
import { GenerationPanel } from './components/GenerationPanel';
import { Viewport3D } from './components/Viewport3D';
import { MaterialInspector } from './components/MaterialInspector';
import { AssetGallery } from './components/AssetGallery';
import { ExportModal } from './components/ExportModal';
import { SUPPORTED_MODELS } from './data/models';
import { SAMPLE_CHARACTERS } from './data/presets';
import { 
  AIModelType, 
  CharacterPreset, 
  RenderMode, 
  LightingPreset, 
  GenerationJob, 
  GenerationSpeed 
} from './types';
import { 
  Box, 
  ExternalLink, 
  Download, 
  RotateCw, 
  Sparkles,
  Layers,
  Activity,
  Flame
} from 'lucide-react';

export const App: React.FC = () => {
  const [selectedModel, setSelectedModel] = useState<AIModelType>('trellis-2.0');
  const [generationSpeed, setGenerationSpeed] = useState<GenerationSpeed>('default');
  const [characterList, setCharacterList] = useState<CharacterPreset[]>(SAMPLE_CHARACTERS);
  const [selectedCharacter, setSelectedCharacter] = useState<CharacterPreset>(SAMPLE_CHARACTERS[0]);
  
  const [renderMode, setRenderMode] = useState<RenderMode>('pbr');
  const [lighting, setLighting] = useState<LightingPreset>('studio');
  const [autoRotate, setAutoRotate] = useState<boolean>(true);
  const [wireframe, setWireframe] = useState<boolean>(false);

  const [isExportModalOpen, setIsExportModalOpen] = useState<boolean>(false);
  const [isGenerating, setIsGenerating] = useState<boolean>(false);
  const [activeJob, setActiveJob] = useState<GenerationJob | null>(null);

  const handleStartGeneration = (job: GenerationJob) => {
    setIsGenerating(true);
    setActiveJob(job);

    const stages: GenerationJob['status'][] = [
      'generating-multiview',
      'synthesizing-latent',
      'extracting-mesh',
      'baking-pbr',
      'completed'
    ];

    const stepDuration = job.speed === 'speedy' ? 700 : job.speed === 'extreme-4k' ? 1400 : 1000;

    stages.forEach((stage, idx) => {
      setTimeout(() => {
        if (stage === 'completed') {
          setIsGenerating(false);
          setActiveJob(null);

          const newChar: CharacterPreset = {
            id: 'gen-' + Date.now(),
            title: job.prompt.length > 28 ? job.prompt.slice(0, 28) + '...' : job.prompt,
            style: job.style,
            prompt: job.prompt,
            thumbnail: job.referenceImage || '/images/gallery/orange_creature.jpg',
            glbUrl: '/models/cyber_samurai.glb',
            modelType: job.model,
            polyCount: job.targetPolyBudget || 48000,
            vertexCount: Math.round((job.targetPolyBudget || 48000) * 0.52),
            textureRes: job.textureRes || '4096 x 4096',
            geometryColor: '#06B6D4',
            metallic: 0.8,
            roughness: 0.2,
            emissiveIntensity: 2.5,
            hasBones: true,
            segments: ['head', 'torso', 'arms', 'legs', 'weapon', 'accessories']
          };

          setCharacterList((prev) => [newChar, ...prev]);
          setSelectedCharacter(newChar);
        } else {
          setActiveJob((prev) => prev ? {
            ...prev,
            status: stage,
            progress: Math.min(100, Math.round(((idx + 1) / stages.length) * 100))
          } : null);
        }
      }, (idx + 1) * stepDuration);
    });
  };

  const currentModelInfo = SUPPORTED_MODELS.find(m => m.id === selectedModel) || SUPPORTED_MODELS[0];

  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden bg-[#07090E] text-slate-100 font-sans select-none">
      {/* Top Navigation Bar */}
      <header className="h-14 border-b border-slate-800/80 bg-slate-950/80 backdrop-blur-md px-5 flex items-center justify-between z-30 shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl bg-gradient-to-tr from-cyan-500 via-blue-500 to-purple-600 flex items-center justify-center shadow-lg shadow-cyan-500/20">
            <Box className="w-4 h-4 text-white" />
          </div>
          <div>
            <div className="font-extrabold text-sm tracking-tight text-white flex items-center gap-2">
              RODIN <span className="text-cyan-400 font-semibold">3D STUDIO</span>
              <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded-full bg-cyan-500/10 text-cyan-400 border border-cyan-500/30">
                v2.0 Beta
              </span>
            </div>
            <div className="text-[10px] text-slate-400 font-medium">
              Inspired by Hyper3D Rodin • Powered by Microsoft TRELLIS & Hunyuan3D
            </div>
          </div>
        </div>

        {/* Quick Links & Actions */}
        <div className="flex items-center gap-3">
          <div className="hidden md:flex items-center gap-2 px-3 py-1 bg-slate-900 border border-slate-800 rounded-full text-xs text-slate-300">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-ping" />
            <span className="text-[11px] font-mono">Engine: {currentModelInfo.name}</span>
          </div>

          <a
            href="https://huggingface.co/spaces/microsoft/TRELLIS.2"
            target="_blank"
            rel="noreferrer"
            className="hidden sm:flex items-center gap-1 text-xs text-slate-400 hover:text-cyan-400 px-3 py-1.5 rounded-lg hover:bg-slate-900 transition-colors"
          >
            <span>TRELLIS Space</span>
            <ExternalLink className="w-3 h-3" />
          </a>

          <a
            href="https://huggingface.co/spaces/tencent/Hunyuan3D-2.1"
            target="_blank"
            rel="noreferrer"
            className="hidden sm:flex items-center gap-1 text-xs text-slate-400 hover:text-cyan-400 px-3 py-1.5 rounded-lg hover:bg-slate-900 transition-colors"
          >
            <span>Hunyuan3D Space</span>
            <ExternalLink className="w-3 h-3" />
          </a>

          <button
            onClick={() => setIsExportModalOpen(true)}
            className="px-4 py-2 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-white text-xs font-bold uppercase tracking-wider flex items-center gap-1.5 shadow-lg shadow-cyan-950/60 transition-all active:scale-[0.98]"
          >
            <Download className="w-3.5 h-3.5" />
            Export 3D Asset
          </button>
        </div>
      </header>

      {/* Main Studio Body Layout */}
      <div className="flex flex-1 min-h-0 overflow-hidden relative">
        {/* Left Sidebar: Generative Controls & Model Hub */}
        <aside className="w-80 lg:w-96 border-r border-slate-800/80 bg-slate-950/60 backdrop-blur-md p-4 flex flex-col gap-5 overflow-y-auto shrink-0 z-20">
          <ModelSelector
            selectedModel={selectedModel}
            onSelectModel={setSelectedModel}
            speed={generationSpeed}
            onSelectSpeed={setGenerationSpeed}
          />

          <div className="w-full h-px bg-slate-800/80" />

          <GenerationPanel
            selectedModel={selectedModel}
            speed={generationSpeed}
            onGenerate={handleStartGeneration}
            isGenerating={isGenerating}
            activeJob={activeJob}
          />
        </aside>

        {/* Center: Interactive 3D Viewport */}
        <main className="flex-1 relative flex flex-col min-w-0 bg-[#05070C]">
          {/* Floating Viewport Overlays & Toolbar */}
          <div className="absolute top-4 left-4 z-10 flex items-center gap-2">
            <div className="px-3 py-1.5 bg-slate-900/80 backdrop-blur-md border border-slate-800 rounded-xl text-xs font-semibold text-slate-200 flex items-center gap-2 shadow-lg">
              <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: selectedCharacter.geometryColor }} />
              <span className="truncate max-w-[180px]">{selectedCharacter.title}</span>
              <span className="text-slate-500">|</span>
              <span className="text-[11px] font-mono text-cyan-400">{(selectedCharacter.polyCount / 1000).toFixed(1)}k Polys</span>
            </div>
          </div>

          {/* Lighting & Camera Toolbar */}
          <div className="absolute top-4 right-4 z-10 flex items-center gap-2 bg-slate-900/80 backdrop-blur-md border border-slate-800 p-1.5 rounded-xl shadow-lg">
            {/* Auto-Rotate Toggle */}
            <button
              onClick={() => setAutoRotate(!autoRotate)}
              className={`p-1.5 rounded-lg text-xs font-medium transition-colors flex items-center gap-1 ${
                autoRotate ? 'bg-cyan-500/20 text-cyan-400' : 'text-slate-400 hover:text-white'
              }`}
              title="Toggle Turntable Auto-Rotate"
            >
              <RotateCw className="w-3.5 h-3.5" />
            </button>

            <div className="w-px h-4 bg-slate-800" />

            {/* Lighting Preset Picker */}
            <div className="flex items-center gap-1 text-[11px]">
              {(['studio', 'cyberpunk', 'sunset', 'dramatic'] as LightingPreset[]).map((lt) => (
                <button
                  key={lt}
                  onClick={() => setLighting(lt)}
                  className={`px-2 py-1 rounded-lg capitalize transition-colors ${
                    lighting === lt
                      ? 'bg-slate-800 text-cyan-400 font-semibold'
                      : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  {lt}
                </button>
              ))}
            </div>
          </div>

          {/* 3D WebGL Canvas */}
          <div className="flex-1 w-full h-full">
            <Viewport3D
              character={selectedCharacter}
              renderMode={renderMode}
              onSetRenderMode={setRenderMode}
              lighting={lighting}
              onSetLighting={setLighting}
              autoRotate={autoRotate}
              onToggleAutoRotate={() => setAutoRotate(!autoRotate)}
              wireframe={wireframe}
            />
          </div>

          {/* Bottom Floating Viewport Helper */}
          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-10 px-4 py-1.5 bg-slate-900/80 backdrop-blur-md border border-slate-800 rounded-full text-[11px] text-slate-400 font-medium flex items-center gap-4 shadow-xl">
            <span>🖱️ Left Click: Rotate</span>
            <span>•</span>
            <span>Right Click / Shift: Pan</span>
            <span>•</span>
            <span>Scroll: Zoom</span>
          </div>
        </main>

        {/* Right Sidebar: Material Inspector & Asset Library */}
        <aside className="w-72 lg:w-80 border-l border-slate-800/80 bg-slate-950/60 backdrop-blur-md p-4 flex flex-col gap-5 overflow-y-auto shrink-0 z-20">
          <MaterialInspector
            character={selectedCharacter}
            renderMode={renderMode}
            onSetRenderMode={setRenderMode}
            wireframe={wireframe}
            onToggleWireframe={() => setWireframe(!wireframe)}
          />

          <div className="w-full h-px bg-slate-800/80" />

          <AssetGallery
            selectedCharacter={selectedCharacter}
            onSelectCharacter={setSelectedCharacter}
            assetList={characterList}
          />
        </aside>
      </div>

      {/* Export Modal */}
      <ExportModal
        isOpen={isExportModalOpen}
        onClose={() => setIsExportModalOpen(false)}
        character={selectedCharacter}
      />
    </div>
  );
};

export default App;
