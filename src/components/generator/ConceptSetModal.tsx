import React, { useState } from 'react';
import { createPortal } from 'react-dom';
import { ArrowRight, Check, Layers, Loader2, Maximize2, RefreshCw, Sparkles, X } from 'lucide-react';
import { cn } from '../../lib/cn';
import { generateConceptSet, imageSrc } from '../../lib/api';
import { useStudio } from '../../store/StudioContext';
import type { ConceptImage, ConceptSetResult, RefImage } from '../../types';

interface ConceptSetModalProps {
  sourceImage: RefImage;
  isOpen: boolean;
  onClose: () => void;
  onApplyConcept: (concept: ConceptImage, fullPrompt: string) => Promise<void> | void;
  onApplyMultiView?: (concepts: ConceptImage[], fullPrompt: string) => Promise<void> | void;
}

export const ConceptSetModal: React.FC<ConceptSetModalProps> = ({
  sourceImage,
  isOpen,
  onClose,
  onApplyConcept,
  onApplyMultiView,
}) => {
  const { settings } = useStudio();
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [conceptSet, setConceptSet] = useState<ConceptSetResult | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [previewZoom, setPreviewZoom] = useState<string | null>(null);

  const fetchConceptSet = React.useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await generateConceptSet(
        sourceImage.file ?? null,
        sourceImage.sourceUrl ?? null,
        settings.prompt || '',
        4,
      );
      setConceptSet(res);
      if (res.images.length > 0) {
        setSelectedId(res.images[0].id);
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to generate concept set';
      setError(message);
    } finally {
      setLoading(false);
    }
  }, [sourceImage, settings.prompt]);

  React.useEffect(() => {
    if (isOpen && !conceptSet && !loading && !error) {
      void fetchConceptSet();
    }
  }, [isOpen, conceptSet, loading, error, fetchConceptSet]);

  if (!isOpen || typeof document === 'undefined') return null;

  const selectedConcept = conceptSet?.images.find((c) => c.id === selectedId) ?? conceptSet?.images[0];

  const views = (conceptSet?.images ?? []).filter((c) => !c.isOriginal && c.direction && c.direction !== 'unknown'
    && (!['hunyuan3d-2.1', 'hunyuan3d-2-white', 'hybrid'].includes(settings.engine) || c.direction !== 'right'));
  const canMultiView = conceptSet?.validation?.usable === true && views.length >= 2 && (!['hunyuan3d-2.1', 'hunyuan3d-2-white', 'hybrid'].includes(settings.engine)
    || ['front', 'back', 'left'].every((d) => views.some((c) => c.direction === d)));

  const modalContent = (
    <div className="fixed inset-0 z-[9999] flex items-center justify-center bg-black/80 p-4 backdrop-blur-xl animate-popIn">
      <div className="relative flex max-h-[90vh] w-full max-w-[840px] flex-col overflow-hidden rounded-[28px] border border-white/15 bg-ink-900/95 shadow-2xl">
        {/* Header */}
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-white/10 px-6">
          <div className="flex items-center gap-2.5">
            <span className="grid h-8 w-8 place-items-center rounded-xl bg-lilac/20 text-lilac">
              <Sparkles className="h-4 w-4" />
            </span>
            <div>
              <h3 className="text-[15px] font-bold text-white">Candidate Concept Set</h3>
              <p className="text-[11px] text-chalk-ghost">
                One shared subject, labelled camera views. Check pose and markings before using them together.
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => void fetchConceptSet()}
              disabled={loading}
              title="Generate new variations"
              className="flex items-center gap-1.5 rounded-full border border-white/10 bg-white/[0.04] px-3.5 py-1.5 text-[11px] font-medium text-chalk transition-colors hover:border-white/25 hover:text-white disabled:opacity-50"
            >
              <RefreshCw className={cn('h-3 w-3', loading && 'animate-spin')} />
              {loading ? 'Generating…' : 'Re-roll Set'}
            </button>
            <button
              onClick={onClose}
              className="grid h-8 w-8 place-items-center rounded-full text-chalk-ghost transition-colors hover:bg-white/10 hover:text-white"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="rd-scroll flex-1 overflow-y-auto p-6">
          {loading ? (
            <div className="flex min-h-[340px] flex-col items-center justify-center gap-4 text-center">
              <div className="relative grid h-16 w-16 place-items-center rounded-2xl border border-lilac/30 bg-lilac/10">
                <Loader2 className="h-8 w-8 animate-spin text-lilac" />
              </div>
              <div>
                <p className="text-[14px] font-semibold text-white">Rendering Concept Image Set…</p>
                <p className="mt-1 max-w-[420px] text-[12px] leading-relaxed text-chalk-dim">
                  Gemini is analyzing your photo and generating 4 clean 3D game asset views with isolated backgrounds and neutral lighting.
                </p>
              </div>
            </div>
          ) : error ? (
            <div className="flex min-h-[300px] flex-col items-center justify-center gap-3 text-center">
              <p className="text-[13px] font-medium text-red-300">{error}</p>
              <button
                onClick={() => void fetchConceptSet()}
                className="mt-2 rounded-full border border-white/20 bg-white/10 px-4 py-2 text-[12px] text-white hover:bg-white/20"
              >
                Try Again
              </button>
            </div>
          ) : conceptSet ? (
            <div className="space-y-6">
              {/* Core Concept Banner */}
              {conceptSet.core_concept && (
                <div className="flex items-start gap-2.5 rounded-2xl border border-amber-400/25 bg-amber-400/[0.08] p-3.5">
                  <span className="grid h-6 w-6 shrink-0 place-items-center rounded-lg bg-amber-400/20 text-amber-300">
                    <Sparkles className="h-3.5 w-3.5" />
                  </span>
                  <div>
                    <span className="text-[10px] font-bold uppercase tracking-wider text-amber-300">
                      Core Concept Detected
                    </span>
                    <p className="mt-0.5 text-[12px] font-semibold text-amber-100">
                      {conceptSet.core_concept}
                    </p>
                    {conceptSet.image_assessment && (
                      <p className="mt-1 text-[10px] italic text-amber-200/70">
                        {conceptSet.image_assessment}
                      </p>
                    )}
                  </div>
                </div>
              )}

              {conceptSet.warnings?.map((warning) => (
                <p key={warning} className="text-[12px] text-amber-200">{warning}</p>
              ))}
              {conceptSet.validation && !conceptSet.validation.usable && (
                <p className="rounded-xl bg-amber-400/10 p-3 text-[12px] text-amber-200">
                  These views did not pass the consistency check. Use the original or one selected view.
                </p>
              )}
              <p className="text-[12px] text-chalk-dim">
                Use a single view if the generated sides change the face, pose, markings or accessories.
                The original photo is available separately and is excluded from the turnaround set.
              </p>
              {/* Concept Variations Grid */}
              <div>
                <div className="mb-3 flex items-center justify-between">
                  <span className="text-[11px] font-semibold uppercase tracking-wider text-chalk-faint">
                    Select View / Angle ({conceptSet.images.length} Options)
                  </span>
                  {conceptSet.notes && (
                    <span className="text-[11px] text-lilac">{conceptSet.notes}</span>
                  )}
                </div>

                <div className="grid grid-cols-2 gap-3.5 sm:grid-cols-5">
                  {conceptSet.images.map((img) => {
                    const isSelected = img.id === selectedId;
                    const fullSrc = imageSrc(img.url);
                    return (
                      <div
                        key={img.id}
                        onClick={() => setSelectedId(img.id)}
                        className={cn(
                          'group relative aspect-square cursor-pointer overflow-hidden rounded-2xl border bg-black/40 p-1.5 transition-all duration-300',
                          isSelected
                            ? 'border-lilac shadow-[0_0_24px_rgba(216,161,241,0.25)] ring-2 ring-lilac'
                            : 'border-white/10 hover:border-white/30',
                        )}
                      >
                        <div className="relative h-full w-full overflow-hidden rounded-xl">
                          <img
                            src={fullSrc}
                            alt={img.label}
                            className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
                          />
                          <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-80" />
                          <span className="absolute bottom-2 left-2 right-2 truncate text-[10px] font-semibold text-white">
                            {img.label}
                          </span>
                          {img.isOriginal && (
                            <span className="absolute left-2 top-2 rounded bg-amber-400/90 px-1.5 py-0.5 text-[8px] font-extrabold uppercase tracking-tight text-ink shadow">
                              Original
                            </span>
                          )}
                          {isSelected && (
                            <span className="absolute right-2 top-2 grid h-5 w-5 place-items-center rounded-full bg-lilac text-ink shadow-md">
                              <Check className="h-3 w-3" strokeWidth={3} />
                            </span>
                          )}
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              if (fullSrc) setPreviewZoom(fullSrc);
                            }}
                            title="Zoom"
                            className="absolute left-2 top-2 grid h-5 w-5 place-items-center rounded-full bg-black/60 text-white opacity-0 transition-opacity group-hover:opacity-100"
                          >
                            <Maximize2 className="h-2.5 w-2.5" />
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Selected Concept Details */}
              {selectedConcept && (
                <div className="rounded-2xl border border-white/10 bg-white/[0.03] p-4">
                  <div className="flex flex-col gap-4 sm:flex-row sm:items-center">
                    <div className="h-24 w-24 shrink-0 overflow-hidden rounded-xl border border-white/10 bg-black/30">
                      <img
                        src={imageSrc(selectedConcept.url)}
                        alt={selectedConcept.label}
                        className="h-full w-full object-cover"
                      />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-[13px] font-bold text-white">{conceptSet.title}</span>
                        <span className="rounded-full bg-white/10 px-2 py-0.5 text-[9px] font-semibold text-chalk-dim">
                          {selectedConcept.label}
                        </span>
                      </div>
                      <p className="mt-1 line-clamp-2 text-[11px] leading-relaxed text-chalk-dim">
                        {conceptSet.prompt}
                      </p>
                    </div>
                  </div>
                </div>
              )}
            </div>
          ) : null}
        </div>

        {/* Footer Actions */}
        <div className="flex items-center justify-between border-t border-white/10 bg-white/[0.02] px-6 py-4">
          <button
            type="button"
            disabled={submitting || !conceptSet?.images.some((c) => c.isOriginal)}
            onClick={async () => {
              const orig = conceptSet?.images.find((x) => x.isOriginal);
              if (submitting) return;
              setSubmitting(true);
              try {
                if (orig) {
                  await onApplyConcept(orig, conceptSet?.prompt ?? '');
                }
                onClose();
              } catch (err) {
                setError(err instanceof Error ? err.message : 'Could not apply original');
              } finally {
                setSubmitting(false);
              }
            }}
            className="rounded-full border border-white/10 px-4 py-2 text-[12px] font-medium text-chalk-dim transition-colors hover:border-white/25 hover:text-white cursor-pointer disabled:opacity-50"
          >
            Use Original Directly for 3D
          </button>

          <div className="flex items-center gap-2.5">
            {onApplyMultiView && canMultiView && (
              <button
                type="button"
                disabled={submitting}
                onClick={async () => {
                  if (submitting) return;
                  setSubmitting(true);
                  try {
                    await onApplyMultiView(views, conceptSet?.prompt ?? '');
                    onClose();
                  } catch (err) {
                    setError(err instanceof Error ? err.message : 'Could not apply views');
                  } finally {
                    setSubmitting(false);
                  }
                }}
                className="flex items-center gap-1.5 rounded-full border border-lilac/30 bg-lilac/10 px-4 py-2 text-[12px] font-semibold text-lilac transition-all hover:bg-lilac/20 cursor-pointer disabled:opacity-50"
              >
                <Layers className="h-3.5 w-3.5" />
                Use {views.length} Views for 3D
              </button>
            )}

            {selectedConcept && (
              <button
                type="button"
                disabled={submitting}
                onClick={async () => {
                  if (submitting) return;
                  setSubmitting(true);
                  try {
                    await onApplyConcept(selectedConcept, conceptSet?.prompt ?? '');
                    onClose();
                  } catch (err) {
                    setError(err instanceof Error ? err.message : 'Could not apply selected view');
                  } finally {
                    setSubmitting(false);
                  }
                }}
                className="flex items-center gap-2 rounded-full px-5 py-2.5 text-[12px] font-bold text-ink shadow-lift transition-all hover:brightness-110 active:scale-95 cursor-pointer disabled:opacity-60 disabled:cursor-not-allowed select-none"
                style={{ backgroundImage: 'var(--g-accent)' }}
              >
                {submitting ? (
                  <>
                    <Loader2 className="h-3.5 w-3.5 animate-spin text-ink" />
                    <span>Generating 3D…</span>
                  </>
                ) : (
                  <>
                    <span>Use Selected for 3D</span>
                    <ArrowRight className="h-3.5 w-3.5" />
                  </>
                )}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Fullscreen Zoom */}
      {previewZoom && (
        <div
          onClick={() => setPreviewZoom(null)}
          className="fixed inset-0 z-[10000] flex cursor-zoom-out items-center justify-center bg-black/90 p-8 backdrop-blur-2xl"
        >
          <img src={previewZoom} alt="Concept Zoom" className="max-h-[85vh] max-w-[85vw] rounded-2xl object-contain shadow-2xl" />
        </div>
      )}
    </div>
  );

  return createPortal(modalContent, document.body);
};
