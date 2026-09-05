import React, { useCallback, useRef, useState } from 'react';
import { cn } from './cn';
import { GlassPanel, type Status } from './primitives';

/* ===========================================================================
 * studio-ui — gallery
 *
 * Grids of generated things, and the ways in and out of them.
 *
 * The governing constraint here is memory, not looks. A gallery of generated
 * media is dozens of full-size images the browser will happily decode all at
 * once, and on a laptop that is the difference between a page that scrolls and
 * a page that stutters. Every component below is built around that: lazy
 * decoding by default, an explicit aspect box so nothing reflows as images
 * land, and a viewer that is a separate page rather than a layer on top of a
 * still-mounted grid.
 * ========================================================================= */

/* ------------------------------------------------------------------- Thumb */

/**
 * One image in a grid, with a drawn fallback for items that have no picture
 * yet.
 *
 * `loading="lazy"` and `decoding="async"` are the whole point. Without them a
 * 40-card grid decodes 40 full-size images during layout; with them the
 * browser skips everything off-screen. It is one line and it is the single
 * biggest performance decision in this file.
 */
export const Thumb: React.FC<{
  src?: string;
  alt: string;
  /** Drawn when there is no src — a seeded shape beats a grey box. */
  fallback?: React.ReactNode;
  className?: string;
  fit?: 'cover' | 'contain';
}> = ({ src, alt, fallback, className, fit = 'cover' }) => {
  const [failed, setFailed] = useState(false);
  if (!src || failed) {
    return (
      <div className={cn('grid h-full w-full place-items-center bg-[var(--su-surface-sunk)]', className)}>
        {fallback ?? <span className="text-[10px] text-[var(--su-text-ghost)]">{alt}</span>}
      </div>
    );
  }
  return (
    <img
      src={src}
      alt={alt}
      loading="lazy"
      decoding="async"
      onError={() => setFailed(true)}
      className={cn('h-full w-full', className)}
      style={{ objectFit: fit }}
    />
  );
};

/* --------------------------------------------------------------- MediaCard */

export interface Badge {
  /** Short. A badge is a glance, not a sentence. */
  label: React.ReactNode;
  icon?: React.ReactNode;
  tone?: Status;
  title?: string;
}

/**
 * A gallery tile.
 *
 * Meta is hidden until hover on purpose. A grid of generated work is looked at
 * before it is read — captions on every tile turn a gallery into a spreadsheet.
 * The information is one hover away, and the badges carry anything that must
 * survive without hovering.
 */
