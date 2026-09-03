# Recipes

Four screens the kit composes into. Each is the shape of a real page, not a
storybook entry — copy one and replace the data.

---

## 1. Pipeline board

A multi-stage job, drawn as its stages. The core screen for anything that runs
several models in sequence.

```tsx
import { FlowBoard, FlowNode, IconButton, PillButton, Lightbox } from '@/studio-ui';

const toStatus = (s: string) =>
  s === 'running' ? 'busy' : s === 'done' ? 'ok' : s === 'failed' ? 'danger' : 'idle';

export function RunBoard({ run, onRetry, onEdit, onOpenResult, onClose }) {
  const [zoom, setZoom] = useState<string | null>(null);
  const settled = run.status !== 'running';

  return (
    <>
      <FlowBoard
        nodes={run.nodes.map((n) => ({ ...n, status: toStatus(n.status) }))}
        subtitle="Concept run"
        title={run.title}
        status={{ status: toStatus(run.status), label: run.status }}
        actions={<IconButton tone="danger" onClick={onClose}><X /></IconButton>}
        error={run.status === 'failed' && run.error}
        renderNode={(node, i) => (
          <FlowNode
            node={node}
            index={i}
            settled={settled}
            onZoomImage={setZoom}
            // Only stages that CAN be re-entered get a retry.
            onRetry={i > 0 ? () => onRetry(node.kind) : undefined}
            // Editing the user's words re-runs the interpreter; editing a
            // generated value skips it. Different entry points, deliberately.
            onEdit={
              node.kind === 'source' ? (t) => onEdit('interpret', t)
              : node.kind === 'prompt' ? (t) => onEdit('render', t)
              : undefined
            }
            editAction={node.kind === 'source' ? 'Rewrite & re-run' : 'Use this exactly'}
            icons={{ busy: <Loader2 className="su-spin h-3 w-3" />, ok: <Check className="h-3 w-3" /> }}
            footer={
              node.kind === 'result' && node.status === 'ok' && (
                <PillButton variant="solid" size="sm" className="w-full" onClick={onOpenResult}>
                  Open result
                </PillButton>
              )
            }
          />
        )}
      />
      {zoom && <Lightbox src={zoom} onClose={() => setZoom(null)} />}
    </>
  );
}
```

**The thing to get right is not the layout.** It is that each stage's retry
re-enters the pipeline at its own point, keeping everything upstream. A board
whose every button restarts from the top is a nicer-looking progress bar.

---

## 2. Gallery shelf

Two tabs over one grid. The pattern for "everyone's work" beside "my work".

```tsx
import { ShelfTabs, SearchField, CardGrid, MediaCard, EmptyState } from '@/studio-ui';

export function Shelf({ mine, everyones, tab, setTab, onOpen, onLike }) {
  const [q, setQ] = useState('');
  const items = (tab === 'mine' ? mine : everyones)
    .filter((a) => !q || `${a.name} ${a.author}`.toLowerCase().includes(q.toLowerCase()));

  return (
    <section className="mx-auto w-full max-w-[1500px] px-6 pb-28 pt-20">
      <div className="mb-6 flex items-end justify-between gap-4">
        <ShelfTabs
          tabs={[
            { value: 'mine', label: 'Asset', count: mine.length },
            { value: 'all', label: 'Explore', count: everyones.length },
          ]}
          value={tab}
          onChange={setTab}
        />
        <SearchField value={q} onChange={setQ} placeholder="Search assets…" />
      </div>

      {items.length === 0 ? (
        <EmptyState
          title={tab === 'mine' ? 'Nothing generated yet.' : 'Nothing to explore yet.'}
          hint="Pick a starting point from Explore, or drop your own image above."
        />
      ) : (
        <CardGrid>
          {items.map((a) => (
            <MediaCard
              key={a.id}
              title={a.name}
              src={a.thumbUrl}
              onOpen={() => onOpen(a)}
              toggle={{ active: a.liked, onToggle: () => onLike(a.id), icon: <Heart />, label: 'Like' }}
              badges={[
                a.versions > 1 && { label: a.versions, icon: <Layers />, title: `${a.versions} versions` },
                a.private && { label: 'private', icon: <Lock /> },
              ].filter(Boolean)}
              hint={a.model ? 'Click to view in 3D' : 'Click to load as reference'}
              meta={<>{a.author} · {compact(a.faces)} faces</>}
            />
          ))}
        </CardGrid>
      )}
    </section>
  );
}
```

**Two tabs showing the same items under different rules need an explanation on
the card.** If "Explore" collapses duplicates and "Asset" does not, the counts
will differ and a user with no `versions` badge to look at will read that as a
bug.

---

