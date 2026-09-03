import React, { useState } from 'react';
import {
  CardGrid, Connector, DropZone, EmptyState, Field, FlowBoard, FlowNode, GlassPanel,
  HistoryStrip, IconButton, InfoPanel, Lightbox, MediaCard, ModeRail, Notice, PillButton,
  Popover, ProgressRing, SearchField, Segmented, ShelfTabs, Slider, SliderStyles,
  StageHeader, StatusChip, StatusPill, StepMarker, TextArea, Toolbar, Tooltip,
  type FlowNodeData, type Status,
} from './components';

/* ===========================================================================
 * studio-ui — demo
 *
 * Every component on one page. This is not documentation; it is the test.
 *
 * Mount it after rebranding — override the accent variables, load this, and
 * look. A kit this size has too many states to check by reading, and the
 * failure mode of a token swap is never a crash: it is one panel that went
 * unreadable, which you only find by looking at all of them at once.
 *
 *   import { Demo } from './studio-ui/demo';
 *   createRoot(el).render(<Demo />);
 * ========================================================================= */

const Section: React.FC<{ title: string; note?: string; children: React.ReactNode }> = ({
  title, note, children,
}) => (
  <section className="mb-14">
    <h2 className="mb-1 text-[11px] uppercase tracking-[0.18em] text-[var(--su-text-faint)]">{title}</h2>
    {note && <p className="mb-4 max-w-[640px] text-[12px] leading-relaxed text-[var(--su-text-ghost)]">{note}</p>}
    <div className="flex flex-wrap items-start gap-4">{children}</div>
  </section>
);

const STATUSES: Status[] = ['idle', 'busy', 'ok', 'warn', 'danger'];

