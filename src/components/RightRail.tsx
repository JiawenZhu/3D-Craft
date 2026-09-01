import React from 'react';
import { Headphones, Share2 } from 'lucide-react';
import { Tip } from './ui/primitives';

/** The two floating circular buttons pinned to the bottom-right of hyper3d.ai. */
export const RightRail: React.FC = () => (
  <div className="fixed bottom-8 right-6 z-40 flex flex-col gap-3">
    <Tip side="left" label="Share a post & earn 1 credit">
      <button className="grid h-10 w-10 place-items-center rounded-full border border-white/10 bg-ink-800/80 text-chalk-dim shadow-lift backdrop-blur-xl transition-all hover:border-white/25 hover:text-white">
        <Share2 className="h-4 w-4" />
      </button>
    </Tip>
    <Tip side="left" label="Chat with us">
      <button className="grid h-10 w-10 place-items-center rounded-full border border-white/10 bg-ink-800/80 text-chalk-dim shadow-lift backdrop-blur-xl transition-all hover:border-white/25 hover:text-white">
        <Headphones className="h-4 w-4" />
      </button>
    </Tip>
  </div>
);
