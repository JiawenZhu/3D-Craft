import React, { useState } from 'react';
import { RODIN_SHOWCASE_ITEMS, RodinShowcaseItem } from '../data/rodinExamples';
import { Heart, ChevronDown, User, Sparkles } from 'lucide-react';

interface RodinExamplesGridProps {
  onSelectExample: (item: RodinShowcaseItem) => void;
  selectedExampleId?: string;
}

export const RodinExamplesGrid: React.FC<RodinExamplesGridProps> = ({
  onSelectExample,
  selectedExampleId
}) => {
  const [favorites, setFavorites] = useState<Record<string, boolean>>({});
  const [activeHeaderTab, setActiveHeaderTab] = useState<'ChatAvatar' | 'Rodin' | 'OmniCraft'>('Rodin');

  const toggleFavorite = (e: React.MouseEvent, id: string) => {
    e.stopPropagation();
    setFavorites(prev => ({ ...prev, [id]: !prev[id] }));
  };

  return (
    <div className="w-full max-w-5xl flex flex-col gap-5 select-none animate-fade-in">
      {/* Top Breadcrumb Nav (matching top left in screenshot: ChatAvatar | Rodin | OmniCraft ⌵) */}
      <div className="flex items-center justify-between px-2">
        <div className="flex items-center gap-4 text-xs font-semibold text-slate-400">
          <button
            onClick={() => setActiveHeaderTab('ChatAvatar')}
            className={`hover:text-slate-200 transition-colors ${activeHeaderTab === 'ChatAvatar' ? 'text-white' : ''}`}
          >
            ChatAvatar
          </button>

          <button
            onClick={() => setActiveHeaderTab('Rodin')}
            className={`px-3 py-1 rounded-full border border-white/20 text-white font-bold bg-[#332A36]/60 backdrop-blur-md shadow-sm transition-all ${
              activeHeaderTab === 'Rodin' ? 'ring-1 ring-white/30' : ''
            }`}
          >
            Rodin
          </button>

          <button
            onClick={() => setActiveHeaderTab('OmniCraft')}
            className={`flex items-center gap-1 hover:text-slate-200 transition-colors ${activeHeaderTab === 'OmniCraft' ? 'text-white' : ''}`}
          >
            <span>OmniCraft</span>
            <ChevronDown className="w-3 h-3 text-slate-400" />
          </button>
        </div>

        <span className="text-[11px] font-mono text-pink-300 bg-pink-500/10 px-2.5 py-0.5 rounded-full border border-pink-500/20">
          Community Showcase
        </span>
      </div>

      {/* 4x3 Grid of 12 Photorealistic 3D Cards (Exact replica of user screenshot) */}
      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4 p-1">
        {RODIN_SHOWCASE_ITEMS.map((item) => {
          const isFav = favorites[item.id];
          const isSelected = selectedExampleId === item.id;

          return (
            <div
              key={item.id}
              onClick={() => onSelectExample(item)}
              className={`
                group relative aspect-square rounded-3xl border transition-all duration-300 cursor-pointer overflow-hidden bg-[#18131B] shadow-2xl shadow-black/60 flex flex-col justify-between
                ${isSelected
                  ? 'border-pink-500 ring-2 ring-pink-500/50 scale-[1.02]'
                  : 'border-white/10 hover:border-white/30 hover:scale-[1.02] hover:shadow-pink-950/30'
                }
              `}
            >
              {/* Photorealistic 3D Render Image */}
              <img
                src={item.imageUrl}
                alt={item.title}
                className="absolute inset-0 w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
                loading="lazy"
              />

              {/* Dark Gradient Overlay for Clean Legibility */}
              <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-transparent to-black/30 pointer-events-none" />

              {/* Top-Right Heart Button (Exact replica of screenshot) */}
              <button
                onClick={(e) => toggleFavorite(e, item.id)}
                className="absolute top-3 right-3 p-1.5 rounded-full bg-black/50 backdrop-blur-md text-white/80 hover:text-rose-400 transition-colors z-10 border border-white/10"
                title="Favorite asset"
              >
                <Heart
                  className={`w-3.5 h-3.5 transition-transform group-hover:scale-110 ${
                    isFav ? 'text-rose-500 fill-rose-500' : 'stroke-[2]'
                  }`}
                />
              </button>

              {/* Bottom Author & Likes Bar (Exact replica of screenshot) */}
              <div className="z-10 mt-auto p-3 flex items-center justify-between text-xs text-white/90 font-medium">
                <div className="flex items-center gap-1.5 truncate max-w-[120px]">
                  <div className="w-5 h-5 rounded-full bg-gradient-to-tr from-pink-500 to-purple-600 flex items-center justify-center text-[10px] font-bold text-white shrink-0 border border-white/20">
                    {item.author.charAt(0).toUpperCase()}
                  </div>
                  <span className="truncate text-[11px] text-slate-200">{item.author}</span>
                </div>

                <span className="text-[10px] font-mono text-slate-300 font-semibold shrink-0">
                  {item.likes} likes
                </span>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
