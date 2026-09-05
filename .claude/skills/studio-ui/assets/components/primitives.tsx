import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { cn } from './cn';

/* ===========================================================================
 * studio-ui — primitives
 *
 * The pieces everything else is built from. Two rules hold across all of them:
 *
 *   1. No colour literals. Every colour is var(--su-*), so a project rebrands
 *      the kit by editing tokens.css and nothing else.
 *   2. No icon library. Icons arrive as ReactNode props, so the kit works with
 *      lucide, heroicons, an inline SVG, or an emoji, and adds no dependency.
 * ========================================================================= */

/* ------------------------------------------------------------------ Glass */

export type Surface = 1 | 2 | 3 | 'sunk';
export type Radius = 'sm' | 'md' | 'lg' | 'pill';

const SURFACE: Record<Surface, string> = {
  1: 'bg-[var(--su-surface-1)]',
  2: 'bg-[var(--su-surface-2)]',
  3: 'bg-[var(--su-surface-3)]',
  sunk: 'bg-[var(--su-surface-sunk)]',
};

const RADIUS: Record<Radius, string> = {
  sm: 'rounded-[var(--su-radius-sm)]',
  md: 'rounded-[var(--su-radius-md)]',
  lg: 'rounded-[var(--su-radius-lg)]',
  pill: 'rounded-[var(--su-radius-pill)]',
};

/**
 * The base surface. Nearly every panel in the kit is one of these.
 *
 * `blur` is what separates a glass panel from a grey rectangle, and it only
 * reads as glass when there is something behind it worth blurring — over a
 * flat background it is wasted GPU. Pass blur={false} for panels on plain
 * ground, especially in long scrolling lists where the cost multiplies.
 */
export const GlassPanel: React.FC<
  React.HTMLAttributes<HTMLDivElement> & {
    surface?: Surface;
    radius?: Radius;
    bordered?: boolean;
    blur?: boolean | 'heavy';
    lifted?: boolean;
    /** Dashed border reads as "nothing here yet" — empty slots, drop targets. */
    dashed?: boolean;
  }
> = ({
  surface = 1, radius = 'md', bordered = true, blur = true, lifted, dashed,
  className, style, children, ...rest
}) => (
  <div
    className={cn(
      SURFACE[surface],
      RADIUS[radius],
      bordered && 'border border-[var(--su-border)]',
      dashed && 'border-dashed',
      lifted && 'shadow-[var(--su-shadow-lift)]',
      className,
    )}
    style={{
      backdropFilter: blur ? `blur(var(--su-blur${blur === 'heavy' ? '-heavy' : ''}))` : undefined,
      ...style,
    }}
    {...rest}
  >
    {children}
  </div>
);

/* -------------------------------------------------------------- IconButton */

/**
 * Square-ish icon control. `active` is a visual state, not a disabled state —
 * an active IconButton is still pressable, which is what a toggle needs.
 */
export const IconButton = React.forwardRef<
  HTMLButtonElement,
  React.ButtonHTMLAttributes<HTMLButtonElement> & {
    active?: boolean;
    size?: number;
    tone?: 'default' | 'danger';
  }
>(({ active, size = 34, tone = 'default', className, style, ...rest }, ref) => (
  <button
    ref={ref}
    type="button"
    data-active={active ? 'true' : undefined}
    style={{ width: size, height: size, ...style }}
    className={cn(
      'grid shrink-0 place-items-center rounded-[var(--su-radius-pill)] border transition-colors duration-[var(--su-fast)]',
      'disabled:cursor-not-allowed disabled:opacity-40',
      active
        ? 'border-[var(--su-border-strong)] bg-[var(--su-surface-3)] text-[var(--su-text)]'
        : 'border-transparent text-[var(--su-text-faint)] hover:bg-[var(--su-surface-2)] hover:text-[var(--su-text)]',
      tone === 'danger' && 'hover:border-[var(--su-danger)] hover:text-[var(--su-danger)]',
      className,
    )}
    {...rest}
  />
));
IconButton.displayName = 'IconButton';

/* -------------------------------------------------------------- PillButton */

