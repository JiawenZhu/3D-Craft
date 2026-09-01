import React from 'react';
import { 
  Box, 
  Sparkles, 
  Download, 
  Zap, 
  Layers, 
  ExternalLink, 
  Sliders, 
  Scissors, 
  Bone, 
  Globe, 
  HelpCircle,
  Bell,
  Cloud,
  ChevronDown,
  CheckCircle2
} from 'lucide-react';
import { AIModelInfo } from '../types';

interface HeaderProps {
  currentModel: AIModelInfo;
  activeWorkspaceMode: 'generator' | 'omnicraft' | 'bang-to-parts';
  onSelectWorkspaceMode: (mode: 'generator' | 'omnicraft' | 'bang-to-parts') => void;
  assetTitle: string;
  onUpdateTitle: (title: string) => void;
  credits: number;
  onOpenExport: () => void;
}

export const Header: React.FC<HeaderProps> = ({
  currentModel,
  activeWorkspaceMode,
  onSelectWorkspaceMode,
  assetTitle,
  onUpdateTitle,
  credits,
  onOpenExport
}) => {
  return (
    <header className="h-14 border-b border-[#1A2234] bg-[#0A0D14]/95 backdrop-blur-xl px-4 lg:px-6 flex items-center justify-between z-40 shrink-0 select-none">
      {/* Left: Hyper3D Brand & Workspace Mode Switcher */}
      <div className="flex items-center gap-4 lg:gap-6">
        {/* Brand Identity */}
        <div className="flex items-center gap-2.5">
          <div className="relative flex items-center justify-center w-8 h-8 rounded-lg bg-gradient-to-tr from-cyan-500 via-blue-600 to-indigo-600 shadow-md shadow-cyan-500/25 ring-1 ring-white/20">
            <Box className="w-4 h-4 text-white" />
            <div className="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 bg-emerald-400 border-2 border-[#0A0D14] rounded-full" />
          </div>
          <div className="flex flex-col">
            <div className="flex items-center gap-2">
              <span className="font-black text-sm tracking-tight text-white font-sans">
                Hyper3D <span className="text-cyan-400 font-extrabold">RODIN</span>
              </span>
              <span className="text-[9px] uppercase tracking-wider font-mono font-bold px-1.5 py-0.5 rounded bg-cyan-500/10 text-cyan-300 border border-cyan-500/30">
                Gen-2
              </span>
            </div>
            <span className="text-[10px] text-slate-400 font-medium hidden sm:inline-block">
              Generative 3D Asset Studio
            </span>
          </div>
        </div>

        <div className="h-5 w-px bg-slate-800 hidden md:block" />

        {/* Workspace Modes Tabs */}
        <nav className="hidden md:flex items-center p-0.5 bg-[#121826] border border-[#1E293B] rounded-xl text-xs font-semibold">
          <button
            onClick={() => onSelectWorkspaceMode('generator')}
            className={`px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all ${
              activeWorkspaceMode === 'generator'
                ? 'bg-gradient-to-r from-cyan-500/20 to-blue-500/20 text-cyan-300 border border-cyan-500/40 shadow-sm'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5 text-cyan-400" />
            <span>Rodin 3D</span>
          </button>

          <button
            onClick={() => onSelectWorkspaceMode('omnicraft')}
            className={`px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all ${
              activeWorkspaceMode === 'omnicraft'
                ? 'bg-gradient-to-r from-indigo-500/20 to-purple-500/20 text-purple-300 border border-purple-500/40 shadow-sm'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Sliders className="w-3.5 h-3.5 text-purple-400" />
            <span>OmniCraft</span>
          </button>

          <button
            onClick={() => onSelectWorkspaceMode('bang-to-parts')}
            className={`px-3 py-1.5 rounded-lg flex items-center gap-1.5 transition-all ${
              activeWorkspaceMode === 'bang-to-parts'
                ? 'bg-gradient-to-r from-amber-500/20 to-orange-500/20 text-amber-300 border border-amber-500/40 shadow-sm'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Scissors className="w-3.5 h-3.5 text-amber-400" />
            <span>Bang-to-Parts</span>
          </button>
        </nav>
      </div>

      {/* Center: Editable Project Name & Cloud Sync */}
      <div className="hidden xl:flex items-center gap-2 px-3 py-1 bg-[#121826]/80 border border-[#1E293B] rounded-xl">
        <Cloud className="w-3.5 h-3.5 text-slate-500" />
        <input
          type="text"
          value={assetTitle}
          onChange={(e) => onUpdateTitle(e.target.value)}
          className="bg-transparent text-xs font-semibold text-slate-200 focus:outline-none focus:text-white border-b border-transparent focus:border-cyan-500 font-mono w-48 truncate"
          title="Click to rename asset"
        />
        <span className="text-[10px] text-emerald-400 font-mono flex items-center gap-1">
          <CheckCircle2 className="w-3 h-3" />
          Auto-Saved
        </span>
      </div>

      {/* Right: Credits, Pro Badge, Community, Export */}
      <div className="flex items-center gap-2.5 sm:gap-3.5">
        {/* Credits Badge */}
        <div className="flex items-center gap-1.5 px-3 py-1.5 bg-[#121826] border border-cyan-500/30 rounded-xl text-xs font-semibold shadow-sm shadow-cyan-950/40">
          <Zap className="w-3.5 h-3.5 text-amber-400 fill-amber-400 animate-pulse" />
          <span className="text-white font-mono">{credits}</span>
          <span className="text-slate-400 text-[11px]">Credits</span>
        </div>

        {/* Pro Badge */}
        <span className="hidden sm:inline-flex text-[10px] uppercase font-mono font-bold px-2 py-0.5 rounded-full bg-gradient-to-r from-purple-500/20 to-pink-500/20 text-purple-300 border border-purple-500/30">
          PRO TIER
        </span>

        {/* Community & Docs Links */}
        <a
          href="https://hyper3d.ai/workspace/rodin"
          target="_blank"
          rel="noreferrer"
          className="hidden lg:flex items-center gap-1 text-xs text-slate-400 hover:text-cyan-400 px-2.5 py-1 rounded-lg hover:bg-slate-900 transition-colors"
          title="Hyper3D Official Workspace"
        >
          <span>Hyper3D Docs</span>
          <ExternalLink className="w-3 h-3" />
        </a>

        {/* Export Button (Primary CTA) */}
        <button
          onClick={onOpenExport}
          className="px-3.5 sm:px-4 py-1.5 sm:py-2 rounded-xl bg-gradient-to-r from-cyan-500 via-blue-600 to-indigo-600 hover:from-cyan-400 hover:to-blue-500 text-white text-xs font-bold uppercase tracking-wider flex items-center gap-1.5 shadow-lg shadow-cyan-900/40 transition-all hover:scale-[1.02] active:scale-[0.98]"
        >
          <Download className="w-3.5 h-3.5" />
          <span>Export Asset</span>
        </button>
      </div>
    </header>
  );
};
