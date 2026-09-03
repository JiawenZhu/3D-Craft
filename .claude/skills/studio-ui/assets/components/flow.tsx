import React, { useState } from 'react';
import { cn } from './cn';
import { GlassPanel, IconButton, PillButton, StatusChip, StepMarker, TextArea, type Status } from './primitives';

/* ===========================================================================
 * studio-ui — flow
 *
 * A pipeline drawn as the steps it actually is, instead of as one progress bar.
 *
 *   input ──► transform ──► render ──► result
 *
 * Why this exists. A single bar covering a multi-model, multi-minute job tells
 * the user nothing they can act on: not which stage is slow, not which stage
 * failed, not what the machine decided on their behalf along the way. Splitting
 * it buys three things that matter more than the pixels:
 *
 *   - failure gets attributed to a stage, not to "the job"
 *   - a retry can start from the stage that broke, so the expensive stages
 *     before it are not paid for twice
 *   - intermediate artefacts become visible and, where it makes sense,
 *     EDITABLE — a generated prompt you can correct before it is rendered is a
 *     different product from one you merely watch scroll past
 *
 * The kit is deliberately unopinionated about what a stage does. It renders
 * whatever a node carries: an image, text, a progress readout, or your own
 * children.
 * ========================================================================= */

export interface FlowNodeData {
  id: string;
  /** Heading. Say what the stage DOES, not what it is called internally. */
  label: string;
  status: Status;
  /** Sub-line: which engine ran, how long it took. */
  meta?: string;
  /** An image this stage produced or consumed. */
  imageUrl?: string;
  /** Text this stage produced or consumed. */
  text?: string;
  /** One line about the choice this stage made. Reads as the machine's voice. */
  note?: string;
  /** 0–100, while the stage is working. */
  progress?: number;
  /** Live narration under the progress bar. */
  message?: string;
  error?: string;
}

/* --------------------------------------------------------------- Connector */

/**
 * The line between two nodes.
 *
 * It fills as the node AFTER it starts working, so the connector reads as flow
 * rather than as decoration — you can see where the work currently is without
 * reading a single label.
 *
 * `self-center` is load-bearing: an explicit height inside an items-stretch row
 * cannot stretch, so without it the arrows sit at the top edge of the row and
 * the whole board stops reading as one line.
 */
export const Connector: React.FC<{
  active?: boolean;
  done?: boolean;
  arrow?: React.ReactNode;
  /** Below this width the board stacks and connectors are hidden. */
  breakpoint?: string;
}> = ({ active, done, arrow, breakpoint = 'lg' }) => (
  <div
    className={cn(
      'relative hidden h-[1px] w-full min-w-[14px] flex-1 items-center self-center',
      breakpoint === 'lg' ? 'lg:flex' : 'md:flex',
    )}
    aria-hidden
  >
    <span className="absolute inset-0 bg-[var(--su-border)]" />
    <span
      className={cn(
        'absolute inset-y-0 left-0 transition-all duration-[var(--su-slow)]',
        done ? 'w-full bg-[var(--su-ok)]' : active ? 'w-full bg-[var(--su-busy)]' : 'w-0',
      )}
    />
    <span
      className={cn(
        'absolute -right-[3px] transition-colors',
        done ? 'text-[var(--su-ok)]' : active ? 'text-[var(--su-busy)]' : 'text-[var(--su-border-strong)]',
      )}
    >
      {arrow ?? <Chevron />}
    </span>
  </div>
);

const Chevron: React.FC = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"
       strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="m9 18 6-6-6-6" />
  </svg>
);

/* ---------------------------------------------------------------- FlowNode */

