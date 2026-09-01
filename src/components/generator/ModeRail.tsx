import React from 'react';
import { Globe, Image as ImageIcon, Wand2 } from 'lucide-react';
import { cn } from '../../lib/cn';
import type { WorkMode } from '../../types';

const MODES: { id: WorkMode; label: string; Icon: React.ElementType }[] = [
  { id: 'image-to-3d', label: 'Image to 3D', Icon: ImageIcon },
  { id: '3d-editing', label: '3D Editing', Icon: Wand2 },
  { id: 'worldgen', label: 'WorldGen', Icon: Globe },
];

/**
 * The 76×132 frosted rail clipped to the left of the input card.
 * Geometry, radii and the active gradient are matched to the live workspace.
 */
export const ModeRail: React.FC<{ value: WorkMode; onChange: (m: WorkMode) => void }> = ({ value, onChange }) => (
  <div
    className="flex w-[76px] shrink-0 flex-col gap-[3px] rounded-xl p-[3px]"
    style={{ background: 'rgba(255,255,255,.043)', backdropFilter: 'blur(14px)' }}
  >
    {MODES.map(({ id, label, Icon }) => {
      const active = value === id;
      return (
        <button
          key={id}
          onClick={() => onChange(id)}
          className={cn(
            'group flex h-[42px] w-[69px] flex-col items-center justify-center gap-[3px] rounded-[9px] transition-all duration-300',
            active ? 'text-white' : 'text-chalk-faint hover:text-chalk',
          )}
          style={active ? { backgroundImage: 'var(--g-accent-soft)', boxShadow: 'inset 0 0 0 1px rgba(255,255,255,.14)' } : undefined}
        >
          <Icon className="h-[17px] w-[17px]" strokeWidth={1.6} />
          <span className="text-[8px] font-medium leading-none tracking-tight">{label}</span>
        </button>
      );
    })}
  </div>
);
