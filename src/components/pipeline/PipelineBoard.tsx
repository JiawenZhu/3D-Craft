import React, { useMemo, useState } from 'react';
import { ChevronRight, Clock, Trash2, X } from 'lucide-react';
import { cn } from '../../lib/cn';
import { directPipelineRecon, imageSrc, selectPipelineConcept } from '../../lib/api';
import { useStudio } from '../../store/StudioContext';
import { NodeCard } from './NodeCard';
import type { PipelineStage } from '../../types';

/**
 * The run, drawn as the four steps it actually is.
 *
 *   your image  ─►  Gemini writes  ─►  concept render  ─►  3D
 *
 * A single progress bar would have said "generating" for two minutes across
 * three different models. Splitting it lets the user see which stage is slow,
 * read the prompt that was written on their behalf before it is rendered, and
 * re-run one stage without paying for the others.
 */

/** The line between two nodes; it fills while the node after it is working. */
const Connector: React.FC<{ active: boolean; done: boolean }> = ({ active, done }) => (
  <div className="hidden items-center justify-center lg:flex lg:w-[14px]">
    <div
      className={cn(
        'h-[2px] w-full transition-colors duration-500',
        done ? 'bg-emerald-400/40' : active ? 'bg-lilac animate-pulse' : 'bg-white/[0.06]',
      )}
    />
  </div>
);