export const MediaCard: React.FC<{
  title: string;
  src?: string;
  fallback?: React.ReactNode;
  onOpen?: () => void;
  /** Top-left. State that must be readable without hovering. */
  badges?: Badge[];
  /** Top-right toggle — a like, a pin, a select. */
  toggle?: { active: boolean; onToggle: () => void; icon: React.ReactNode; label: string };
  /** Shown on hover, under the title. */
  meta?: React.ReactNode;
  /** One line under the title on hover — what clicking will do. */
  hint?: React.ReactNode;
  aspect?: string;
  className?: string;
}> = ({ title, src, fallback, onOpen, badges, toggle, meta, hint, aspect = '1 / 1', className }) => (
  <div
    role={onOpen ? 'button' : undefined}
    tabIndex={onOpen ? 0 : undefined}
    onClick={onOpen}
    onKeyDown={(e) => {
      if (!onOpen) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onOpen(); }
    }}
    style={{ aspectRatio: aspect }}
    className={cn(
      'group relative overflow-hidden rounded-[var(--su-radius-lg)] border border-[var(--su-border)]',
      'bg-[var(--su-surface-1)] text-left transition-all duration-[var(--su-base)]',
      onOpen && 'cursor-pointer hover:border-[var(--su-border-strong)] hover:shadow-[var(--su-shadow-lift)]',
      'focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--su-border-focus)]',
      className,
    )}
  >
    <Thumb
      src={src}
      alt={title}
      fallback={fallback}
      className="transition-transform duration-[var(--su-slow)] group-hover:scale-[1.06]"
    />

    {badges && badges.length > 0 && (
      <span className="absolute left-3 top-3 flex flex-col items-start gap-1">
        {badges.map((b, i) => (
          <span
            key={i}
            title={b.title}
            className={cn(
              'flex items-center gap-1 rounded-[var(--su-radius-pill)] px-2 py-1',
              'text-[9px] font-semibold backdrop-blur-md',
              b.tone === 'ok' ? 'bg-[var(--su-ok-soft)] text-[var(--su-ok)]'
                : b.tone === 'warn' ? 'bg-[var(--su-warn-soft)] text-[var(--su-warn)]'
                  : b.tone === 'danger' ? 'bg-[var(--su-danger-soft)] text-[var(--su-danger)]'
                    : 'bg-black/45 text-[var(--su-text-dim)]',
            )}
          >
            {b.icon}
            {b.label}
          </span>
        ))}
      </span>
    )}

    {toggle && (
      <span
        role="button"
        tabIndex={0}
        aria-pressed={toggle.active}
        aria-label={toggle.label}
        onClick={(e) => { e.stopPropagation(); toggle.onToggle(); }}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); toggle.onToggle(); }
        }}
        className={cn(
          'absolute right-3 top-3 grid h-8 w-8 cursor-pointer place-items-center',
          'rounded-[var(--su-radius-pill)] backdrop-blur-md transition-all',
          toggle.active
            ? 'bg-[var(--su-text)] text-[var(--su-bg)]'
            : 'bg-black/35 text-white/80 hover:bg-black/55 hover:text-white',
        )}
      >
        {toggle.icon}
      </span>
    )}

    <span
      className={cn(
        'pointer-events-none absolute inset-x-0 bottom-0 flex translate-y-2 flex-col gap-0.5 p-4',
        'bg-gradient-to-t from-black/90 via-black/55 to-transparent',
        'opacity-0 transition-all duration-[var(--su-base)] group-hover:translate-y-0 group-hover:opacity-100',
      )}
    >
      <span className="truncate text-[13px] font-semibold text-white">{title}</span>
      {hint && <span className="text-[10px] text-[var(--su-accent)]">{hint}</span>}
      {meta && <span className="flex items-center gap-2 text-[10px] text-[var(--su-text-faint)]">{meta}</span>}
    </span>
  </div>
);

/* ---------------------------------------------------------------- CardGrid */