export const Demo: React.FC = () => {
  const [seg, setSeg] = useState('a');
  const [mode, setMode] = useState('image');
  const [tab, setTab] = useState('mine');
  const [q, setQ] = useState('');
  const [slider, setSlider] = useState(1.4);
  const [pop, setPop] = useState(false);
  const [zoom, setZoom] = useState<string | null>(null);
  const [prompt, setPrompt] = useState('');
  const [notice, setNotice] = useState<string | null>('A dismissible line of feedback.');
  const [nodes, setNodes] = useState<FlowNodeData[]>([
    { id: 'a', label: 'Your image', status: 'ok', meta: 'source', text: 'a small brass lantern' },
    { id: 'b', label: 'Model writes the prompt', status: 'ok', meta: 'flash · 7.2s',
      text: 'Stylised game-ready render of a small brass lantern, three-quarter front view, plain background, even light, no text.',
      note: 'Kept the shape, dropped the cluttered desk behind it.' },
    { id: 'c', label: 'Concept render', status: 'busy', meta: 'pro-image',
      progress: 62, message: 'rendering…' },
    { id: 'd', label: 'Reconstruction', status: 'idle', meta: 'queued' },
  ]);

  const advance = () => setNodes((ns) => ns.map((n): FlowNodeData =>
    (n.status === 'busy' ? { ...n, status: 'ok', progress: 100 } : n)));

  return (
    <div className="min-h-screen bg-[var(--su-bg)] px-10 py-12 text-[var(--su-text-dim)]">
      <SliderStyles />

      <header className="mb-12">
        <h1 className="text-[28px] font-semibold text-[var(--su-text)]">studio-ui</h1>
        <p className="mt-1 max-w-[620px] text-[13px] leading-relaxed text-[var(--su-text-faint)]">
          Every component, every state. Achromatic by default — override the accent
          variables and reload to see the whole kit take a brand.
        </p>
      </header>

      <Section title="Surfaces" note="Translucent whites over the ground, so one set of values works over any backdrop.">
        {([1, 2, 3, 'sunk'] as const).map((s) => (
          <GlassPanel key={String(s)} surface={s} className="grid h-24 w-40 place-items-center">
            <span className="font-mono text-[11px] text-[var(--su-text-faint)]">surface {s}</span>
          </GlassPanel>
        ))}
        <GlassPanel dashed className="grid h-24 w-40 place-items-center">
          <span className="font-mono text-[11px] text-[var(--su-text-ghost)]">dashed</span>
        </GlassPanel>
        <GlassPanel lifted radius="lg" className="grid h-24 w-40 place-items-center">
          <span className="font-mono text-[11px] text-[var(--su-text-faint)]">lifted</span>
        </GlassPanel>
      </Section>

      <Section title="Buttons">
        <PillButton variant="accent">Accent</PillButton>
        <PillButton variant="solid">Solid</PillButton>
        <PillButton variant="ghost">Ghost</PillButton>
        <PillButton variant="ghost" disabled>Disabled</PillButton>
        <PillButton variant="ghost" size="lg" className="w-[191px]" hoverLabel="$0.02">GENERATE</PillButton>
        <PillButton variant="ghost" size="lg" className="w-[191px]" progress={42}
                    busy={<><ProgressRing value={42} /> 42%</>}>GENERATE</PillButton>
        <div className="flex items-center gap-1">
          {[false, true].map((a) => (
            <Tooltip key={String(a)} label={a ? 'Active' : 'Resting'}>
              <IconButton active={a} aria-label="example"><Dot /></IconButton>
            </Tooltip>
          ))}
          <IconButton tone="danger" aria-label="delete"><Dot /></IconButton>
          <IconButton disabled aria-label="disabled"><Dot /></IconButton>
        </div>
      </Section>

      <Section title="Choice">
        <Segmented
          value={seg} onChange={setSeg}
          options={[
            { value: 'a', label: 'Concept → 3D', hint: 'The long way, and the better one' },
            { value: 'b', label: 'Direct → 3D' },
            { value: 'c', label: 'Off', disabled: true },
          ]}
        />
        <Segmented size="sm" value={seg} onChange={setSeg}
                   options={[{ value: 'a', label: 'Single' }, { value: 'b', label: 'Multi' }]} />
        <div className="relative">
          <PillButton variant="ghost" size="sm" onClick={() => setPop((v) => !v)}>Popover</PillButton>
          <Popover open={pop} onClose={() => setPop(false)} className="w-[260px]">
            <p className="mb-2 text-[11px] uppercase tracking-[0.16em] text-[var(--su-text-faint)]">Panel</p>
            <Slider label="Exposure" value={slider} onChange={setSlider} min={0} max={3}
                    format={(v) => `${v.toFixed(2)}×`} />
          </Popover>
        </div>
      </Section>

      <Section title="Status" note="Meaning stays separate from the brand accent — a red brand must not make every panel look like an error.">
        <div className="flex flex-wrap items-center gap-2">
          {STATUSES.map((s) => <StatusChip key={s} status={s}>{s}</StatusChip>)}
        </div>
        <div className="flex items-center gap-2">
          {STATUSES.map((s, i) => <StepMarker key={s} index={i + 1} status={s} />)}
        </div>
        <div className="flex items-center gap-2">
          {STATUSES.map((s) => <StatusPill key={s} status={s} label={s} />)}
        </div>
        <ProgressRing value={68} size={34} />
      </Section>

      <Section title="Notices">
        <div className="flex w-full max-w-[560px] flex-col gap-2">
          {STATUSES.map((s) => (
            <Notice key={s} tone={s} onDismiss={s === 'idle' ? () => {} : undefined}>
              tone <code>{s}</code> — {s === 'danger' ? 'announced as an alert' : 'announced as status'}
            </Notice>
          ))}
          {notice && <Notice tone="warn" onDismiss={() => setNotice(null)}>{notice}</Notice>}
        </div>
      </Section>

      <Section title="Inputs">
        <div className="flex w-full max-w-[520px] flex-col gap-3">
          <Field placeholder="Say what to change…" value={prompt}
                 onChange={(e) => setPrompt(e.target.value)}
                 action={<IconButton size={26} aria-label="run"><Dot /></IconButton>} />
          <TextArea rows={3} placeholder="A longer well…" />
          <Slider label="Directional" value={slider} onChange={setSlider} min={0} max={3}
                  format={(v) => `${v.toFixed(2)}×`} />
        </div>
        <DropZone onFiles={() => {}} label="Image to 3D" hint="Supports .png .jpg .webp"
                  className="h-[180px] w-[180px]" />
      </Section>

      <Section title="Flow" note="A long job drawn as the stages it actually is. The third node is working; the connector after it fills to show where the work is.">
        <div className="w-full">
          <FlowBoard
            nodes={nodes}
            subtitle="Concept run"
            title="Small Brass Lantern"
            status={{ status: 'busy', label: 'running' }}
            actions={<PillButton size="sm" variant="ghost" onClick={advance}>Advance</PillButton>}
            renderNode={(n, i) => (
              <FlowNode
                node={n} index={i}
                settled={n.status !== 'busy'}
                onEdit={n.text ? () => {} : undefined}
                onRetry={i > 0 ? () => {} : undefined}
                editAction={i === 0 ? 'Rewrite & re-run' : 'Use this exactly'}
                footer={i === 3 && n.status === 'ok' && (
                  <PillButton variant="solid" size="sm" className="w-full">Open result</PillButton>
                )}
              />
            )}
          />
        </div>
        <div className="flex w-full items-center gap-2">
          <span className="text-[11px] text-[var(--su-text-ghost)]">connector states:</span>
          <div className="flex h-6 w-24 items-center"><Connector /></div>
          <div className="flex h-6 w-24 items-center"><Connector active /></div>
          <div className="flex h-6 w-24 items-center"><Connector done /></div>
        </div>
      </Section>

      <Section title="Gallery">
        <div className="w-full">
          <div className="mb-5 flex items-end justify-between gap-4">
            <ShelfTabs
              tabs={[{ value: 'mine', label: 'Asset', count: 16 }, { value: 'all', label: 'Explore', count: 23 }]}
              value={tab} onChange={setTab}
            />
            <SearchField value={q} onChange={setQ} />
          </div>
          {tab === 'mine' ? (
            <CardGrid>
              {['Ember Golem', 'Forest Ranger', 'Retro Van', 'Ramen Shop'].map((t, i) => (
                <MediaCard
                  key={t}
                  title={t}
                  onOpen={() => {}}
                  fallback={<Placeholder seed={i} />}
                  toggle={{ active: i === 1, onToggle: () => {}, icon: <Dot />, label: 'Like' }}
                  badges={i === 0 ? [{ label: '3', title: '3 versions' }]
                    : i === 2 ? [{ label: '3D', tone: 'ok' }] : undefined}
                  hint={i === 2 ? 'Click to view in 3D' : undefined}
                  meta={<>you · {12 + i}k faces</>}
                />
              ))}
            </CardGrid>
          ) : (
            <EmptyState
              title="Nothing to explore yet."
              hint="Finished projects land here, alongside any images dropped into the gallery folder."
              action={<PillButton variant="ghost" size="sm">Open the folder</PillButton>}
            />
          )}
          <div className="mt-5">
            <p className="mb-2 text-[11px] uppercase tracking-[0.16em] text-[var(--su-text-faint)]">Recent</p>
            <HistoryStrip
              items={[
                { id: '1', title: 'run one', status: 'ok' },
                { id: '2', title: 'run two', status: 'busy' },
                { id: '3', title: 'run three', status: 'danger' },
              ]}
              activeId="2"
              onPick={() => {}}
            />
          </div>
        </div>
      </Section>

      <Section title="Workspace chrome">
        <Toolbar
          side="right"
          items={[
            { id: '1', icon: <Dot />, label: 'Zoom in' },
            { id: '2', icon: <Dot />, label: 'Zoom out' },
            { id: '3', icon: <Dot />, label: 'Fit', separated: true },
            { id: '4', icon: <Dot />, label: 'Grid', active: true },
            { id: '5', icon: <Dot />, label: 'Disabled', disabled: true },
          ]}
        />
        <Toolbar
          orientation="horizontal"
          items={[
            { id: '1', icon: <Dot />, label: 'Material', active: true },
            { id: '2', icon: <Dot />, label: 'Wire' },
            { id: '3', icon: <Dot />, label: 'Normal' },
          ]}
        />
        <ModeRail
          value={mode} onChange={setMode}
          items={[
            { value: 'image', label: 'Image to 3D', icon: <Dot /> },
            { value: 'edit', label: '3D Editing', icon: <Dot /> },
            { value: 'world', label: 'WorldGen', icon: <Dot />, disabled: true },
          ]}
        />
        <InfoPanel
          className="w-[208px]"
          title="Model info"
          rows={[
            { label: 'Triangles', value: '29,510' },
            { label: 'Vertices', value: '19,199' },
            { label: 'Meshes', value: '1' },
            { label: 'File size', value: '5.13 MB' },
          ]}
        />
        <GlassPanel className="w-full max-w-[560px] p-0" radius="lg">
          <StageHeader
            onBack={() => {}}
            title="Ember Golem"
            subtitle="trellis · 29.5k tris"
            actions={<PillButton variant="accent" size="sm">Export</PillButton>}
          />
        </GlassPanel>
      </Section>

      <Section title="Overlays">
        <PillButton variant="ghost" size="sm" onClick={() => setZoom('demo')}>Open lightbox</PillButton>
      </Section>

      {zoom && (
        <Lightbox
          src="data:image/svg+xml;utf8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='480' height='360'%3E%3Crect width='480' height='360' fill='%23222'/%3E%3Ctext x='240' y='185' fill='%23888' font-family='monospace' font-size='16' text-anchor='middle'%3Elightbox%3C/text%3E%3C/svg%3E"
          caption="A caption sits under the image"
          onClose={() => setZoom(null)}
        />
      )}
    </div>
  );
};

/** Neutral stand-in so the demo needs no image assets. */
const Placeholder: React.FC<{ seed: number }> = ({ seed }) => (
  <svg viewBox="0 0 120 120" className="h-full w-full" preserveAspectRatio="xMidYMid slice" aria-hidden>
    <rect width="120" height="120" fill="var(--su-surface-sunk)" />
    <circle cx={40 + seed * 12} cy="52" r={22 - seed * 2} fill="var(--su-surface-3)" />
    <rect x="26" y="72" width="68" height="26" rx="8" fill="var(--su-surface-2)" />
  </svg>
);

const Dot: React.FC = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor"
       strokeWidth="2" aria-hidden><circle cx="12" cy="12" r="7" /></svg>
);