export const PipelineBoard: React.FC = () => {
  const { pipeline, pipelineRuns, openRun, closeRun, retryStage, openAsset, assets, deleteRun } = useStudio();
  const [zoom, setZoom] = useState<{ url: string; caption: string } | null>(null);

  const asset3d = useMemo(() => {
    if (!pipeline?.assetId) return null;
    return assets.find((a) => a.id === pipeline.assetId) ?? null;
  }, [pipeline?.assetId, assets]);

  if (!pipeline) return null;

  const settled = pipeline.status !== 'running';

  return (
    <section className="relative z-10 mx-auto mt-14 w-full max-w-[1180px] animate-riseIn px-6 sm:px-[76px]">
      {pipeline && (
        <>
          {/* header ---------------------------------------------------- */}
          <div className="mb-4 flex items-end justify-between gap-4">
            <div className="min-w-0">
              <p className="flex items-center gap-2 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">
                Concept run
                <span
                  className={cn(
                    'rounded-full px-2 py-[1px] text-[9px] font-semibold tracking-normal',
                    pipeline.status === 'running' ? 'bg-lilac/15 text-lilac'
                      : pipeline.status === 'done' ? 'bg-emerald-400/15 text-emerald-300'
                        : 'bg-red-500/15 text-red-300',
                  )}
                >
                  {pipeline.status}
                </span>
              </p>
              <h2 className="mt-1 truncate text-[22px] font-semibold text-white">{pipeline.title}</h2>
            </div>
            <div className="flex shrink-0 items-center gap-1.5">
              <button
                onClick={() => deleteRun(pipeline.id)}
                title="Delete this run"
                className="grid h-8 w-8 place-items-center rounded-full border border-white/10 bg-white/[0.03] text-chalk-ghost transition-colors hover:border-red-500/40 hover:text-red-300"
              >
                <Trash2 className="h-[14px] w-[14px]" />
              </button>
              <button
                onClick={closeRun}
                title="Close the board"
                className="grid h-8 w-8 place-items-center rounded-full border border-white/10 bg-white/[0.03] text-chalk-dim transition-colors hover:border-white/25 hover:text-white"
              >
                <X className="h-[14px] w-[14px]" />
              </button>
            </div>
          </div>

          {/* the graph ------------------------------------------------- */}
          <div className="flex flex-col gap-3 lg:flex-row lg:items-stretch lg:gap-0">
            {pipeline.nodes.map((node, i) => (
              <React.Fragment key={node.id}>
                <div className="w-full lg:w-[calc(25%-14px)]">
                  <NodeCard
                    node={node}
                    index={i}
                    canRetry={settled}
                    onRetry={(stage: PipelineStage, prompt?: string) => retryStage(stage, prompt)}
                    onZoom={(url, caption) => setZoom({ url, caption })}
                    onOpen3D={asset3d ? () => openAsset(asset3d) : undefined}
                    onSelectConcept={(url) => {
                      selectPipelineConcept(pipeline.id, url)
                        .then(() => openRun(pipeline.id))
                        .catch(() => {});
                    }}
                    onDirectRecon={
                      node.kind === 'source'
                        ? () => {
                            directPipelineRecon(pipeline.id)
                              .then(() => openRun(pipeline.id))
                              .catch(() => {});
                          }
                        : undefined
                    }
                  />
                </div>
                {i < pipeline.nodes.length - 1 && (
                  <Connector
                    active={pipeline.nodes[i + 1].status === 'running'}
                    done={pipeline.nodes[i + 1].status === 'done'}
                  />
                )}
              </React.Fragment>
            ))}
          </div>

          {pipeline.status === 'failed' && pipeline.error && (
            <p className="mt-3 rounded-xl border border-red-500/25 bg-red-500/[0.07] px-3 py-2 text-[11px] leading-relaxed text-red-300">
              {pipeline.error}
              <span className="ml-1 text-red-300/60">
                Use the ↻ on the stage that failed — the stages before it are kept.
              </span>
            </p>
          )}
        </>
      )}

      {/* history --------------------------------------------------------- */}
      {pipelineRuns.length > 0 && (
        <div className={cn(pipeline ? 'mt-8' : '')}>
          <p className="mb-2.5 flex items-center gap-1.5 text-[11px] uppercase tracking-[0.16em] text-chalk-faint">
            <Clock className="h-3 w-3" /> Recent runs
          </p>
          <div className="flex gap-2 overflow-x-auto pb-2 rd-scroll">
            {pipelineRuns.map((r) => {
              const thumb = imageSrc(r.conceptUrl ?? r.sourceUrl);
              return (
                <button
                  key={r.id}
                  onClick={() => openRun(r.id)}
                  title={`${r.title} · ${r.status}`}
                  className={cn(
                    'group relative h-[64px] w-[64px] shrink-0 overflow-hidden rounded-[14px] border transition-all',
                    pipeline?.id === r.id
                      ? 'border-white/50'
                      : 'border-white/[0.08] hover:border-white/30',
                  )}
                >
                  {thumb
                    ? <img src={thumb} alt={r.title} loading="lazy" decoding="async" className="h-full w-full object-cover" />
                    : <span className="grid h-full w-full place-items-center bg-white/[0.03] text-[9px] text-chalk-ghost">run</span>}
                  <span
                    className={cn(
                      'absolute bottom-1 right-1 h-1.5 w-1.5 rounded-full',
                      r.status === 'running' ? 'animate-pulse bg-lilac'
                        : r.status === 'done' ? 'bg-emerald-400' : 'bg-red-400',
                    )}
                  />
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* lightbox -------------------------------------------------------- */}
      {zoom && (
        <div
          onClick={() => setZoom(null)}
          className="fixed inset-0 z-[200] grid place-items-center bg-ink/90 p-8 backdrop-blur-xl"
        >
          <figure className="max-h-full max-w-[760px]" onClick={(e) => e.stopPropagation()}>
            <img src={zoom.url} alt={zoom.caption} className="max-h-[78vh] w-auto rounded-[20px] border border-white/10" />
            <figcaption className="mt-3 flex items-center justify-between text-[11px] text-chalk-dim">
              <span>{zoom.caption}</span>
              <button onClick={() => setZoom(null)} className="text-chalk-faint transition-colors hover:text-white">
                close
              </button>
            </figcaption>
          </figure>
        </div>
      )}
    </section>
  );
};
