import React from 'react';
import { CornerDownLeft, Sparkles, Zap } from 'lucide-react';
import { cn } from '../../lib/cn';
import { useStudio } from '../../store/StudioContext';

/**
 * Which route GENERATE takes, and the words that go with the image.
 *
 *   Concept → 3D   the image is re-rendered as a clean studio asset first
 *   Direct → 3D    the image goes straight to the reconstructor
 *
 * The default is the concept pass, because image-to-3D inherits every flaw of
 * its input: a cluttered background becomes geometry, a cropped limb becomes a
 * hole, and baked-in shadows become permanent dark patches in the albedo. The
 * direct route stays one click away for inputs that are already clean — a
 * gallery render, or a concept somebody has already approved.
 *
 * The prompt lives here rather than in the input card because the card is a
 * fixed 180x180 that shows the image OR a textarea, never both, and this
 * workflow is image AND words: the picture says what the thing is, the words
 * say what to change about it.
 */
export const RouteToggle: React.FC = () => {
  const {
    usePipeline, setUsePipeline, geminiReady, health, settings, patch,
    images, startPipeline, generate, pipeline,
  } = useStudio();

  const busy = pipeline?.status === 'running';
  const viaPipeline = usePipeline && geminiReady;

  const options = [
    {
      value: true,
      label: 'Concept → 3D',
      Icon: Sparkles,
      hint: geminiReady
        ? `Gemini writes the prompt and renders a clean asset first · ${health?.gemini?.note}`
        : 'Needs GEMINI_API_KEY in .env on the server',
    },
    { value: false, label: 'Direct → 3D', Icon: Zap, hint: 'Send the image straight to the reconstructor' },
  ];

  const submit = () => {
    if (busy) return;
    if (!images.length && !settings.prompt.trim()) return;
    (viaPipeline ? startPipeline : generate)();
  };

  return (
    <div className="mt-7 flex flex-col items-center gap-2.5">
      {/* route ---------------------------------------------------------- */}
      <div className="inline-flex items-center gap-0.5 rounded-full border border-white/10 bg-white/[0.03] p-0.5 backdrop-blur-xl">
        {options.map((o) => {
          const active = usePipeline === o.value;
          const blocked = o.value && !geminiReady;
          return (
            <button
              key={String(o.value)}
              onClick={() => !blocked && setUsePipeline(o.value)}
              disabled={blocked}
              title={o.hint}
              className={cn(
                'flex items-center gap-1.5 rounded-full px-3.5 py-[5px] text-[11px] transition-all duration-200',
                blocked ? 'cursor-not-allowed text-chalk-ghost opacity-50'
                  : active ? 'bg-white/90 font-semibold text-ink'
                    : 'text-chalk-faint hover:text-white',
              )}
            >
              <o.Icon className="h-3 w-3" />
              {o.label}
            </button>
          );
        })}
      </div>

      {/* the words that go with the image -------------------------------- */}
      <div
        className="flex w-full max-w-[520px] items-center gap-2 rounded-2xl border border-white/10 bg-white/[0.03] px-3.5 py-2 transition-colors focus-within:border-white/30"
        style={{ backdropFilter: 'blur(14px)' }}
      >
        <input
          value={settings.prompt}
          onChange={(e) => patch({ prompt: e.target.value })}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); } }}
          placeholder={
            viaPipeline
              ? images.length
                ? 'Say what to change — “make him a forest ranger with a lantern”'
                : 'Describe the asset — Gemini renders it, then it is reconstructed'
              : 'Name the result (optional)'
          }
          className="min-w-0 flex-1 bg-transparent text-[12px] text-chalk placeholder:text-chalk-ghost"
        />
        <button
          onClick={submit}
          disabled={busy || (!images.length && !settings.prompt.trim())}
          title="Run it"
          className={cn(
            'grid h-[26px] w-[26px] shrink-0 place-items-center rounded-lg transition-all',
            busy || (!images.length && !settings.prompt.trim())
              ? 'cursor-not-allowed text-chalk-ghost'
              : 'bg-white/10 text-white hover:bg-white/20',
          )}
        >
          <CornerDownLeft className="h-3.5 w-3.5" />
        </button>
      </div>

      <p className="max-w-[440px] text-center text-[10px] leading-relaxed text-chalk-ghost">
        {!geminiReady
          ? 'Set GEMINI_API_KEY in .env and restart the server to enable the concept pass.'
          : viaPipeline
            ? 'Your image and words go to Gemini, which writes the full prompt and renders a clean, evenly-lit asset — then that is reconstructed. With no image, it draws one from the words alone.'
            : 'Your image goes straight to the reconstructor. Best when it is already a clean render on a plain background.'}
      </p>
    </div>
  );
};
