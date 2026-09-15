import React from 'react';
import { Box, Heart, Layers, Lock, Rotate3d, Trash2, Wand2 } from 'lucide-react';
import { cn } from '../lib/cn';
import type { Asset } from '../types';
import { AssetThumb } from './AssetThumb';
import { compact } from '../lib/format';
import { engineById } from '../data/engines';

export const AssetCard: React.FC<{
  asset: Asset;
  onOpen: (a: Asset) => void;
  onLike: (id: string) => void;
  onDelete?: (id: string) => void;
  /** Set when this reference image already has a generated mesh. */
  builtAsset?: Asset;
}> = ({ asset, onOpen, onLike, onDelete, builtAsset }) => (
  <button
    onClick={() => onOpen(asset)}
    className="group relative aspect-square overflow-hidden rounded-[28px] border border-white/[0.06] bg-white/[0.03] text-left transition-all duration-300 hover:border-white/20 hover:shadow-lift"
  >
    <AssetThumb asset={asset} className="h-full w-full transition-transform duration-700 group-hover:scale-[1.06]" />

    {/* like ------------------------------------------------------------- */}
    <span
      role="button"
      onClick={(e) => { e.stopPropagation(); onLike(asset.id); }}
      className={cn(
        'absolute right-3 top-3 grid h-8 w-8 place-items-center rounded-full backdrop-blur-md transition-all',
        asset.liked ? 'bg-white/90 text-rose' : 'bg-black/35 text-white/80 hover:bg-black/55 hover:text-white',
      )}
    >
      <Heart className={cn('h-[15px] w-[15px]', asset.liked && 'fill-current')} />
    </span>

    {onDelete && (
      <span
        role="button"
        title="Delete asset"
        onClick={(e) => {
          e.stopPropagation();
          if (window.confirm(`Delete "${asset.name}"?`)) {
            onDelete(asset.id);
          }
        }}
        className="absolute left-3 top-3 z-20 grid h-8 w-8 place-items-center rounded-full bg-black/45 text-white/70 backdrop-blur-md transition-all hover:bg-red-500 hover:text-white"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </span>
    )}

    {!onDelete && asset.versions && asset.versions > 1 && (
      <span
        title={`${asset.versions} versions of this project — the newest is shown here. All of them are in your ASSET tab.`}
        className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-black/45 px-2 py-1 text-[9px] font-semibold text-chalk backdrop-blur-md"
      >
        <Layers className="h-2.5 w-2.5" /> {asset.versions}
      </span>
    )}

    {builtAsset && (
      <span className="absolute left-3 top-3 flex items-center gap-1 rounded-full bg-emerald-400/20 px-2 py-1 text-[9px] font-semibold text-emerald-200 backdrop-blur-md">
        <Rotate3d className="h-2.5 w-2.5" /> 3D
      </span>
    )}

    {asset.visibility === 'private' && (
      <span className="absolute left-3 top-3 grid h-7 w-7 place-items-center rounded-full bg-black/45 text-white/80 backdrop-blur-md">
        <Lock className="h-3 w-3" />
      </span>
    )}

    {/* meta ------------------------------------------------------------- */}
    <span className="pointer-events-none absolute inset-x-0 bottom-0 flex translate-y-2 flex-col gap-0.5 bg-gradient-to-t from-black/90 via-black/55 to-transparent p-4 opacity-0 transition-all duration-300 group-hover:translate-y-0 group-hover:opacity-100">
      <span className="truncate text-[13px] font-semibold text-white">{asset.name}</span>
      {asset.isReference ? (
        builtAsset ? (
          <span className="flex items-center gap-1.5 text-[10px] text-emerald-300">
            <Rotate3d className="h-2.5 w-2.5" /> Click to view in 3D · {compact(builtAsset.faces)} faces
          </span>
        ) : (
          <span className="flex items-center gap-1.5 text-[10px] text-lilac">
            <Wand2 className="h-2.5 w-2.5" /> Click to load as reference
          </span>
        )
      ) : (
        <>
          <span className="flex items-center gap-2 text-[10px] text-chalk-dim">
            <span className="truncate">{asset.author}</span>
            <span className="text-chalk-ghost">·</span>
            <span className="flex items-center gap-1"><Heart className="h-2.5 w-2.5" />{asset.likes}</span>
            <span className="text-chalk-ghost">·</span>
            <span className="flex items-center gap-1"><Box className="h-2.5 w-2.5" />{compact(asset.faces)}</span>
          </span>
          <span className="mt-0.5 w-fit rounded-full border border-white/12 px-1.5 py-0.5 font-mono text-[9px] text-chalk-faint">
            {engineById(asset.engine).label}
          </span>
        </>
      )}
    </span>
  </button>
);
