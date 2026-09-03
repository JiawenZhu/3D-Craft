import React from 'react';
import { cn } from './cn';
import { GlassPanel, IconButton, Tooltip, type Status } from './primitives';

/* ===========================================================================
 * studio-ui — workspace
 *
 * The chrome around a working canvas: rails, toolbars, readouts, notices.
 *
 * The rule that shapes all of it — the canvas is the product and the chrome is
 * not. Everything here is small, translucent, and pinned to an edge, so that
 * on a 13" screen the thing being worked on still owns the middle. When a
 * control needs more room than that allows, it becomes a Popover rather than
 * growing the panel.
 * ========================================================================= */

/* ----------------------------------------------------------------- Toolbar */

export interface ToolbarItem {
  id: string;
  icon: React.ReactNode;
  label: string;
  onClick?: () => void;
  active?: boolean;
  disabled?: boolean;
  /** Draws a hairline above this item — group things that belong together. */
  separated?: boolean;
}

/**
 * A rail of icon buttons, vertical by default.
 *
 * Every item gets a Tooltip, and that is not politeness — an icon-only rail is
 * unusable without one, and the tooltip is the only place the control's name
 * exists. If an item's meaning cannot survive being reduced to one glyph plus a
 * hover label, it belongs in a menu instead.
 */
export const Toolbar: React.FC<{
  items: ToolbarItem[];
  orientation?: 'vertical' | 'horizontal';
  side?: 'left' | 'right' | 'top' | 'bottom';
  className?: string;
}> = ({ items, orientation = 'vertical', side = 'left', className }) => (
  <GlassPanel
    radius="pill"
    className={cn(
      'flex gap-0.5 p-1',
      orientation === 'vertical' ? 'flex-col' : 'flex-row',
      className,
    )}
  >
    {items.map((item) => (
      <React.Fragment key={item.id}>
        {item.separated && (
          <span
            className={cn(
              'bg-[var(--su-border)]',
              orientation === 'vertical' ? 'mx-2 my-1 h-px' : 'my-2 mx-1 w-px',
            )}
          />
        )}
        <Tooltip label={item.label} side={side === 'left' ? 'right' : side === 'right' ? 'left' : 'bottom'}>
          <IconButton
            active={item.active}
            disabled={item.disabled}
            onClick={item.onClick}
            aria-label={item.label}
          >
            {item.icon}
          </IconButton>
        </Tooltip>
      </React.Fragment>
    ))}
  </GlassPanel>
);

/* --------------------------------------------------------------- InfoPanel */

/**
 * Key/value readout — dimensions, counts, file size.
 *
 * Values are monospaced and right-aligned so a column of numbers lines up at
 * the decimal. Labels are uppercase and tracked out, which lets them sit at a
 * much lower contrast without becoming unreadable — that contrast gap is what
 * makes the values scannable.
 */
export const InfoPanel: React.FC<{
  title?: React.ReactNode;
  rows: { label: React.ReactNode; value: React.ReactNode; title?: string }[];
  actions?: React.ReactNode;
  className?: string;
}> = ({ title, rows, actions, className }) => (
  <GlassPanel className={cn('p-3', className)}>
    {title && (
      <div className="mb-1.5 flex items-center justify-between">
        <span className="text-[11px] uppercase tracking-[0.16em] text-[var(--su-text-faint)]">{title}</span>
        {actions}
      </div>
    )}
    <dl>
      {rows.map((r, i) => (
        <div
          key={i}
          title={r.title}
          className="flex items-center justify-between gap-3 border-b border-[var(--su-border)] py-2 last:border-0"
        >
          <dt className="shrink-0 text-[11px] uppercase tracking-[0.14em] text-[var(--su-text-faint)]">
            {r.label}
          </dt>
          <dd className="truncate text-right font-mono text-[12px] text-[var(--su-text-dim)]">{r.value}</dd>
        </div>
      ))}
    </dl>
  </GlassPanel>
);

/* ------------------------------------------------------------------ Notice */

/**
 * A line of feedback that is not a modal.
 *
 * Dismissible by default because the alternative — a notice that stays until
 * something else replaces it — trains people to stop reading the spot it
 * appears in. If a message genuinely must be acknowledged, it is a dialog, not
 * a notice.
 */
export const Notice: React.FC<{
  tone?: Status;
  icon?: React.ReactNode;
  children: React.ReactNode;
  onDismiss?: () => void;
  action?: React.ReactNode;
  className?: string;
}> = ({ tone = 'idle', icon, children, onDismiss, action, className }) => {
  const TONE: Record<Status, string> = {
    idle: 'border-[var(--su-border)] bg-[var(--su-surface-1)] text-[var(--su-text-dim)]',
    busy: 'border-[var(--su-busy)] bg-[var(--su-busy-soft)] text-[var(--su-busy)]',
    ok: 'border-[var(--su-ok)] bg-[var(--su-ok-soft)] text-[var(--su-ok)]',
    warn: 'border-[var(--su-warn)] bg-[var(--su-warn-soft)] text-[var(--su-warn)]',
    danger: 'border-[var(--su-danger)] bg-[var(--su-danger-soft)] text-[var(--su-danger)]',
  };
  return (
    <div
      role={tone === 'danger' ? 'alert' : 'status'}
      className={cn(
        'su-pop flex items-start gap-2 rounded-[var(--su-radius-sm)] border px-3 py-2',
        'text-[11px] leading-relaxed',
        TONE[tone], className,
      )}
      style={{ backdropFilter: 'blur(var(--su-blur))' }}
    >
      {icon && <span className="mt-px shrink-0">{icon}</span>}
      <span className="min-w-0 flex-1">{children}</span>
      {action}
      {onDismiss && (
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="shrink-0 opacity-60 transition-opacity hover:opacity-100"
        >
          ×
        </button>
      )}
    </div>
  );
};