/** Responsive grid with a sensible default. Override `cols` for denser sets. */
export const CardGrid: React.FC<{
  children: React.ReactNode;
  cols?: string;
  className?: string;
}> = ({ children, cols = 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4', className }) => (
  <div className={cn('grid gap-5', cols, className)}>{children}</div>
);

/* -------------------------------------------------------------- EmptyState */

/**
 * What a grid says when it has nothing.
 *
 * Two lines, and the second is the important one: it names the specific next
 * action. "No items" tells the user what they can already see. "Drop an image
 * above, or pick one from the gallery" tells them what to do about it.
 */
export const EmptyState: React.FC<{
  title: React.ReactNode;
  hint?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
}> = ({ title, hint, action, className }) => (
  <div
    className={cn(
      'grid h-64 place-items-center rounded-[var(--su-radius-lg)] border border-dashed',
      'border-[var(--su-border)] text-center',
      className,
    )}
  >
    <div>
      <p className="text-[13px] text-[var(--su-text-faint)]">{title}</p>
      {hint && <p className="mt-1 text-[11px] text-[var(--su-text-ghost)]">{hint}</p>}
      {action && <div className="mt-3 flex justify-center">{action}</div>}
    </div>
  </div>
);

/* --------------------------------------------------------------- ShelfTabs */

/**
 * Big section switch with counts — the top of a gallery page.
 *
 * The count is part of the label rather than a badge beside it, because the
 * number is what people actually navigate by once they have used the thing
 * twice ("the tab with 40 in it").
 */
export function ShelfTabs<T extends string>({
  tabs, value, onChange, className,
}: {
  tabs: { value: T; label: string; count?: number }[];
  value: T;
  onChange: (v: T) => void;
  className?: string;
}) {
  return (
    <div className={cn('flex items-baseline gap-5', className)}>
      {tabs.map((t) => (
        <button
          key={t.value}
          type="button"
          onClick={() => onChange(t.value)}
          aria-current={value === t.value}
          className={cn(
            'text-[26px] font-semibold uppercase tracking-[0.02em] transition-colors duration-[var(--su-base)] sm:text-[30px]',
            value === t.value
              ? 'text-[var(--su-text)]'
              : 'text-[var(--su-text-ghost)] hover:text-[var(--su-text-faint)]',
          )}
        >
          {t.label}
          {t.count != null && (
            <span className="ml-2 align-middle text-[13px] font-normal text-[var(--su-text-ghost)]">
              {t.count}
            </span>
          )}
        </button>
      ))}
    </div>
  );
}

/* ------------------------------------------------------------- SearchField */

/**
 * Collapsed to an icon until used.
 *
 * A permanently-open search box on a gallery header competes with the content
 * for attention and is used maybe once a session. Collapsed, it costs 36px and
 * expands on click.
 */
export const SearchField: React.FC<{
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  icon?: React.ReactNode;
  clearIcon?: React.ReactNode;
}> = ({ value, onChange, placeholder = 'Search…', icon, clearIcon }) => {
  const [open, setOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  return (
    <div
      className={cn(
        'flex items-center overflow-hidden rounded-[var(--su-radius-pill)] border border-[var(--su-border)]',
        'bg-[var(--su-surface-1)] transition-all duration-[var(--su-base)]',
        open ? 'w-[220px] px-3' : 'w-9',
      )}
      style={{ backdropFilter: 'blur(var(--su-blur))' }}
    >
      <button
        type="button"
        onClick={() => { setOpen((v) => !v); requestAnimationFrame(() => inputRef.current?.focus()); }}
        aria-label={open ? 'Close search' : 'Search'}
        style={{ marginLeft: open ? -12 : 0 }}
        className="grid h-9 w-9 shrink-0 place-items-center text-[var(--su-text-faint)] transition-colors hover:text-[var(--su-text)]"
      >
        {icon ?? <SearchGlyph />}
      </button>
      {open && (
        <>
          <input
            ref={inputRef}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Escape') { onChange(''); setOpen(false); } }}
            placeholder={placeholder}
            className="h-9 min-w-0 flex-1 bg-transparent text-[12px] text-[var(--su-text-dim)] outline-none placeholder:text-[var(--su-text-ghost)]"
          />
          {value && (
            <button
              type="button"
              onClick={() => onChange('')}
              aria-label="Clear search"
              className="text-[var(--su-text-faint)] transition-colors hover:text-[var(--su-text)]"
            >
              {clearIcon ?? <CloseGlyph />}
            </button>
          )}
        </>
      )}
    </div>
  );
};

/* ------------------------------------------------------------- HistoryStrip */

/**
 * A horizontal row of small thumbnails — recent runs, versions, related items.
 *
 * Selection is a border rather than a scale or a glow, because the row is
 * dense and anything that changes an item's SIZE makes its neighbours move.
 */
export const HistoryStrip: React.FC<{
  items: { id: string; src?: string; title: string; status?: Status }[];
  activeId?: string;
  onPick: (id: string) => void;
  size?: number;
  className?: string;
}> = ({ items, activeId, onPick, size = 64, className }) => (
  <div className={cn('su-scroll flex gap-2 overflow-x-auto pb-2', className)}>
    {items.map((item) => (
      <button
        key={item.id}
        type="button"
        onClick={() => onPick(item.id)}
        title={item.title}
        style={{ width: size, height: size }}
        className={cn(
          'relative shrink-0 overflow-hidden rounded-[var(--su-radius-sm)] border transition-all',
          activeId === item.id
            ? 'border-[var(--su-border-focus)]'
            : 'border-[var(--su-border)] hover:border-[var(--su-border-strong)]',
        )}
      >
        <Thumb src={item.src} alt={item.title} />
        {item.status && (
          <span
            className={cn(
              'absolute bottom-1 right-1 h-1.5 w-1.5 rounded-[var(--su-radius-pill)]',
              item.status === 'busy' ? 'su-pulse bg-[var(--su-busy)]'
                : item.status === 'ok' ? 'bg-[var(--su-ok)]'
                  : item.status === 'danger' ? 'bg-[var(--su-danger)]'
                    : 'bg-[var(--su-text-ghost)]',
            )}
          />
        )}
      </button>
    ))}
  </div>
);

/* ---------------------------------------------------------------- DropZone */

/**
 * The image input. Drag, click, or paste.
 *
 * Paste is included because it is how people actually move a screenshot into a
 * tool, and it is three lines to support. The zone reports files; it never owns
 * them — object URLs have to be revoked by whoever created them, and a
 * component that both creates and forgets them is a leak with a nice border.
 */
export const DropZone: React.FC<{
  onFiles: (files: File[]) => void;
  accept?: string;
  multiple?: boolean;
  /** Rendered instead of the prompt when there is something to show. */
  children?: React.ReactNode;
  label?: React.ReactNode;
  hint?: React.ReactNode;
  className?: string;
}> = ({
  onFiles, accept = 'image/*', multiple = false, children, label, hint, className,
}) => {
  const [over, setOver] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const take = useCallback((list: FileList | null | undefined) => {
    const files = Array.from(list ?? []).filter((f) => f.type.startsWith('image/'));
    if (files.length) onFiles(multiple ? files : files.slice(0, 1));
  }, [onFiles, multiple]);

  return (
    <GlassPanel
      surface="sunk"
      onDragOver={(e) => { e.preventDefault(); setOver(true); }}
      onDragLeave={() => setOver(false)}
      onDrop={(e) => { e.preventDefault(); setOver(false); take(e.dataTransfer.files); }}
      onPaste={(e) => take(e.clipboardData?.files)}
      className={cn(
        'relative flex flex-col p-[10px] transition-all duration-[var(--su-base)]',
        over && 'border-[var(--su-border-focus)] bg-[var(--su-surface-2)]',
        className,
      )}
    >
      {label && <div className="mb-1.5 text-[13px] font-bold leading-none text-[var(--su-text)]">{label}</div>}

      <div className="relative min-h-0 flex-1">
        {children ?? (
          <button
            type="button"
            onClick={() => inputRef.current?.click()}
            className="group grid h-full w-full place-items-center rounded-[var(--su-radius-sm)] transition-colors hover:bg-[var(--su-surface-1)]"
          >
            <PlusGlyph />
          </button>
        )}
      </div>

      {hint && (
        <div className="mt-1.5 text-center text-[9px] font-medium text-[var(--su-text-ghost)]">{hint}</div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept={accept}
        multiple={multiple}
        hidden
        onChange={(e) => { take(e.target.files); e.target.value = ''; }}
      />
    </GlassPanel>
  );
};

/* ---------------------------------------------------------------- Lightbox */

/** Full-bleed image viewer. Click anywhere, or press escape, to dismiss. */
export const Lightbox: React.FC<{
  src: string;
  caption?: React.ReactNode;
  onClose: () => void;
}> = ({ src, caption, onClose }) => {
  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      onClick={onClose}
      className="fixed inset-0 z-[200] grid place-items-center bg-[var(--su-bg)]/90 p-8"
      style={{ backdropFilter: 'blur(var(--su-blur-heavy))' }}
    >
      <figure className="max-h-full max-w-[760px]" onClick={(e) => e.stopPropagation()}>
        <img src={src} alt="" className="max-h-[78vh] w-auto rounded-[var(--su-radius-md)] border border-[var(--su-border)]" />
        <figcaption className="mt-3 flex items-center justify-between text-[11px] text-[var(--su-text-faint)]">
          <span>{caption}</span>
          <button type="button" onClick={onClose} className="transition-colors hover:text-[var(--su-text)]">
            close
          </button>
        </figcaption>
      </figure>
    </div>
  );
};

/* --- fallback glyphs ----------------------------------------------------- */
const SearchGlyph = () => (
  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
       strokeLinecap="round" aria-hidden><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
);
const CloseGlyph = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
       strokeLinecap="round" aria-hidden><path d="M18 6 6 18M6 6l12 12" /></svg>
);
const PlusGlyph = () => (
  <svg width="38" height="38" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.1"
       strokeLinecap="round" aria-hidden
       className="text-[var(--su-text-dim)] transition-transform duration-[var(--su-base)] group-hover:scale-110">
    <path d="M12 5v14M5 12h14" />
  </svg>
);
