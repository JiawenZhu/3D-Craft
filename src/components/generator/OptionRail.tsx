import React from 'react';
import { Boxes, Hexagon, PenTool, PersonStanding } from 'lucide-react';
import { cn } from '../../lib/cn';
import { Tip } from '../ui/primitives';
import { useStudio } from '../../store/StudioContext';
import type { GeoMode, PoseMode } from '../../types';

const GEO: { id: GeoMode; label: string; hint: string }[] = [
  { id: 'sharp', label: 'Sharp', hint: 'Default — preserve hard surface detail' },
  { id: 'smooth', label: 'Smooth', hint: 'Relax micro-detail for organic forms' },
  { id: 'zero', label: 'Zero', hint: 'Clean, distraction-free surfaces' },
  { id: 'focal', label: 'Focal', hint: 'Spend the budget on the subject' },
];

/** The four circular toggles pinned to the right edge of the input card. */
export const OptionRail: React.FC = () => {
  const { settings, patch } = useStudio();
  const nextGeo = () => {
    const i = GEO.findIndex((g) => g.id === settings.geoMode);
    patch({ geoMode: GEO[(i + 1) % GEO.length].id });
  };
  const nextPose = () => {
    const order: PoseMode[] = ['none', 't-pose', 'a-pose'];
    patch({ poseMode: order[(order.indexOf(settings.poseMode) + 1) % order.length] });
  };
  const geo = GEO.find((g) => g.id === settings.geoMode)!;

  const Btn: React.FC<{ active?: boolean; onClick: () => void; children: React.ReactNode; badge?: boolean }> = ({ active, onClick, children, badge }) => (
    <button
      onClick={onClick}
      className={cn(
        'relative grid h-[30px] w-[30px] place-items-center rounded-full border transition-all duration-200',
        active ? 'border-white/40 bg-white/12 text-white' : 'border-white/8 bg-white/[0.03] text-chalk-faint hover:border-white/25 hover:text-chalk',
      )}
    >
      {children}
      {badge && <span className="absolute -right-0 -top-0 h-[6px] w-[6px] rounded-full bg-coral" />}
    </button>
  );

  return (
    <div className="flex w-[30px] shrink-0 flex-col gap-[6px]">
      <Tip side="right" label={`Surface: ${geo.label} — ${geo.hint}`}>
        <Btn active={settings.geoMode !== 'sharp'} onClick={nextGeo} badge>
          <PenTool className="h-[14px] w-[14px]" strokeWidth={1.6} />
        </Btn>
      </Tip>
      <Tip side="right" label={settings.quadRemesh ? 'Quad remesh: on' : 'Quad remesh: off (triangles)'}>
        <Btn active={settings.quadRemesh} onClick={() => patch({ quadRemesh: !settings.quadRemesh })}>
          <Hexagon className="h-[14px] w-[14px]" strokeWidth={1.6} />
        </Btn>
      </Tip>
      <Tip side="right" label={settings.poseMode === 'none' ? 'Pose: free' : `Pose: ${settings.poseMode.toUpperCase()}`}>
        <Btn active={settings.poseMode !== 'none'} onClick={nextPose}>
          <PersonStanding className="h-[15px] w-[15px]" strokeWidth={1.6} />
        </Btn>
      </Tip>
      <Tip side="right" label={settings.texture ? 'Texture: on' : 'Texture: off (geometry only)'}>
        <Btn active={settings.texture} onClick={() => patch({ texture: !settings.texture })}>
          <Boxes className="h-[14px] w-[14px]" strokeWidth={1.6} />
        </Btn>
      </Tip>
    </div>
  );
};