/* -------------------------------------------------------------- StatusPill */

/**
 * The "is the backend alive" readout, for a top bar.
 *
 * It states what IS rather than what is wrong, and stays visible when
 * everything is fine. A health indicator that only appears on failure is one
 * the user has no reason to trust, because they have never seen it working.
 */
export const StatusPill: React.FC<{
  status: Status;
  label: React.ReactNode;
  detail?: string;
  className?: string;
}> = ({ status, label, detail, className }) => {
  const DOT: Record<Status, string> = {
    idle: 'bg-[var(--su-text-ghost)]',
    busy: 'su-pulse bg-[var(--su-busy)]',
    ok: 'bg-[var(--su-ok)]',
    warn: 'bg-[var(--su-warn)]',
    danger: 'bg-[var(--su-danger)]',
  };
  return (
    <span
      title={detail}
      className={cn(
        'inline-flex items-center gap-1.5 rounded-[var(--su-radius-pill)] border border-[var(--su-border)]',
        'bg-[var(--su-surface-1)] px-2.5 py-1 font-mono text-[10px] text-[var(--su-text-faint)]',
        className,
      )}
      style={{ backdropFilter: 'blur(var(--su-blur))' }}
    >
      <span className={cn('h-1.5 w-1.5 rounded-[var(--su-radius-pill)]', DOT[status])} />
      {label}
    </span>
  );
};

/* -------------------------------------------------------------- StageHeader */

/**
 * The bar above a full-page working view: back, title, actions.
 *
 * The title is centred and the controls are pinned to the edges, so the header
 * stays symmetric no matter how many actions there are — a header whose title
 * shifts sideways as buttons appear is the fastest way to make an app feel
 * unfinished.
 */
export const StageHeader: React.FC<{
  onBack?: () => void;
  backLabel?: React.ReactNode;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  actions?: React.ReactNode;
  className?: string;
}> = ({ onBack, backLabel = 'Back', title, subtitle, actions, className }) => (
  <header className={cn('relative flex items-center justify-between gap-4 px-4 py-3', className)}>
    <div className="flex min-w-0 flex-1 items-center gap-2">
      {onBack && (
        <button
          type="button"
          onClick={onBack}
          className={cn(
            'flex items-center gap-1.5 rounded-[var(--su-radius-pill)] border border-[var(--su-border)]',
            'bg-[var(--su-surface-1)] px-3.5 py-2 text-[12px] text-[var(--su-text-dim)]',
            'transition-colors hover:border-[var(--su-border-strong)] hover:text-[var(--su-text)]',
          )}
          style={{ backdropFilter: 'blur(var(--su-blur))' }}
        >
          ← {backLabel}
        </button>
      )}
    </div>

    <div className="pointer-events-none absolute left-1/2 -translate-x-1/2 text-center">
      <h1 className="truncate text-[15px] font-semibold text-[var(--su-text)]">{title}</h1>
      {subtitle && <p className="truncate text-[10px] text-[var(--su-text-ghost)]">{subtitle}</p>}
    </div>

    <div className="flex min-w-0 flex-1 items-center justify-end gap-2">{actions}</div>
  </header>
);

/* ----------------------------------------------------------------- ModeRail */

/**
 * A vertical rail of labelled modes — the left edge of a generator.
 *
 * Each item is an icon over a two-word caption. The caption is what makes this
 * different from a Toolbar: a mode changes what the whole workspace is for, and
 * that is too consequential to communicate with a glyph and a hover.
 */
export function ModeRail<T extends string>({
  items, value, onChange, className,
}: {
  items: { value: T; label: string; icon: React.ReactNode; disabled?: boolean }[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
}) {
  return (
    <GlassPanel className={cn('flex flex-col gap-0.5 p-1', className)}>
      {items.map((item) => {
        const active = value === item.value;
        return (
          <button
            key={item.value}
            type="button"
            disabled={item.disabled}
            onClick={() => onChange(item.value)}
            aria-current={active}
            className={cn(
              'flex w-[62px] flex-col items-center gap-1 rounded-[var(--su-radius-sm)] px-1 py-2',
              'text-center transition-all duration-[var(--su-fast)]',
              item.disabled && 'cursor-not-allowed opacity-40',
              active
                ? 'bg-[var(--su-surface-3)] text-[var(--su-text)]'
                : 'text-[var(--su-text-faint)] hover:bg-[var(--su-surface-2)] hover:text-[var(--su-text)]',
            )}
          >
            {item.icon}
            <span className="text-[8px] font-medium leading-tight">{item.label}</span>
          </button>
        );
      })}
    </GlassPanel>
  );
}

/* ------------------------------------------------------------- StageOverlay */

/**
 * A full-screen working view.
 *
 * This is a PAGE, not a modal over a live page — which is why it renders its
 * own background rather than a translucent scrim. When a viewer opens over a
 * gallery that is still mounted, every thumbnail in that gallery is still
 * decoded and every canvas behind it is still running. Unmount the grid and
 * render this instead; on a laptop it is the difference between a viewer that
 * spins smoothly and one that stutters.
 */
export const StageOverlay: React.FC<{
  children: React.ReactNode;
  className?: string;
}> = ({ children, className }) => (
  <div className={cn('fixed inset-0 z-[150] flex flex-col bg-[var(--su-bg)]', className)}>
    {children}
  </div>
);