export const FlowNode: React.FC<{
  node: FlowNodeData;
  index: number;
  /** Edits and retries are offered only once the run has come to rest — a
   *  control that fights a running job is worse than no control. */
  settled?: boolean;
  /** Give this to make the node's text editable; you receive the new value. */
  onEdit?: (text: string) => void;
  onRetry?: () => void;
  onZoomImage?: (url: string) => void;
  /** Copy for the editor. Name the ACTION, not "Save" — the user is starting
   *  work, not filing something. */
  editAction?: string;
  editHint?: string;
  icons?: Partial<Record<'busy' | 'ok' | 'warn' | 'danger' | 'edit' | 'retry' | 'close', React.ReactNode>>;
  /** Anything extra under the body — a button that opens the result. */
  footer?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
}> = ({
  node, index, settled = true, onEdit, onRetry, onZoomImage,
  editAction = 'Run with this', editHint, icons, footer, children, className,
}) => {
  const [draft, setDraft] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);
  const busy = node.status === 'busy';
  const editing = draft !== null;

  const commit = () => {
    const next = (draft ?? '').trim();
    setDraft(null);
    if (next && onEdit) onEdit(next);
  };

  return (
    <GlassPanel
      surface={busy ? 2 : node.status === 'idle' ? 1 : 1}
      dashed={node.status === 'idle'}
      className={cn(
        'flex min-h-[236px] w-full flex-col p-3 transition-all duration-[var(--su-base)]',
        busy && 'border-[var(--su-busy)]',
        node.status === 'danger' && 'border-[var(--su-danger)]',
        className,
      )}
    >
      {/* header ------------------------------------------------------- */}
      <div className="flex items-start gap-2">
        <StepMarker index={index + 1} status={node.status} icons={icons} />
        <div className="min-w-0 flex-1">
          <p className={cn(
            'truncate text-[12px] font-semibold leading-tight',
            busy ? 'text-[var(--su-text)]' : 'text-[var(--su-text-dim)]',
          )}>
            {node.label}
          </p>
          {node.meta && (
            <p className="mt-0.5 truncate font-mono text-[9px] text-[var(--su-text-ghost)]">{node.meta}</p>
          )}
        </div>
        <div className="flex shrink-0 items-center gap-0.5">
          {onEdit && settled && !editing && (
            <IconButton size={22} title={editHint} onClick={() => setDraft(node.text ?? '')}>
              {icons?.edit ?? <PencilGlyph />}
            </IconButton>
          )}
          {onRetry && settled && !editing && (
            <IconButton size={22} title="Re-run from this stage — everything before it is kept" onClick={onRetry}>
              {icons?.retry ?? <RetryGlyph />}
            </IconButton>
          )}
          {editing && (
            <IconButton size={22} title="Discard the edit" onClick={() => setDraft(null)}>
              {icons?.close ?? <CloseGlyph />}
            </IconButton>
          )}
        </div>
      </div>

      {/* body --------------------------------------------------------- */}
      <div className="mt-2.5 min-h-0 flex-1">
        {editing ? (
          <div className="flex h-full flex-col">
            <TextArea
              autoFocus
              value={draft}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Escape') setDraft(null);
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) commit();
              }}
              className="min-h-[124px] flex-1"
            />
            <PillButton
              variant="accent" size="sm" className="mt-2 w-full"
              disabled={!draft.trim()}
              onClick={commit}
            >
              {editAction}
            </PillButton>
            <p className="mt-1 text-center text-[9px] text-[var(--su-text-ghost)]">
              ⌘↵ to run · esc to discard
            </p>
          </div>
        ) : children ? (
          children
        ) : node.status === 'danger' && node.error ? (
          <p className="rounded-[var(--su-radius-sm)] bg-[var(--su-danger-soft)] p-2 text-[10px] leading-relaxed text-[var(--su-danger)]">
            {node.error}
          </p>
        ) : node.imageUrl ? (
          <button
            type="button"
            onClick={() => onZoomImage?.(node.imageUrl!)}
            className="group relative block h-[124px] w-full overflow-hidden rounded-[var(--su-radius-sm)] border border-[var(--su-border)] bg-[var(--su-surface-sunk)]"
          >
            <img
              src={node.imageUrl} alt={node.label} loading="lazy" decoding="async"
              className="h-full w-full object-contain"
            />
            {onZoomImage && (
              <span className="absolute inset-0 grid place-items-center bg-black/45 text-[10px] text-white opacity-0 transition-opacity group-hover:opacity-100">
                expand
              </span>
            )}
          </button>
        ) : node.text ? (
          <div className="rounded-[var(--su-radius-sm)] bg-[var(--su-surface-1)] p-2">
            {node.note && (
              <p className="mb-1.5 text-[10px] leading-relaxed text-[var(--su-accent)]">{node.note}</p>
            )}
            <p
              className="text-[10px] leading-relaxed text-[var(--su-text-faint)]"
              style={expanded ? undefined : {
                display: '-webkit-box', WebkitLineClamp: 4, WebkitBoxOrient: 'vertical', overflow: 'hidden',
              }}
            >
              {node.text}
            </p>
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              className="mt-1 text-[9px] text-[var(--su-text-ghost)] transition-colors hover:text-[var(--su-text)]"
            >
              {expanded ? 'less' : 'show all'}
            </button>
          </div>
        ) : busy ? (
          <div className="grid h-[124px] place-items-center rounded-[var(--su-radius-sm)] border border-[var(--su-border)] bg-[var(--su-surface-sunk)]">
            <div className="w-full px-4 text-center">
              <div className="h-[3px] w-full overflow-hidden rounded-[var(--su-radius-pill)] bg-[var(--su-surface-3)]">
                <div
                  className="h-full rounded-[var(--su-radius-pill)] bg-[var(--su-busy)] transition-[width] duration-500"
                  style={{ width: `${node.progress ?? 3}%` }}
                />
              </div>
              {node.message && (
                <p className="mt-1.5 truncate font-mono text-[9px] text-[var(--su-text-faint)]">{node.message}</p>
              )}
            </div>
          </div>
        ) : (
          <div className="grid h-[124px] place-items-center rounded-[var(--su-radius-sm)] border border-dashed border-[var(--su-border)]">
            <span className="text-[10px] text-[var(--su-text-ghost)]">waiting</span>
          </div>
        )}
      </div>

      {footer && !editing && <div className="mt-2.5">{footer}</div>}
    </GlassPanel>
  );
};

