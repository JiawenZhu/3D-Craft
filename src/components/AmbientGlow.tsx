import React from 'react';

/**
 * The three fixed, 100px-blurred gradient orbs that give hyper3d.ai its warm
 * mauve/ember cast over a near-black (#121317) page. Values are lifted from the
 * live site's computed styles — including the fact that they are static: a
 * 100px blur over a 677px element is far too expensive to animate per frame.
 */
export const AmbientGlow: React.FC = () => (
  <div aria-hidden className="pointer-events-none fixed inset-0 z-0 overflow-hidden">
    <div
      className="absolute rounded-full"
      style={{
        width: 677, height: 677, left: '46%', top: '-14%', transform: 'translateX(-50%)',
        filter: 'blur(100px)',
        backgroundImage: 'linear-gradient(309.02deg, rgba(104,194,160,.40) 16.79%, rgba(28,101,77,.40) 93.35%)',
      }}
    />
    <div
      className="absolute rounded-full"
      style={{
        width: 346, height: 346, left: '62%', top: '18%',
        filter: 'blur(100px)',
        backgroundImage: 'linear-gradient(132.64deg, rgba(214,242,231,.30) 42.55%, rgba(28,101,77,.30) 79.55%)',
      }}
    />
    <div
      className="absolute rounded-full"
      style={{
        width: 403, height: 403, left: '24%', top: '26%',
        filter: 'blur(100px)',
        backgroundImage: 'linear-gradient(20deg, rgba(156,220,195,.22) 10%, rgba(104,194,160,.28) 90%)',
      }}
    />
    {/* vignette + film grain keep the gradients from banding */}
    <div className="absolute inset-0" style={{ background: 'radial-gradient(120% 80% at 50% 0%, transparent 20%, rgba(10,10,12,.55) 70%, rgba(8,8,10,.9) 100%)' }} />
    <div className="rd-grain absolute inset-0 opacity-[0.035] mix-blend-overlay" />
  </div>
);
