import React from 'react';
import type { Asset } from '../types';
import { imageSrc } from '../lib/api';

/**
 * Procedural stand-in preview, art-directed to read like a studio render:
 * gradient backdrop, floor falloff, contact shadow, key highlight and rim.
 * A real generation replaces this with its reference image or rendered GLB.
 */
const SHAPES: Record<Asset['seedShape'], React.ReactNode> = {
  figure: (
    <g>
      <ellipse cx="60" cy="36" rx="12.5" ry="14" />
      <path d="M47.5 51h25l5.5 27-7 2.5-2 24h-18.5l-2-24-7-2.5z" />
      <path d="M45.5 54l-8.5 22 6 2.5 8-20zM74.5 54l8.5 22-6 2.5-8-20z" opacity=".9" />
      <path d="M52 104.5l-1.5-9h8l-1 9zM69.5 104.5l-1.5-9h-8l1 9z" opacity=".8" />
    </g>
  ),
  mech: (
    <g>
      <path d="M40 28h40a5 5 0 015 5v18a5 5 0 01-5 5H40a5 5 0 01-5-5V33a5 5 0 015-5z" />
      <path d="M33 60h54a7 7 0 017 7v20a7 7 0 01-7 7H33a7 7 0 01-7-7V67a7 7 0 017-7z" opacity=".96" />
      <rect x="18" y="63" width="10" height="26" rx="4" opacity=".82" />
      <rect x="92" y="63" width="10" height="26" rx="4" opacity=".82" />
      <rect x="47" y="96" width="11" height="12" rx="3" opacity=".7" />
      <rect x="62" y="96" width="11" height="12" rx="3" opacity=".7" />
    </g>
  ),
  creature: (
    <g>
      <path d="M31 72c0-19.5 13-33 29-33s29 13.5 29 33c0 14-12.5 22-29 22s-29-8-29-22z" />
      <path d="M42 44l-9-19 20.5 9zM78 44l9-19-20.5 9z" opacity=".92" />
      <path d="M44 92l-3 12h9l1.5-11zM76 92l3 12h-9l-1.5-11z" opacity=".78" />
    </g>
  ),
  prop: (
    <g>
      <path d="M60 20l33 18.5v37L60 94 27 75.5v-37z" />
      <path d="M60 20l33 18.5L60 57 27 38.5z" opacity=".62" />
      <path d="M60 57v37L27 75.5v-37z" opacity=".34" />
    </g>
  ),
  vehicle: (
    <g>
      <path d="M27 63h66l-9-19H36z" opacity=".9" />
      <path d="M20 62h80a6 6 0 016 6v11a6 6 0 01-6 6H20a6 6 0 01-6-6V68a6 6 0 016-6z" />
      <circle cx="36" cy="89" r="9.5" opacity=".88" />
      <circle cx="84" cy="89" r="9.5" opacity=".88" />
    </g>
  ),
};

export const AssetThumb: React.FC<{ asset: Asset; className?: string }> = ({ asset, className }) => {
  // Backend thumbs are API-relative ("/files/…"); resolve them against the API
  // origin, not the Vite origin the page is served from.
  const thumb = imageSrc(asset.thumbUrl);
  if (thumb) {
    return (
      <img
        src={thumb}
        alt={asset.name}
        // 20+ full-size JPEGs decoded eagerly is the single biggest memory hit
        // on this page; let the browser skip what is off-screen.
        loading="lazy"
        decoding="async"
        className={className}
        style={{ objectFit: 'cover' }}
      />
    );
  }
  const id = asset.id.replace(/[^a-zA-Z0-9]/g, '');
  return (
    <svg viewBox="0 0 120 120" className={className} preserveAspectRatio="xMidYMid slice">
      <defs>
        <radialGradient id={`b${id}`} cx="50%" cy="28%" r="80%">
          <stop offset="0%" stopColor={asset.tint} stopOpacity=".55" />
          <stop offset="45%" stopColor={asset.tint} stopOpacity=".16" />
          <stop offset="100%" stopColor="#0b0c0f" />
        </radialGradient>
        <linearGradient id={`f${id}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#0b0c0f" stopOpacity="0" />
          <stop offset="100%" stopColor="#08090b" stopOpacity=".92" />
        </linearGradient>
        {/* key light from upper-left, tint bounce from below */}
        <linearGradient id={`m${id}`} x1="0.15" y1="0" x2="0.75" y2="1">
          <stop offset="0%" stopColor="#ffffff" stopOpacity=".97" />
          <stop offset="45%" stopColor={asset.tint} stopOpacity=".95" />
          <stop offset="100%" stopColor={asset.tint} stopOpacity=".55" />
        </linearGradient>
        <radialGradient id={`s${id}`} cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#000" stopOpacity=".62" />
          <stop offset="100%" stopColor="#000" stopOpacity="0" />
        </radialGradient>
      </defs>

      <rect width="120" height="120" fill={`url(#b${id})`} />
      <rect y="72" width="120" height="48" fill={`url(#f${id})`} />
      <ellipse cx="60" cy="107" rx="36" ry="8" fill={`url(#s${id})`} />
      <g fill={`url(#m${id})`}>{SHAPES[asset.seedShape]}</g>
      {/* specular sheen */}
      <ellipse cx="44" cy="34" rx="26" ry="18" fill="#fff" opacity=".07" />
    </svg>
  );
};
