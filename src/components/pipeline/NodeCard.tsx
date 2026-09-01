import React, { useState } from 'react';
import {
  AlertTriangle, Box, Check, ChevronDown, Loader2, Maximize2, RefreshCw, Rotate3d,
} from 'lucide-react';
import { cn } from '../../lib/cn';
import { imageSrc } from '../../lib/api';
import type { PipelineNode, PipelineStage } from '../../types';

const STATUS_RING: Record<PipelineNode['status'], string> = {
  pending: 'border-white/12 text-chalk-ghost',
  running: 'border-lilac/70 text-lilac',
  done: 'border-emerald-400/50 text-emerald-300',
  failed: 'border-red-500/50 text-red-300',
};

/** Small round step marker: number, spinner, tick or warning. */
const Marker: React.FC<{ index: number; status: PipelineNode['status'] }> = ({ index, status }) => (
  <span
    className={cn(
      'grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full border text-[10px] font-semibold',
      STATUS_RING[status],
    )}
  >
    {status === 'running' ? <Loader2 className="h-3 w-3 animate-spin" />
      : status === 'done' ? <Check className="h-3 w-3" strokeWidth={3} />
        : status === 'failed' ? <AlertTriangle className="h-3 w-3" />
          : index + 1}
  </span>
);

const secs = (ms?: number) => (ms == null ? null : ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`);

export const NodeCard: React.FC<{
  node: PipelineNode;
  index: number;
  /** Retry is only offered once the run has come to rest. */
  canRetry: boolean;
  onRetry: (stage: PipelineStage) => void;
  onZoom: (url: string, caption: string) => void;
  /** Set when the finished mesh is loaded and the workbench can open it. */
  onOpen3D?: () => void;
}> = ({ node, index, canRetry, onRetry, onZoom, onOpen3D }) => {
  const [expanded, setExpanded] = useState(false);
  const busy = node.status === 'running';
  const image = imageSrc(node.imageUrl);

  return (
    <div
      className={cn(
        'relative flex min-h-[236px] w-full flex-col rounded-[20px] border p-3 transition-all duration-300',
        busy ? 'border-lilac/35 bg-lilac/[0.04]'
          : node.status === 'failed' ? 'border-red-500/25 bg-red-500/[0.04]'
            : node.status === 'done' ? 'border-white/[0.08] bg-white/[0.03]'
              : 'border-dashed border-white/[0.07] bg-white/[0.015]',
      )}
      style={{ backdropFilter: 'blur(16px)' }}
    >
      {/* header --------------------------------------------------------- */}
      <div className="flex items-start gap-2">
        <Marker index={index} status={node.status} />
        <div className="min-w-0 flex-1">
          <p className={cn('truncate text-[12px] font-semibold leading-tight', busy ? 'text-white' : 'text-chalk')}>
            {node.label}
          </p>
          <p className="mt-0.5 truncate font-mono text-[9px] text-chalk-ghost">
            {node.model ?? node.provider ?? node.kind}
            {node.ms != null && ` · ${secs(node.ms)}`}
          </p>
        </div>
        {canRetry && node.kind !== 'source' && (
          <button
            onClick={() => onRetry(node.kind)}
            title={`Re-run from “${node.label}” — everything before it is kept`}
            className="grid h-[22px] w-[22px] shrink-0 place-items-center rounded-full text-chalk-ghost transition-colors hover:bg-white/10 hover:text-white"
          >
            <RefreshCw className="h-3 w-3" />
          </button>
        )}
      </div>

      {/* body ----------------------------------------------------------- */}
      <div className="mt-2.5 min-h-0 flex-1">
        {node.status === 'failed' ? (
          <p className="rounded-lg bg-red-500/10 p-2 text-[10px] leading-relaxed text-red-300">
            {node.error ?? 'This stage failed.'}
          </p>
        ) : image ? (
          <button
            onClick={() => onZoom(image, node.label)}
            className="group relative block h-[124px] w-full overflow-hidden rounded-[12px] border border-white/[0.06] bg-black/25"
          >
            <img src={image} alt={node.label} loading="lazy" decoding="async" className="h-full w-full object-contain" />
            <span className="absolute inset-0 grid place-items-center bg-black/45 opacity-0 transition-opacity group-hover:opacity-100">
              <Maximize2 className="h-4 w-4 text-white" />
            </span>
          </button>
        ) : node.kind === 'prompt' && node.text ? (
          <div className="rounded-[12px] bg-white/[0.03] p-2">
            {node.notes && <p className="mb-1.5 text-[10px] leading-relaxed text-lilac">{node.notes}</p>}
            <p className={cn('text-[10px] leading-relaxed text-chalk-dim', !expanded && 'line-clamp-4')}>
              {node.text}
            </p>
            <button
              onClick={() => setExpanded((v) => !v)}
              className="mt-1 flex items-center gap-0.5 text-[9px] text-chalk-faint transition-colors hover:text-white"
            >
              {expanded ? 'less' : 'full prompt'}
              <ChevronDown className={cn('h-2.5 w-2.5 transition-transform', expanded && 'rotate-180')} />
            </button>
          </div>
        ) : node.kind === 'model3d' ? (
          <div className="grid h-[124px] place-items-center rounded-[12px] border border-white/[0.05] bg-black/20">
            {busy ? (
              <div className="w-full px-4 text-center">
                <Box className="mx-auto mb-2 h-5 w-5 animate-pulse text-lilac" />
                <div className="h-[3px] w-full overflow-hidden rounded-full bg-white/10">
                  <div
                    className="h-full rounded-full bg-lilac transition-[width] duration-500"
                    style={{ width: `${node.progress ?? 3}%` }}
                  />
                </div>
                <p className="mt-1.5 truncate font-mono text-[9px] text-chalk-faint">{node.message ?? 'Queued'}</p>
              </div>
            ) : (
              <Box className="h-5 w-5 text-chalk-ghost" />
            )}
          </div>
        ) : (
          <div className="grid h-[124px] place-items-center rounded-[12px] border border-dashed border-white/[0.06]">
            <span className="text-[10px] text-chalk-ghost">{busy ? 'working…' : 'waiting'}</span>
          </div>
        )}

        {/* the user's own words, under their image */}
        {node.kind === 'source' && node.text && (
          <p className="mt-2 line-clamp-2 text-[10px] leading-relaxed text-chalk-dim">“{node.text}”</p>
        )}
      </div>

      {/* footer --------------------------------------------------------- */}
      {node.kind === 'model3d' && node.status === 'done' && (
        <button
          onClick={onOpen3D}
          disabled={!onOpen3D}
          className={cn(
            'mt-2.5 flex h-[30px] w-full items-center justify-center gap-1.5 rounded-full text-[11px] font-semibold transition-all',
            onOpen3D
              ? 'bg-white/90 text-ink hover:bg-white'
              : 'cursor-wait bg-white/10 text-chalk-faint',
          )}
        >
          <Rotate3d className="h-3.5 w-3.5" />
          {onOpen3D ? 'Open in 3D' : 'preparing…'}
          {node.faces ? <span className="font-mono text-[9px] opacity-60">{(node.faces / 1000).toFixed(0)}k</span> : null}
        </button>
      )}
    </div>
  );
};
