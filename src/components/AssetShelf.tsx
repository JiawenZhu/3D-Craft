import React, { useMemo, useState } from 'react';
import { ChevronDown, Search, X } from 'lucide-react';
import { cn } from '../lib/cn';
import { useStudio } from '../store/StudioContext';
import { AssetCard } from './AssetCard';
import { StoryRail } from './StoryRail';
import { FILTERS } from '../data/gallery';
import type { Asset } from '../types';

export const AssetShelf: React.FC = () => {
  const { assets, exploreAssets, shelfTab, setShelfTab, openAsset, toggleLike } = useStudio();
  const [filter, setFilter] = useState<string>('Featured');
  const [filterOpen, setFilterOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [searchOpen, setSearchOpen] = useState(false);

  const source = shelfTab === 'asset' ? assets : exploreAssets;

  const list = useMemo(() => {
    let out: Asset[] = [...source];
    if (query.trim()) {
      const q = query.toLowerCase();
      out = out.filter((a) => `${a.name} ${a.prompt} ${a.author}`.toLowerCase().includes(q));
    }
    if (filter === 'Newest') out.sort((a, b) => b.createdAt - a.createdAt);
    if (filter === 'Most liked') out.sort((a, b) => b.likes - a.likes);
    if (filter === 'Hunyuan3D') out = out.filter((a) => a.engine === 'hunyuan3d-2.1');
    if (filter === 'TRELLIS.2') out = out.filter((a) => a.engine === 'trellis-2');
    return out;
  }, [source, query, filter]);

  return (
    <section className="relative z-10 mx-auto flex w-full max-w-[1500px] gap-4 px-6 pb-28 pt-20 sm:px-[76px]">
      <div className="min-w-0 flex-1">
      {/* header --------------------------------------------------------- */}
      <div className="mb-6 flex items-end justify-between gap-4">
        <div className="flex items-baseline gap-5">
          {(['asset', 'explore'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setShelfTab(t)}
              className={cn(
                'text-[26px] font-semibold uppercase tracking-[0.02em] transition-colors duration-300 sm:text-[30px]',
                shelfTab === t ? 'text-white' : 'text-white/25 hover:text-white/50',
              )}
            >
              {t}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <div className={cn('flex items-center overflow-hidden rounded-full border border-white/10 bg-white/[0.03] backdrop-blur-xl transition-all duration-300', searchOpen ? 'w-[220px] px-3' : 'w-9')}>
            <button onClick={() => setSearchOpen((v) => !v)} className="grid h-9 w-9 shrink-0 place-items-center text-chalk-dim transition-colors hover:text-white" style={{ marginLeft: searchOpen ? -12 : 0 }}>
              <Search className="h-[15px] w-[15px]" />
            </button>
            {searchOpen && (
              <>
                <input
                  autoFocus value={query} onChange={(e) => setQuery(e.target.value)}
                  placeholder="Search assets…"
                  className="h-9 min-w-0 flex-1 text-[12px] text-chalk placeholder:text-chalk-ghost"
                />
                {query && <button onClick={() => setQuery('')} className="text-chalk-faint hover:text-white"><X className="h-3.5 w-3.5" /></button>}
              </>
            )}
          </div>

          <div className="relative">
            <button
              onClick={() => setFilterOpen((v) => !v)}
              className="flex h-9 items-center gap-1.5 rounded-full border border-white/10 bg-white/[0.03] px-4 text-[12px] text-chalk backdrop-blur-xl transition-colors hover:border-white/25 hover:text-white"
            >
              Filter <ChevronDown className={cn('h-3.5 w-3.5 transition-transform', filterOpen && 'rotate-180')} />
            </button>
            {filterOpen && (
              <>
                <div className="fixed inset-0 z-40" onClick={() => setFilterOpen(false)} />
                <div className="absolute right-0 top-full z-50 mt-2 w-44 animate-popIn rounded-2xl border border-white/10 bg-ink-900/95 p-1.5 shadow-lift backdrop-blur-2xl">
                  {FILTERS.map((f) => (
                    <button
                      key={f}
                      onClick={() => { setFilter(f); setFilterOpen(false); }}
                      className={cn('block w-full rounded-lg px-3 py-1.5 text-left text-[12px] transition-colors', filter === f ? 'bg-white/[0.08] text-white' : 'text-chalk-dim hover:bg-white/[0.04] hover:text-white')}
                    >
                      {f}
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      <div className="mb-6">
        <span className="inline-flex items-center rounded-full border border-rose/30 px-3.5 py-1 text-[12px] text-rose" style={{ background: 'rgba(230,118,93,.08)' }}>
          {filter}
        </span>
      </div>

      {/* grid ----------------------------------------------------------- */}
      {list.length === 0 ? (
        <div className="grid h-64 place-items-center rounded-[28px] border border-dashed border-white/8 text-center">
          <div>
            <p className="text-[13px] text-chalk-dim">
              {shelfTab === 'asset' ? 'Nothing generated yet.' : 'No matches.'}
            </p>
            <p className="mt-1 text-[11px] text-chalk-ghost">
              {shelfTab === 'asset' ? 'Drop an image above and hit GENERATE.' : 'Try a different filter.'}
            </p>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-2 gap-5 sm:grid-cols-3 lg:grid-cols-4">
          {list.map((a) => (
            <AssetCard key={a.id} asset={a} onOpen={openAsset} onLike={toggleLike} />
          ))}
        </div>
      )}
      </div>
      <StoryRail />
    </section>
  );
};
