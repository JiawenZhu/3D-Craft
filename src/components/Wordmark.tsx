import React from 'react';
import { cn } from '../lib/cn';

/**
 * Rodin's hero logotype. The live mark is a 391×86 SVG whose stroke draws itself
 * in before filling; we match those dimensions exactly and use `textLength` so a
 * webfont lands on the same width instead of drifting with the font stack.
 */
export const Wordmark: React.FC<{ className?: string }> = ({ className }) => (
  <div className={cn('relative select-none', className)}>
    <svg viewBox="0 0 391 100" width={391} height={86} className="overflow-visible" role="img" aria-label="Rodin">
      <defs>
        <linearGradient id="rd-wm" x1="0" y1="0" x2="1" y2="0.4">
          <stop offset="0%" stopColor="#ffffff" />
          <stop offset="62%" stopColor="#f6f1f4" />
          <stop offset="100%" stopColor="#e9dbe7" />
        </linearGradient>
      </defs>
      {['stroke', 'fill'].map((layer) => (
        <text
          key={layer}
          x="195.5" y="83" textAnchor="middle"
          textLength="376" lengthAdjust="spacingAndGlyphs"
          fontFamily="'Playfair Display', Georgia, serif" fontSize="104" fontWeight={500}
          fill={layer === 'fill' ? 'url(#rd-wm)' : 'none'}
          stroke={layer === 'stroke' ? 'rgba(255,255,255,.9)' : undefined}
          strokeWidth={layer === 'stroke' ? 0.85 : undefined}
          opacity={layer === 'fill' ? 0 : 1}
          style={{ animation: layer === 'fill'
            ? 'rd-wm-in 1.2s cubic-bezier(.16,1,.3,1) .95s forwards'
            : 'rd-wm-out 1s ease 1.1s forwards' }}
        >
          Rodin
        </text>
      ))}
    </svg>
    <style>{`
      @keyframes rd-wm-out { to { opacity: 0 } }
      @keyframes rd-wm-in  { from { opacity: 0; filter: blur(7px) } to { opacity: 1; filter: none } }
    `}</style>
  </div>
);
