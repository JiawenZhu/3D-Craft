import React, { useEffect, useRef, useState } from 'react';
import { cn } from '../../lib/cn';

/* ---------------------------------------------------------------- Tooltip */
export const Tip: React.FC<{
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
    <span className="relative inline-flex" onMouseEnter={() => setOpen(true)} onMouseLeave={() => setOpen(false)}>
      {children}
      {open && (
        <span className={cn(
          'pointer-events-none absolute z-[999] animate-popIn whitespace-nowrap rounded-lg border border-white/10',
          'bg-ink-800/95 px-2.5 py-1.5 text-[11px] font-medium text-chalk shadow-lift backdrop-blur-xl', pos,
        )}>
          {label}
        </span>
      )}
    </span>
  );
};

/* -------------------------------------------------------------- IconButton */
export const IconButton = React.forwardRef<HTMLButtonElement, React.ButtonHTMLAttributes<HTMLButtonElement> & {
  active?: boolean; size?: number;
}>(({ active, size = 34, className, style, ...rest }, ref) => (
  <button
    ref={ref}
    type="button"
    data-active={active ? 'true' : undefined}
    style={{ width: size, height: size, ...style }}
    className={cn('rd-icon-btn shrink-0 border', className)}
    {...rest}
  />
));
IconButton.displayName = 'IconButton';

/* --------------------------------------------------------------- Segmented */
export function Segmented<T extends string>({ options, value, onChange, className, size = 'md' }: {
  options: { value: T; label: React.ReactNode; hint?: string }[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
  size?: 'sm' | 'md';
}) {
  return (
    <div className={cn('inline-flex items-center gap-0.5 rounded-full border border-white/10 bg-white/[0.03] p-0.5 backdrop-blur-xl', className)}>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          title={o.hint}
          onClick={() => onChange(o.value)}
          className={cn(
            'rounded-full transition-all duration-200',
            size === 'sm' ? 'px-2.5 py-1 text-[11px]' : 'px-3.5 py-1.5 text-xs',
            value === o.value ? 'bg-white/90 font-medium text-ink' : 'text-chalk-dim hover:text-white',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------------ Switch */
export const Switch: React.FC<{ checked: boolean; onChange: (v: boolean) => void; label?: string }> = ({ checked, onChange, label }) => (
  <button
    type="button"
    onClick={() => onChange(!checked)}
    className="group flex items-center gap-2.5"
  >
    <span className={cn(
      'relative h-[18px] w-[32px] rounded-full border transition-colors duration-200',
      checked ? 'border-white/60 bg-white/80' : 'border-white/12 bg-white/[0.06]',
    )}>
      <span className={cn(
        'absolute top-1/2 h-3 w-3 -translate-y-1/2 rounded-full transition-all duration-200',
        checked ? 'left-[16px] bg-ink' : 'left-[2px] bg-chalk-faint',
      )} />
    </span>
    {label && <span className={cn('text-xs transition-colors', checked ? 'text-white' : 'text-chalk-dim group-hover:text-chalk')}>{label}</span>}
  </button>
);

/* ------------------------------------------------------------------ Slider */
export const Slider: React.FC<{
  value: number; min: number; max: number; step?: number;
  onChange: (v: number) => void; label: string; format?: (v: number) => string;
}> = ({ value, min, max, step = 1, onChange, label, format }) => {
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <label className="block">
      <span className="mb-2 flex items-baseline justify-between">
        <span className="text-[11px] uppercase tracking-[0.14em] text-chalk-faint">{label}</span>
        <span className="font-mono text-[11px] text-chalk">{format ? format(value) : value}</span>
      </span>
      <span className="relative block h-4">
        <span className="absolute top-1/2 h-[3px] w-full -translate-y-1/2 rounded-full bg-white/10" />
        <span className="absolute top-1/2 h-[3px] -translate-y-1/2 rounded-full bg-gradient-to-r from-rose to-lilac" style={{ width: `${pct}%` }} />
        <span className="absolute top-1/2 h-3 w-3 -translate-x-1/2 -translate-y-1/2 rounded-full border border-white/70 bg-ink-900 shadow-[0_0_10px_rgba(209,158,233,.6)]" style={{ left: `${pct}%` }} />
        <input
          type="range" min={min} max={max} step={step} value={value}
          onChange={(e) => onChange(Number(e.target.value))}
          className="absolute inset-0 w-full cursor-pointer opacity-0"
        />
      </span>
    </label>
  );
};

/* ----------------------------------------------------------------- Popover */
export const Popover: React.FC<{
  open: boolean; onClose: () => void; children: React.ReactNode; className?: string; anchor?: 'top' | 'bottom';
}> = ({ open, onClose, children, className, anchor = 'top' }) => {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) onClose(); };
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    // defer so the click that opened it doesn't immediately close it
    const t = setTimeout(() => document.addEventListener('mousedown', onDoc), 0);
    document.addEventListener('keydown', onKey);
    return () => { clearTimeout(t); document.removeEventListener('mousedown', onDoc); document.removeEventListener('keydown', onKey); };
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div
      ref={ref}
      className={cn(
        'absolute z-50 animate-popIn rounded-2xl border border-white/10 bg-ink-900/95 p-4 shadow-lift backdrop-blur-2xl',
        anchor === 'top' ? 'bottom-full mb-3' : 'top-full mt-3',
        className,
      )}
    >
      {children}
    </div>
  );
};

/* ------------------------------------------------------------------- Modal */
export const Modal: React.FC<{ open: boolean; onClose: () => void; children: React.ReactNode; className?: string }> = ({ open, onClose, children, className }) => {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    if (open) document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[200] grid place-items-center p-6">
      <div className="absolute inset-0 bg-black/70 backdrop-blur-sm" onClick={onClose} />
      <div className={cn('relative animate-popIn rd-panel w-full max-w-lg p-6 shadow-lift', className)}>{children}</div>
    </div>
  );
};

/* ----------------------------------------------------------- Section label */
export const FieldLabel: React.FC<{ children: React.ReactNode; className?: string }> = ({ children, className }) => (
  <div className={cn('mb-2 text-[11px] font-medium uppercase tracking-[0.16em] text-chalk-faint', className)}>{children}</div>
);