/**
 * The primary action. Three things it does that a plain button does not:
 *
 *   - `progress` fills it from the left while work runs, so the button IS the
 *     progress bar. A separate bar underneath says the same thing twice and
 *     pushes the layout around when it appears.
 *   - `hoverLabel` swaps the label on hover. Good for the cost or the shortcut
 *     of the thing you are about to do — information that matters at the
 *     moment of committing and is noise before it.
 *   - `busy` replaces the label wholesale, because a button that still says
 *     "Generate" while generating invites a second click.
 */
export const PillButton: React.FC<
  React.ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: 'accent' | 'ghost' | 'solid';
    size?: 'sm' | 'md' | 'lg';
    progress?: number;
    hoverLabel?: React.ReactNode;
    busy?: React.ReactNode;
    icon?: React.ReactNode;
  }
> = ({
  variant = 'ghost', size = 'md', progress, hoverLabel, busy, icon,
  className, children, disabled, style, ...rest
}) => {
  const SIZE = {
    sm: 'h-[30px] px-3.5 text-[11px]',
    md: 'h-[38px] px-5 text-[12px]',
    lg: 'h-[60px] px-8 text-[18px]',
  }[size];

  const VARIANT = {
    accent: 'border-transparent text-[var(--su-accent-ink)] hover:brightness-110',
    solid: 'border-transparent bg-[var(--su-text)] text-[var(--su-bg)] hover:opacity-90',
    ghost:
      'border-[var(--su-border)] bg-[var(--su-surface-1)] text-[var(--su-text)] ' +
      'hover:border-[var(--su-border-strong)] hover:bg-[var(--su-surface-2)]',
  }[variant];

  return (
    <button
      type="button"
      disabled={disabled}
      style={{
        backgroundImage: variant === 'accent' && !disabled ? 'var(--su-gradient)' : undefined,
        backdropFilter: variant === 'ghost' ? 'blur(var(--su-blur))' : undefined,
        ...style,
      }}
      className={cn(
        'group relative flex items-center justify-center gap-2 overflow-hidden rounded-[var(--su-radius-pill)]',
        'border font-semibold transition-all duration-[var(--su-base)] active:scale-[0.985]',
        'disabled:cursor-not-allowed disabled:opacity-50 disabled:active:scale-100',
        SIZE, VARIANT, className,
      )}
      {...rest}
    >
      {progress != null && (
        <span
          aria-hidden
          className="absolute inset-y-0 left-0 bg-[var(--su-surface-3)] transition-[width] duration-500"
          style={{ width: `${Math.max(0, Math.min(100, progress))}%` }}
        />
      )}
      <span className="relative flex items-center gap-2">
        {busy ?? (
          <>
            {icon}
            <span className={cn(hoverLabel && 'transition-opacity duration-[var(--su-base)] group-hover:opacity-0')}>
              {children}
            </span>
          </>
        )}
      </span>
      {hoverLabel && !busy && (
        <span className="absolute inset-0 grid place-items-center opacity-0 transition-opacity duration-[var(--su-base)] group-hover:opacity-100">
          {hoverLabel}
        </span>
      )}
    </button>
  );
};

/* --------------------------------------------------------------- Segmented */

/**
 * Mutually exclusive choice, 2–4 options. Beyond four the labels stop fitting
 * and it wants to be a Select instead.
 *
 * Options carry an optional `hint`, surfaced as the title attribute — a
 * segmented control has room for a word and the choice usually needs a
 * sentence.
 */
