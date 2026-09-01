import React, { useCallback, useRef, useState } from 'react';
import {
  ArrowUp, Compass, HelpCircle, Image as ImageIcon, Images, Plus, Sparkles, Wand2, X,
} from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';
import { Popover, Tip } from '../ui/primitives';
import { DirectionPicker } from './DirectionPicker';

const ACCEPT = 'image/png,image/jpeg,image/webp,image/avif';

const MODE_META = {
  'image-to-3d': { title: 'Image to 3D', Icon: ImageIcon, supports: '.png .jpg .webp' },
  '3d-editing': { title: '3D Editing', Icon: Wand2, supports: '.obj .fbx .glb' },
  worldgen: { title: 'WorldGen', Icon: Compass, supports: 'text → environment' },
} as const;

/** Rotating labels on the floating pill, exactly as the live card cycles them. */
const PILL_LABELS = [
  { text: 'Text to Image/3D', cls: 'rd-grad-text-warm' },
  { text: 'Remix Gen', cls: 'rd-grad-text-remix' },
  { text: 'Turbo Gen', cls: 'rd-grad-text-turbo' },
];

export const InputCard: React.FC = () => {
  const { settings, patch, images, addImages, removeImage, setDirection } = useStudio();
  const [dragging, setDragging] = useState(false);
  const [dirFor, setDirFor] = useState<string | null>(null);
  const [pill, setPill] = useState(0);
  const fileRef = useRef<HTMLInputElement>(null);
  const meta = MODE_META[settings.mode];

  const onDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault(); setDragging(false);
    if (e.dataTransfer.files?.length) { addImages(e.dataTransfer.files); patch({ inputMode: 'image' }); }
  }, [addImages, patch]);

  const textMode = settings.inputMode === 'text' || settings.mode === 'worldgen';

  return (
    <div className="relative">
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        className={cn(
          'relative flex h-[180px] w-[180px] flex-col overflow-hidden rounded-[20px] border p-[10px] pb-[48px] transition-all duration-300',
          dragging ? 'border-white/60 bg-white/[0.08]' : 'border-white/10 bg-black/20',
        )}
        style={{ backdropFilter: 'blur(16px)' }}
      >
        {/* header ------------------------------------------------------- */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-[6px]">
            <meta.Icon className="h-[15px] w-[15px] text-white" strokeWidth={1.8} />
            <span className="text-[13px] font-bold leading-none text-white">{meta.title}</span>
          </div>
          <div className="flex items-center gap-[5px]">
            <Tip label="Sample images">
              <button
                onClick={() => patch({ prompt: settings.prompt || 'a weathered brass astrolabe on a walnut stand' })}
                className="grid h-[20px] w-[20px] place-items-center rounded-full bg-white/20 text-white/90 transition-colors hover:bg-white/35"
              >
                <Images className="h-[11px] w-[11px]" />
              </button>
            </Tip>
            <Tip label="Both engines run locally — nothing is uploaded">
              <button className="grid h-[20px] w-[20px] place-items-center rounded-full bg-white/20 text-white/90 transition-colors hover:bg-white/35">
                <HelpCircle className="h-[11px] w-[11px]" />
              </button>
            </Tip>
          </div>
        </div>

        {/* body ---------------------------------------------------------- */}
        <div className="relative mt-[6px] flex-1">
          {textMode ? (
            <textarea
              value={settings.prompt}
              onChange={(e) => patch({ prompt: e.target.value })}
              placeholder={settings.mode === 'worldgen' ? 'Describe a scene…' : 'Describe what to build…'}
              className="h-full w-full resize-none rounded-[10px] bg-white/[0.04] p-2 text-[11px] leading-[1.5] text-chalk placeholder:text-chalk-ghost focus:bg-white/[0.07]"
            />
          ) : images.length === 0 ? (
            <button
              onClick={() => fileRef.current?.click()}
              className="group grid h-full w-full place-items-center rounded-[10px] transition-colors hover:bg-white/[0.04]"
            >
              <Plus className="h-[38px] w-[38px] text-white/85 transition-transform duration-300 group-hover:scale-110" strokeWidth={1.1} />
            </button>
          ) : (
            <div className={cn('grid h-full gap-[5px]', images.length === 1 ? 'grid-cols-1' : 'grid-cols-2 content-start')}>
              {images.map((img) => (
                <div key={img.id} className="group relative overflow-hidden rounded-[9px] border border-white/10 bg-white/[0.04]">
                  <img src={img.url} alt={img.name} className="h-full w-full object-cover" />
                  <div className="absolute inset-0 flex items-end justify-between bg-gradient-to-t from-black/80 to-transparent p-1 opacity-0 transition-opacity group-hover:opacity-100">
                    <button
                      onClick={() => setDirFor(dirFor === img.id ? null : img.id)}
                      className="rounded-full bg-black/60 px-1.5 py-0.5 text-[8px] text-white"
                    >
                      {img.direction === 'unknown' ? 'set view' : img.direction}
                    </button>
                    <button onClick={() => removeImage(img.id)} className="grid h-4 w-4 place-items-center rounded-full bg-black/60 text-white">
                      <X className="h-2.5 w-2.5" />
                    </button>
                  </div>
                </div>
              ))}
              {settings.imageMode === 'multi' && images.length < 8 && (
                <button
                  onClick={() => fileRef.current?.click()}
                  className="grid place-items-center rounded-[9px] border border-dashed border-white/15 text-chalk-faint transition-colors hover:border-white/35 hover:text-white"
                >
                  <Plus className="h-4 w-4" />
                </button>
              )}
            </div>
          )}

        </div>

        {/* footer -------------------------------------------------------- */}
        <div className="mt-[6px] flex h-[14px] items-center justify-center gap-1 text-[9px] font-medium text-chalk-ghost">
          {textMode ? (
            <button
              onClick={() => patch({ prompt: '' })}
              className="transition-colors hover:text-chalk"
            >
              {settings.prompt.length} chars · click to clear
            </button>
          ) : (
            <span>Supports <span className="text-chalk-faint">{meta.supports}</span></span>
          )}
        </div>

        {/* text-mode send button, matching the live lilac→gold pill ------- */}
        {textMode && settings.prompt.trim() && (
          <button
            onClick={() => patch({ inputMode: 'text' })}
            className="absolute bottom-[50px] right-[10px] grid h-[26px] w-[42px] place-items-center rounded-full text-ink shadow-lift"
            style={{ backgroundImage: 'var(--g-send)' }}
          >
            <ArrowUp className="h-[14px] w-[14px]" strokeWidth={2.4} />
          </button>
        )}

        <input
          ref={fileRef} type="file" accept={ACCEPT} hidden
          multiple={settings.imageMode === 'multi'}
          onChange={(e) => e.target.files && addImages(e.target.files)}
        />
      </div>

      {/* Direction picker lives outside the card: the card is overflow-hidden,
          which would otherwise clip the popover. */}
      {dirFor && (
        <Popover open onClose={() => setDirFor(null)} anchor="bottom" className="left-1/2 z-[90] -translate-x-1/2">
          <DirectionPicker
            value={images.find((i) => i.id === dirFor)?.direction ?? 'unknown'}
            onChange={(d) => { setDirection(dirFor, d); setDirFor(null); }}
          />
        </Popover>
      )}

      {/* single / multi-view switch, shown while the card is in image mode */}
      {!textMode && (
        <div className="absolute -top-[38px] left-1/2 flex -translate-x-1/2 items-center gap-0.5 rounded-full border border-white/10 bg-white/[0.04] p-0.5 backdrop-blur-xl">
          {(['single', 'multi'] as const).map((m) => (
            <button
              key={m}
              onClick={() => patch({ imageMode: m })}
              className={cn(
                'rounded-full px-2.5 py-[3px] text-[9px] transition-all duration-200',
                settings.imageMode === m ? 'bg-white/90 font-semibold text-ink' : 'text-chalk-faint hover:text-white',
              )}
            >
              {m === 'single' ? 'Single image' : 'Multi-view'}
            </button>
          ))}
        </div>
      )}

      {/* the floating gradient pill that hangs over the card's lower edge */}
      <button
        onClick={() => {
          if (textMode) patch({ inputMode: 'image' });
          else { patch({ inputMode: 'text' }); setPill((p) => (p + 1) % PILL_LABELS.length); }
        }}
        className="absolute bottom-[12px] left-1/2 flex h-[30px] w-[156px] -translate-x-1/2 items-center justify-center rounded-[17px] transition-all duration-300 hover:brightness-125"
        style={{ background: 'rgba(210,182,223,.15)', backdropFilter: 'blur(14px)' }}
      >
        <span className={cn('text-[13px] font-bold', textMode ? 'rd-grad-text' : PILL_LABELS[pill].cls)}>
          {textMode ? 'Back to Image' : PILL_LABELS[pill].text}
        </span>
        <Sparkles className="ml-1 h-3 w-3 text-lilac/70" />
      </button>
    </div>
  );
};
