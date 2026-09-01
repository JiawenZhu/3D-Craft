import React from 'react';
import { cn } from '../../lib/cn';
import type { Direction } from '../../types';

/** Rodin's 3x3 + up/down direction grid, used to tag each reference view. */
const GRID: (Direction | null)[][] = [
  ['back-left', 'back', 'back-right'],
  ['left', 'up', 'right'],
  ['front-left', 'front', 'front-right'],
];

const LABEL: Record<Direction, string> = {
  unknown: 'Unknown', front: 'Front', 'front-left': 'Front Left', 'front-right': 'Front Right',
  left: 'Left', right: 'Right', back: 'Back', 'back-left': 'Back Left', 'back-right': 'Back Right',
  up: 'Up', down: 'Down',
};

export const DirectionPicker: React.FC<{ value: Direction; onChange: (d: Direction) => void }> = ({ value, onChange }) => (
  <div className="w-[196px]">
    <div className="mb-2.5 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">Select direction</div>
    <div className="grid grid-cols-3 gap-1">
      {GRID.flat().map((d, i) => (
        <button
          key={i}
          onClick={() => d && onChange(d)}
          className={cn(
            'h-9 rounded-lg border text-[9px] leading-tight transition-all',
            value === d
              ? 'border-white/70 bg-white/10 text-white'
              : 'border-white/8 bg-white/[0.03] text-chalk-faint hover:border-white/20 hover:text-chalk',
          )}
        >
          {d ? LABEL[d].replace(' ', '\n') : ''}
        </button>
      ))}
    </div>
    <div className="mt-1 grid grid-cols-2 gap-1">
      {(['down', 'unknown'] as Direction[]).map((d) => (
        <button
          key={d}
          onClick={() => onChange(d)}
          className={cn(
            'h-8 rounded-lg border text-[10px] transition-all',
            value === d ? 'border-white/70 bg-white/10 text-white' : 'border-white/8 bg-white/[0.03] text-chalk-faint hover:border-white/20 hover:text-chalk',
          )}
        >
          {LABEL[d]}
        </button>
      ))}
    </div>
    <p className="mt-2.5 text-[10px] leading-relaxed text-chalk-ghost">
      Images tagged with a direction measurably improve multi-view accuracy.
    </p>
  </div>
);