/* --------------------------------------------------------------- FlowBoard */

/**
 * Lays nodes in a row with connectors between them, and stacks on narrow
 * screens where a four-across row would be four unreadable columns.
 *
 * `renderNode` rather than baked-in FlowNode: a board is a layout, and the
 * moment one stage needs something the others do not, a fixed renderer becomes
 * a fork of the whole component.
 */
export function FlowBoard<T extends { id: string; status: Status }>({
  nodes, renderNode, title, subtitle, status, actions, error, className,
}: {
  nodes: T[];
  renderNode: (node: T, index: number) => React.ReactNode;
  title?: React.ReactNode;
  subtitle?: React.ReactNode;
  status?: { status: Status; label: string };
  actions?: React.ReactNode;
  error?: React.ReactNode;
  className?: string;
}) {
  const col = `lg:w-[calc(${(100 / Math.max(1, nodes.length)).toFixed(4)}%-14px)]`;
  return (
    <section className={cn('su-rise w-full', className)}>
      {(title || status || actions) && (
        <header className="mb-4 flex items-end justify-between gap-4">
          <div className="min-w-0">
            {(subtitle || status) && (
              <p className="flex items-center gap-2 text-[11px] uppercase tracking-[0.16em] text-[var(--su-text-faint)]">
                {subtitle}
                {status && <StatusChip status={status.status}>{status.label}</StatusChip>}
              </p>
            )}
            {title && (
              <h2 className="mt-1 truncate text-[22px] font-semibold text-[var(--su-text)]">{title}</h2>
            )}
          </div>
          {actions && <div className="flex shrink-0 items-center gap-1.5">{actions}</div>}
        </header>
      )}

      <div className="flex flex-col gap-3 lg:flex-row lg:items-stretch lg:gap-0">
        {nodes.map((node, i) => (
          <React.Fragment key={node.id}>
            <div className={cn('w-full', col)}>{renderNode(node, i)}</div>
            {i < nodes.length - 1 && (
              <Connector
                active={nodes[i + 1].status === 'busy'}
                done={nodes[i + 1].status === 'ok'}
              />
            )}
          </React.Fragment>
        ))}
      </div>

      {error && (
        <p className="mt-3 rounded-[var(--su-radius-sm)] border border-[var(--su-danger)] bg-[var(--su-danger-soft)] px-3 py-2 text-[11px] leading-relaxed text-[var(--su-danger)]">
          {error}
        </p>
      )}
    </section>
  );
}

/* --- fallback glyphs, so the kit renders with no icon library installed --- */
const PencilGlyph = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
       strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
  </svg>
);
const RetryGlyph = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
       strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M21 12a9 9 0 1 1-3-6.7L21 8" /><path d="M21 3v5h-5" />
  </svg>
);
const CloseGlyph = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
       strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M18 6 6 18M6 6l12 12" />
  </svg>
);