export function Segmented<T extends string | number | boolean>({
  options, value, onChange, size = 'md', className,
}: {
  options: { value: T; label: React.ReactNode; icon?: React.ReactNode; hint?: string; disabled?: boolean }[];
  value: T;
  onChange: (v: T) => void;
  size?: 'sm' | 'md';
  className?: string;
}) {
  return (
    <div
      role="tablist"
      className={cn(
        'inline-flex items-center gap-0.5 rounded-[var(--su-radius-pill)] border border-[var(--su-border)]',
        'bg-[var(--su-surface-1)] p-0.5',
        className,
      )}
      style={{ backdropFilter: 'blur(var(--su-blur))' }}
    >
      {options.map((o) => {
        const active = value === o.value;
        return (
          <button
            key={String(o.value)}
            type="button"
            role="tab"
            aria-selected={active}
            disabled={o.disabled}
            title={o.hint}
            onClick={() => !o.disabled && onChange(o.value)}
            className={cn(
              'flex items-center gap-1.5 rounded-[var(--su-radius-pill)] transition-all duration-[var(--su-fast)]',
              size === 'sm' ? 'px-2.5 py-[3px] text-[9px]' : 'px-3.5 py-[5px] text-[11px]',
              o.disabled
                ? 'cursor-not-allowed text-[var(--su-text-ghost)] opacity-50'
                : active
                  ? 'bg-[var(--su-text)] font-semibold text-[var(--su-bg)]'
                  : 'text-[var(--su-text-faint)] hover:text-[var(--su-text)]',
            )}
          >
            {o.icon}
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

/* -------------------------------------------------------------- StatusChip */

export type Status = 'idle' | 'busy' | 'ok' | 'warn' | 'danger';

const STATUS_TONE: Record<Status, string> = {
  idle: 'bg-[var(--su-surface-2)] text-[var(--su-text-faint)]',
  busy: 'bg-[var(--su-busy-soft)] text-[var(--su-busy)]',
  ok: 'bg-[var(--su-ok-soft)] text-[var(--su-ok)]',
  warn: 'bg-[var(--su-warn-soft)] text-[var(--su-warn)]',
  danger: 'bg-[var(--su-danger-soft)] text-[var(--su-danger)]',
};

/**
 * A word about state. Kept tiny and low-contrast on purpose: it labels the
 * thing beside it, and a chip that outshouts its own heading has the hierarchy
 * backwards.
 */
export const StatusChip: React.FC<{
  status: Status;
  children: React.ReactNode;
  icon?: React.ReactNode;
  className?: string;
}> = ({ status, children, icon, className }) => (
  <span
    className={cn(
      'inline-flex items-center gap-1 rounded-[var(--su-radius-pill)] px-2 py-[1px]',
      'text-[9px] font-semibold tracking-normal',
      STATUS_TONE[status], className,
    )}
  >
    {icon}
    {children}
  </span>
);

/* -------------------------------------------------------------- StepMarker */

/**
 * The numbered dot on a step. It carries four states in one 22px circle, and
 * the number only shows while the step is waiting — once something has
 * happened to a step, what happened matters more than where it sits in the
 * sequence, and the position is already obvious from the layout.
 */
export const StepMarker: React.FC<{
  index: number;
  status: Status;
  icons?: Partial<Record<'busy' | 'ok' | 'warn' | 'danger', React.ReactNode>>;
  size?: number;
}> = ({ index, status, icons, size = 22 }) => {
  const RING: Record<Status, string> = {
    idle: 'border-[var(--su-border)] text-[var(--su-text-ghost)]',
    busy: 'border-[var(--su-busy)] text-[var(--su-busy)]',
    ok: 'border-[var(--su-ok)] text-[var(--su-ok)]',
    warn: 'border-[var(--su-warn)] text-[var(--su-warn)]',
    danger: 'border-[var(--su-danger)] text-[var(--su-danger)]',
  };
  const glyph = status === 'idle' ? index : icons?.[status as 'busy' | 'ok' | 'warn' | 'danger'];
  return (
    <span
      style={{ width: size, height: size }}
      className={cn(
        'grid shrink-0 place-items-center rounded-[var(--su-radius-pill)] border text-[10px] font-semibold',
        RING[status],
      )}
    >
      {glyph ?? index}
    </span>
  );
};

/* ------------------------------------------------------------- ProgressRing */

/** Determinate ring. Sized to sit inside a lg PillButton beside its label. */
export const ProgressRing: React.FC<{ value: number; size?: number; stroke?: number }> = ({
  value, size = 26, stroke = 2.5,
}) => {
  const r = 12;
  const c = 2 * Math.PI * r;
  return (
    <svg viewBox="0 0 30 30" width={size} height={size} className="-rotate-90">
      <circle cx="15" cy="15" r={r} fill="none" stroke="var(--su-border)" strokeWidth={stroke} />
      <circle
        cx="15" cy="15" r={r} fill="none"
        stroke="var(--su-accent)" strokeWidth={stroke} strokeLinecap="round"
        strokeDasharray={c}
        strokeDashoffset={c * (1 - Math.max(0, Math.min(100, value)) / 100)}
        style={{ transition: 'stroke-dashoffset 350ms linear' }}
      />
    </svg>
  );
};

/* ----------------------------------------------------------------- Tooltip */

/**
 * Hover label. Deliberately not a focus-triggered popover: it holds a hint,
 * never the only copy of something a keyboard user needs. If the tooltip is
 * the only place the information exists, that is a sign it belongs in the
 * interface instead.
 */
export const Tooltip: React.FC<{
  label: React.ReactNode;
  side?: 'top' | 'bottom' | 'left' | 'right';
  children: React.ReactElement;
}> = ({ label, side = 'top', children }) => {
  const [open, setOpen] = useState(false);
  const pos = {
    top: 'bottom-full left-1/2 -translate-x-1/2 mb-2',
    bottom: 'top-full left-1/2 -translate-x-1/2 mt-2',
    left: 'right-full top-1/2 -translate-y-1/2 mr-2',
    right: 'left-full top-1/2 -translate-y-1/2 ml-2',
  }[side];

  return (
    <span
      className="relative inline-flex"
      onMouseEnter={() => setOpen(true)}
      onMouseLeave={() => setOpen(false)}
      onFocus={() => setOpen(true)}
      onBlur={() => setOpen(false)}
    >
      {children}
      {open && (
        <span
          role="tooltip"
          className={cn(
            'su-pop pointer-events-none absolute z-[999] whitespace-nowrap rounded-[var(--su-radius-sm)]',
            'border border-[var(--su-border)] bg-[var(--su-bg-raised)] px-2.5 py-1.5',
            'text-[11px] font-medium text-[var(--su-text-dim)] shadow-[var(--su-shadow-lift)]',
            pos,
          )}
          style={{ backdropFilter: 'blur(var(--su-blur-heavy))' }}
        >
          {label}
        </span>
      )}
    </span>
  );
};

/* ----------------------------------------------------------------- Popover */

/**
 * Anchored panel with an outside-click scrim.
 *
 * The scrim is a real element rather than a document listener because it also
 * blocks clicks reaching what is underneath — dismissing a popover should not
 * simultaneously press the button behind it, which is the classic bug in the
 * document-listener version.
 */
export const Popover: React.FC<{
  open: boolean;
  onClose: () => void;
  anchor?: 'top' | 'bottom';
  className?: string;
  children: React.ReactNode;
}> = ({ open, onClose, anchor = 'bottom', className, children }) => {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;
  return (
    <>
      <div className="fixed inset-0 z-[90]" onClick={onClose} />
      <div
        className={cn(
          'su-pop absolute z-[100] rounded-[var(--su-radius-md)] border border-[var(--su-border)]',
          'bg-[var(--su-bg-raised)] p-3 shadow-[var(--su-shadow-lift)]',
          anchor === 'bottom' ? 'top-full mt-2' : 'bottom-full mb-2',
          className,
        )}
        style={{ backdropFilter: 'blur(var(--su-blur-heavy))' }}
      >
        {children}
      </div>
    </>
  );
};

/* ------------------------------------------------------------------ Slider */

/**
 * Labelled range with a live readout.
 *
 * The readout is not decoration. A slider with no number is unusable for
 * anything you might want to reproduce, come back to, or tell somebody about —
 * and every slider in a tool like this is eventually one of those.
 */
export const Slider: React.FC<{
  label: React.ReactNode;
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  step?: number;
  format?: (v: number) => string;
  hint?: string;
  disabled?: boolean;
}> = ({ label, value, onChange, min = 0, max = 1, step = 0.01, format, hint, disabled }) => {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <label className={cn('block', disabled && 'opacity-50')} title={hint}>
      <span className="mb-1.5 flex items-baseline justify-between">
        <span className="text-[11px] uppercase tracking-[0.14em] text-[var(--su-text-faint)]">{label}</span>
        <span className="font-mono text-[11px] text-[var(--su-text-dim)]">
          {format ? format(value) : value.toFixed(2)}
        </span>
      </span>
      <input
        type="range"
        min={min} max={max} step={step} value={value} disabled={disabled}
        onChange={(e) => onChange(Number(e.target.value))}
        className="su-range h-1 w-full cursor-pointer appearance-none rounded-[var(--su-radius-pill)] disabled:cursor-not-allowed"
        style={{
          background:
            `linear-gradient(to right, var(--su-accent) ${pct}%, var(--su-surface-3) ${pct}%)`,
        }}
      />
    </label>
  );
};

/**
 * Thumb styling has to be injected: ::-webkit-slider-thumb cannot be expressed
 * as a Tailwind utility or an inline style. Mount this once, near the root.
 */
export const SliderStyles: React.FC = () => (
  <style>{`
    .su-range::-webkit-slider-thumb {
      -webkit-appearance: none; appearance: none;
      width: 13px; height: 13px; border-radius: 999px;
      background: var(--su-text); border: none; cursor: pointer;
      box-shadow: 0 1px 4px rgb(0 0 0 / 0.5);
    }
    .su-range::-moz-range-thumb {
      width: 13px; height: 13px; border-radius: 999px;
      background: var(--su-text); border: none; cursor: pointer;
    }
    .su-range:focus-visible::-webkit-slider-thumb { outline: 2px solid var(--su-border-focus); outline-offset: 2px; }
  `}</style>
);

/* ------------------------------------------------------------------- Field */

/**
 * Single-line input in a pill. `action` is the affordance on the right — a
 * submit arrow, a clear button — and it lives inside the border so the whole
 * thing reads as one control rather than an input next to a button.
 */
export const Field: React.FC<
  Omit<React.InputHTMLAttributes<HTMLInputElement>, 'size'> & {
    icon?: React.ReactNode;
    action?: React.ReactNode;
    wrapperClassName?: string;
  }
> = ({ icon, action, wrapperClassName, className, ...rest }) => (
  <div
    className={cn(
      'flex items-center gap-2 rounded-[var(--su-radius-md)] border border-[var(--su-border)]',
      'bg-[var(--su-surface-1)] px-3.5 py-2 transition-colors duration-[var(--su-fast)]',
      'focus-within:border-[var(--su-border-strong)]',
      wrapperClassName,
    )}
    style={{ backdropFilter: 'blur(var(--su-blur))' }}
  >
    {icon && <span className="shrink-0 text-[var(--su-text-faint)]">{icon}</span>}
    <input
      className={cn(
        'min-w-0 flex-1 bg-transparent text-[12px] text-[var(--su-text-dim)] outline-none',
        'placeholder:text-[var(--su-text-ghost)]',
        className,
      )}
      {...rest}
    />
    {action}
  </div>
);

/* --------------------------------------------------------------- TextArea */

/** Multi-line well. Same ink as Field; sunken rather than raised because you
 *  are putting something into it. */
export const TextArea: React.FC<React.TextareaHTMLAttributes<HTMLTextAreaElement>> = ({
  className, ...rest
}) => (
  <textarea
    className={cn(
      'w-full resize-none rounded-[var(--su-radius-sm)] border border-[var(--su-border)]',
      'bg-[var(--su-surface-sunk)] p-2 text-[11px] leading-relaxed text-[var(--su-text-dim)] outline-none',
      'placeholder:text-[var(--su-text-ghost)] focus:border-[var(--su-border-strong)]',
      className,
    )}
    {...rest}
  />
);

/* ---------------------------------------------------------------- useMeasure
 * Small hook the layout components share: report an element's width so a
 * component can adapt without a media query. Media queries key on the viewport,
 * which is the wrong question when a card is in a sidebar. */
export function useMeasure<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, width] as const;
}
