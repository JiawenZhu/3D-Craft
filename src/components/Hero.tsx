import React, { useEffect, useState } from 'react';
import { Menu } from 'lucide-react';
import { Wordmark } from './Wordmark';
import { Segmented } from './ui/primitives';
import { useStudio } from '../store/StudioContext';
import { engineById, TIPS } from '../data/engines';

/** The two-line strapline rotates in a fixed slot, as it does on the live site. */
const STRAPLINES = [
  ['The best way to understand is to create.', 'What I cannot create, I do not understand.'],
  ['Controllable large-scale generative models', 'for creating high-quality 3D assets.'],
  ['Slow down, zoom in.', 'The details are everything.'],
  ['Clean and sharp surfaces. No distractions.', 'Less is more.'],
  ['Your ideas, one workspace.', 'From image or text to concepts and 3D.'],
];

export const Hero: React.FC = () => {
  const { settings } = useStudio();
  const engine = engineById(settings.engine);
  const [product, setProduct] = useState<'avatar' | '3d'>('3d');
  const [line, setLine] = useState(0);
  const [tip, setTip] = useState(0);

  useEffect(() => {
    const a = window.setInterval(() => setLine((v) => (v + 1) % STRAPLINES.length), 7000);
    const b = window.setInterval(() => setTip((v) => (v + 1) % TIPS.length), 5500);
    return () => { window.clearInterval(a); window.clearInterval(b); };
  }, []);

  return (
    <div className="flex flex-col items-center text-center">
      <div className="mb-6 flex animate-riseIn items-center gap-1.5">
        <Segmented
          size="sm" value={product} onChange={setProduct}
          options={[{ value: 'avatar', label: 'Avatar' }, { value: '3d', label: '3D' }]}
        />
        <button className="grid h-[26px] w-[26px] place-items-center rounded-full border border-white/10 text-chalk-dim transition-colors hover:text-white">
          <Menu className="h-3.5 w-3.5" />
        </button>
      </div>

      <Wordmark />

      <div className="mt-2 rounded-[10px] px-2.5 py-0.5 text-[12.8px] font-medium text-chalk">
        {engine.release}
        <sup className="ml-1 text-[8px] text-coral">●</sup>
      </div>

      <div className="mt-3 flex h-[46px] flex-col justify-start">
        <p key={line} className="animate-riseIn text-[14px] leading-[23px] text-chalk-dim">
          {STRAPLINES[line][0]}
          <br />
          {STRAPLINES[line][1]}
        </p>
      </div>

      <div className="mt-2 h-4 overflow-hidden">
        <p key={tip} className="animate-riseIn text-[11px] text-chalk-ghost">{TIPS[tip]}</p>
      </div>
    </div>
  );
};