## 3. Generator panel

Image in, words beside it, one action out.

```tsx
import { DropZone, Field, Segmented, PillButton, Notice, ProgressRing } from '@/studio-ui';

export function Generator({ image, setImage, prompt, setPrompt, route, setRoute, run, job, notice }) {
  const busy = job && job.status === 'busy';

  return (
    <div className="flex flex-col items-center gap-4">
      <DropZone
        onFiles={([f]) => setImage(f)}
        label="Image to 3D"
        hint={<>Supports <span className="text-[var(--su-text-faint)]">.png .jpg .webp</span></>}
        className="h-[180px] w-[180px]"
      >
        {image && (
          <img src={URL.createObjectURL(image)} alt=""
               className="h-full w-full rounded-[var(--su-radius-sm)] object-cover" />
        )}
      </DropZone>

      <PillButton
        variant="ghost" size="lg" className="w-[191px]"
        onClick={run}
        disabled={busy || (!image && !prompt.trim())}
        progress={busy ? job.progress : undefined}
        hoverLabel={`$${cost.toFixed(2)}`}
        busy={busy && <><ProgressRing value={job.progress} /> {Math.round(job.progress)}%</>}
      >
        GENERATE
      </PillButton>

      <Segmented
        value={route}
        onChange={setRoute}
        options={[
          { value: 'concept', label: 'Concept → 3D', icon: <Sparkles className="h-3 w-3" />,
            hint: 'Re-render the image cleanly first' },
          { value: 'direct', label: 'Direct → 3D', icon: <Zap className="h-3 w-3" />,
            hint: 'Send the image straight to the reconstructor' },
        ]}
      />

      {/* The prompt lives here, not in the drop zone: that card shows the image
          OR a textarea, never both, and this workflow is image AND words. */}
      <Field
        value={prompt}
        onChange={(e) => setPrompt(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && !e.shiftKey && run()}
        placeholder={image ? 'Say what to change…' : 'Describe the asset…'}
        action={<IconButton size={26} onClick={run}><CornerDownLeft className="h-3.5 w-3.5" /></IconButton>}
        wrapperClassName="w-full max-w-[520px]"
      />

      {notice && <Notice tone="warn" onDismiss={notice.dismiss}>{notice.text}</Notice>}
    </div>
  );
}
```

---

## 4. Viewer stage

A canvas with chrome around it. The pattern for anything with a heavy runtime —
3D, video, a big editor.

```tsx
import { StageOverlay, StageHeader, Toolbar, InfoPanel, PillButton } from '@/studio-ui';

export function Viewer({ asset, onBack, stats }) {
  const [showInfo, setShowInfo] = useState(true);

  return (
    <StageOverlay>
      <StageHeader
        onBack={onBack}
        title={asset.name}
        subtitle={`${asset.engine} · ${compact(stats.triangles)} tris`}
        actions={<PillButton variant="accent" size="sm" icon={<Download />}>Export</PillButton>}
      />

      <div className="relative flex-1">
        <Canvas />{/* the product */}

        <Toolbar
          className="absolute right-4 top-1/2 -translate-y-1/2"
          side="right"
          items={[
            { id: 'in',    icon: <ZoomIn />,  label: 'Zoom in',  onClick: zoomIn },
            { id: 'out',   icon: <ZoomOut />, label: 'Zoom out', onClick: zoomOut },
            { id: 'fit',   icon: <Expand />,  label: 'Fit to view', onClick: fit, separated: true },
            { id: 'grid',  icon: <Grid3x3 />, label: 'Grid', active: grid, onClick: () => setGrid(!grid) },
            { id: 'info',  icon: <Info />,    label: 'Model info', active: showInfo,
              onClick: () => setShowInfo((v) => !v) },
          ]}
        />

        {showInfo && (
          <InfoPanel
            className="absolute left-4 top-4 w-[208px]"
            title="Model info"
            rows={[
              { label: 'Triangles', value: stats.triangles.toLocaleString() },
              { label: 'Meshes',    value: stats.meshes },
              { label: 'Size',      value: `${stats.sizeMb.toFixed(2)} MB` },
            ]}
          />
        )}
      </div>
    </StageOverlay>
  );
}
```

**`StageOverlay`, not a modal.** Render this *instead of* the gallery, not on
top of it. A viewer layered over a still-mounted grid keeps forty thumbnails
decoded and any canvases behind it running — on a laptop that is the difference
between a viewer that spins smoothly and one that stutters.

**Fill `InfoPanel` from data you already have.** Counting geometry on the client
leaves the panel empty until the model loads, and empty-then-populated reads as
broken. Measure it server-side when the asset is produced and send the numbers
with it.
