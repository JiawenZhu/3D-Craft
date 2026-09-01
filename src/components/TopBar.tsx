import React, { useState } from 'react';
import {
  ChevronDown, Cpu, ExternalLink, Github, User, Wifi, WifiOff,
} from 'lucide-react';
import { cn } from '../lib/cn';
import { useStudio } from '../store/StudioContext';
import { ENGINES } from '../data/engines';
import { Popover, Tip } from './ui/primitives';

const TOOLS = [
  { name: 'Texture Generator', tag: 'PBR' },
  { name: 'Image Enhancer', tag: 'Free' },
  { name: 'Image Remix', tag: 'Beta' },
  { name: 'HDRI Generation', tag: '8K' },
  { name: 'Mesh Editor', tag: 'Web' },
  { name: 'Format Convertor', tag: 'GLB/FBX' },
];

export const TopBar: React.FC = () => {
  const { health, credits } = useStudio();
  const [toolsOpen, setToolsOpen] = useState(false);
  const [statusOpen, setStatusOpen] = useState(false);
  const online = !!health;

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex h-16 items-center justify-between px-5 sm:px-8">
      {/* left: product switcher, mirroring "ChatAvatar | Rodin" */}
      <nav className="flex items-center gap-1">
        <button className="rounded-full px-3 py-1.5 text-sm text-chalk-dim transition-colors duration-300 hover:text-white">
          ChatAvatar
        </button>
        <button className="rounded-full border border-white/12 bg-white/[0.06] px-3 py-1.5 text-sm text-white backdrop-blur-xl">
          Rodin
        </button>
        <div className="relative ml-1">
          <button
            onClick={() => setToolsOpen((v) => !v)}
            className="flex items-center gap-1 rounded-full px-3 py-1.5 text-sm text-chalk-dim transition-colors hover:text-white"
          >
            OmniCraft <ChevronDown className={cn('h-3.5 w-3.5 transition-transform', toolsOpen && 'rotate-180')} />
          </button>
          <Popover open={toolsOpen} onClose={() => setToolsOpen(false)} anchor="bottom" className="left-0 w-64">
            <div className="mb-3 text-[11px] uppercase tracking-[0.18em] text-chalk-faint">Toolbag for 3D</div>
            <div className="space-y-0.5">
              {TOOLS.map((t) => (
                <button key={t.name} className="flex w-full items-center justify-between rounded-lg px-2.5 py-2 text-left text-[13px] text-chalk transition-colors hover:bg-white/[0.06] hover:text-white">
                  {t.name}
                  <span className="rounded-full border border-white/10 px-1.5 py-0.5 font-mono text-[9px] text-chalk-faint">{t.tag}</span>
                </button>
              ))}
            </div>
          </Popover>
        </div>
      </nav>

      {/* right: engine health, credits, account */}
      <div className="flex items-center gap-2">
        <div className="relative">
          <button
            onClick={() => setStatusOpen((v) => !v)}
            className="rd-pill h-8 px-3 text-[11px]"
          >
            <span className={cn('h-1.5 w-1.5 rounded-full', online ? 'bg-emerald-400' : 'bg-amber-500/80')} />
            <span className="hidden font-mono text-chalk sm:inline">
              {online ? health!.device.toUpperCase() : 'PREVIEW'}
            </span>
            {online ? <Wifi className="h-3 w-3 text-chalk-faint" /> : <WifiOff className="h-3 w-3 text-chalk-faint" />}
          </button>
          <Popover open={statusOpen} onClose={() => setStatusOpen(false)} anchor="bottom" className="right-0 w-[300px]">
            <div className="mb-3 flex items-center gap-2 text-[11px] uppercase tracking-[0.18em] text-chalk-faint">
              <Cpu className="h-3.5 w-3.5" /> Local inference
            </div>
            {online ? (
              <>
                <div className="mb-3 flex items-center justify-between rounded-lg bg-white/[0.04] px-3 py-2 text-xs">
                  <span className="text-chalk-dim">device</span>
                  <span className="font-mono text-white">{health!.device} · torch {health!.torch}</span>
                </div>
                <div className="space-y-1.5">
                  {ENGINES.filter((e) => e.id !== 'hybrid').map((e) => {
                    const h = health!.engines?.[e.id];
                    return (
                      <div key={e.id} className="flex items-center justify-between text-xs">
                        <span className="text-chalk">{e.label}</span>
                        <span className={cn('font-mono text-[10px]', h?.loaded ? 'text-emerald-400' : h?.installed ? 'text-amber-400' : 'text-chalk-ghost')}>
                          {h?.loaded ? 'loaded' : h?.installed ? 'installed' : 'not installed'}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </>
            ) : (
              <p className="text-xs leading-relaxed text-chalk-dim">
                No inference server on <span className="font-mono text-chalk">127.0.0.1:8000</span>. The studio is running in
                preview mode — every control works and generations are simulated.
                <br /><br />
                Start it with <span className="font-mono text-white">npm run server</span>.
              </p>
            )}
            <div className="mt-4 flex gap-2">
              {ENGINES.slice(0, 2).map((e) => (
                <a key={e.id} href={e.spaceUrl} target="_blank" rel="noreferrer"
                   className="flex flex-1 items-center justify-center gap-1 rounded-lg border border-white/10 py-1.5 text-[10px] text-chalk-dim transition-colors hover:border-white/25 hover:text-white">
                  {e.vendor} <ExternalLink className="h-2.5 w-2.5" />
                </a>
              ))}
            </div>
          </Popover>
        </div>

        <Tip label="Credits are local & cosmetic — nothing is billed">
          <div className="rd-pill h-8 px-3 font-mono text-[11px] text-chalk">{credits.toFixed(1)}</div>
        </Tip>

        <a href="https://github.com/microsoft/TRELLIS" target="_blank" rel="noreferrer" className="rd-icon-btn h-8 w-8 border">
          <Github className="h-4 w-4" />
        </a>

        <button className="flex items-center gap-1.5 rounded-full px-2 py-1.5 text-sm text-chalk-dim transition-colors hover:text-white">
          <User className="h-4 w-4" /> <span className="hidden sm:inline">Login</span>
        </button>
      </div>
    </header>
  );
};
