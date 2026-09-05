import React, { useState } from 'react';
import { ScrollView, Text, View } from 'react-native';
import { type, useTheme, type Status } from './theme';
import {
  Divider, EmptyState, Field, FlowBoard, FlowNode, GlassPanel, HistoryStrip, Hint,
  IconButton, ImagePickerTile, InfoPanel, Lightbox, MediaCard, ModeTabs, Notice,
  PillButton, ProgressRing, Screen, ScreenHeader, SearchField, Segmented, Sheet,
  ShelfTabs, Slider, StatusChip, StatusPill, StepMarker, Toolbar,
  type FlowNodeData, type Insets,
} from './components';

/* ===========================================================================
 * studio-ui-native — demo
 *
 * Every component in every state, on one scroll. This is not documentation; it
 * is the test you run after rebranding.
 *
 * A kit this size has too many states to check by reading, and the failure mode
 * of a token change is never a crash — it is one panel that went unreadable,
 * which you only find by looking at all of them at once. On mobile there is a
 * second reason: this is also where you notice that a control you shrank is now
 * under 44pt, or that a label wraps to three lines at large text sizes.
 *
 *   <ThemeProvider><Demo insets={useSafeAreaInsets()} /></ThemeProvider>
 * ========================================================================= */

const STATUSES: Status[] = ['idle', 'busy', 'ok', 'warn', 'danger'];

const Dot: React.FC<{ color?: string }> = ({ color }) => (
  <View style={{ width: 14, height: 14, borderRadius: 7, borderWidth: 2, borderColor: color ?? '#9c9c9c' }} />
);

const Section: React.FC<{ title: string; note?: string; children: React.ReactNode }> = ({
  title, note, children,
}) => {
  const t = useTheme();
  return (
    <View style={{ marginBottom: t.space(9) }}>
      <Text style={[type.micro, { color: t.textFaint }]}>{title}</Text>
      {note && (
        <Text style={[type.caption, { color: t.textGhost, marginTop: t.space(1), lineHeight: 18 }]}>
          {note}
        </Text>
      )}
      <View style={{ marginTop: t.space(3), gap: t.space(3) }}>{children}</View>
    </View>
  );
};

export const Demo: React.FC<{ insets?: Insets }> = ({
  insets = { top: 0, bottom: 0, left: 0, right: 0 },
}) => {
  const t = useTheme();
  const [seg, setSeg] = useState('a');
  const [mode, setMode] = useState('image');
  const [tab, setTab] = useState('mine');
  const [q, setQ] = useState('');
  const [slider, setSlider] = useState(1.4);
  const [text, setText] = useState('');
  const [sheet, setSheet] = useState(false);
  const [zoom, setZoom] = useState(false);
  const [notice, setNotice] = useState<string | null>('A dismissible line of feedback.');
  const [nodes, setNodes] = useState<FlowNodeData[]>([
    { id: 'a', label: 'Your image', status: 'ok', meta: 'source', text: 'a small brass lantern' },
    {
      id: 'b', label: 'Model writes the prompt', status: 'ok', meta: 'flash · 7.2s',
      text: 'Stylised game-ready render of a small brass lantern, three-quarter front view, plain background, even light, no text.',
      note: 'Kept the shape, dropped the cluttered desk behind it.',
    },
    { id: 'c', label: 'Concept render', status: 'busy', meta: 'pro-image', progress: 62, message: 'rendering…' },
    { id: 'd', label: 'Reconstruction', status: 'idle', meta: 'queued' },
  ]);

  const advance = () =>
    setNodes((ns) => ns.map((n): FlowNodeData => (n.status === 'busy' ? { ...n, status: 'ok', progress: 100 } : n)));

  return (
    <Screen insets={insets}>
      <ScreenHeader
        title="studio-ui-native"
        subtitle="every component, every state"
        actions={<StatusPill status="ok" label="ok" />}
      />

      <ScrollView contentContainerStyle={{ padding: t.space(4), paddingBottom: t.space(24) }}>
        <Section title="Surfaces" note="Translucent fills, not blur — the honest cross-platform default. Pass blurComponent on iOS for real glass.">
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: t.space(2) }}>
            {([1, 2, 3, 'sunk'] as const).map((s) => (
              <GlassPanel key={String(s)} surface={s} style={{ width: 92, height: 68, alignItems: 'center', justifyContent: 'center' }}>
                <Text style={[type.mono, { color: t.textFaint, fontSize: 11 }]}>{String(s)}</Text>
              </GlassPanel>
            ))}
            <GlassPanel dashed style={{ width: 92, height: 68, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={[type.mono, { color: t.textGhost, fontSize: 11 }]}>dashed</Text>
            </GlassPanel>
            <GlassPanel lift={2} style={{ width: 92, height: 68, alignItems: 'center', justifyContent: 'center' }}>
              <Text style={[type.mono, { color: t.textFaint, fontSize: 11 }]}>lift 2</Text>
            </GlassPanel>
          </View>
        </Section>

        <Section title="Buttons" note="subLabel replaces the web kit's hover label — on a phone the price belongs in front of you, not behind a gesture.">
          <PillButton title="Accent" variant="accent" subLabel="$0.02" />
          <PillButton title="Solid" variant="solid" />
          <PillButton title="Ghost" variant="ghost" />
          <PillButton title="Disabled" variant="ghost" disabled />
          <PillButton title="GENERATE" variant="ghost" size="lg" progress={42} />
          <PillButton title="GENERATE" variant="accent" size="lg" busy busyLabel="Rendering…" />
          <View style={{ flexDirection: 'row', gap: t.space(2), alignItems: 'center' }}>
            <IconButton label="resting"><Dot /></IconButton>
            <IconButton label="active" active><Dot /></IconButton>
            <IconButton label="danger" tone="danger"><Dot /></IconButton>
            <IconButton label="disabled" disabled><Dot /></IconButton>
            <Hint
              title="About hit targets"
              body="Every icon control here is at least 44pt including hitSlop, even when it looks smaller. On the web this would be a tooltip; there are no tooltips on a phone, so it is a sheet."
              icon={<Dot />}
            />
          </View>
        </Section>

        <Section title="Choice">
          <Segmented
            value={seg}
            onChange={setSeg}
            options={[
              { value: 'a', label: 'Concept' },
              { value: 'b', label: 'Direct' },
              { value: 'c', label: 'Off', disabled: true },
            ]}
          />
          <ModeTabs
            value={mode}
            onChange={setMode}
            style={{ marginHorizontal: -t.space(4) }}
            items={[
              { value: 'image', label: 'Image to 3D', icon: <Dot /> },
              { value: 'edit', label: '3D Editing', icon: <Dot /> },
              { value: 'world', label: 'WorldGen', icon: <Dot />, disabled: true },
            ]}
          />
          <PillButton title="Open a sheet" size="sm" variant="ghost" onPress={() => setSheet(true)} />
        </Section>

        <Section title="Status" note="Meaning stays separate from the brand accent — a red brand must not make every panel look like an error.">
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: t.space(2) }}>
            {STATUSES.map((s) => <StatusChip key={s} status={s} label={s} />)}
          </View>
          <View style={{ flexDirection: 'row', gap: t.space(2), alignItems: 'center' }}>
            {STATUSES.map((s, i) => <StepMarker key={s} index={i + 1} status={s} />)}
            <ProgressRing value={68} size={30} />
          </View>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: t.space(2) }}>
            {STATUSES.map((s) => <StatusPill key={s} status={s} label={s} />)}
          </View>
        </Section>

        <Section title="Notices">
          {STATUSES.map((s) => (
            <Notice key={s} tone={s}>{`tone ${s}`}</Notice>
          ))}
          {notice && (
            <Notice tone="warn" onDismiss={() => setNotice(null)} dismissIcon={<Dot />}>
              {notice}
            </Notice>
          )}
        </Section>

        <Section title="Inputs">
          <Field value={text} onChangeText={setText} label="Prompt" placeholder="Say what to change…" />
          <Field value={text} onChangeText={setText} multiline placeholder="A longer well…" />
          <SearchField value={q} onChangeText={setQ} icon={<Dot />} clearIcon={<Dot />} />
          <Slider label="Directional" value={slider} onChange={setSlider} min={0} max={3} format={(v) => `${v.toFixed(2)}×`} />
          <ImagePickerTile
            label="Image to 3D"
            hint="Tap to choose a photo"
            onPickLibrary={() => {}}
            onPickCamera={() => {}}
            addIcon={<Text style={{ fontSize: 34, color: t.textFaint }}>+</Text>}
            cameraIcon={<Dot />}
            style={{ width: 180 }}
          />
        </Section>

        <Section title="Flow" note="Vertical on a phone. Four stages across 390pt would be four unreadable slivers.">
          <FlowBoard
            nodes={nodes}
            subtitle="Concept run"
            title="Small Brass Lantern"
            statusLabel={{ status: 'busy', label: 'running' }}
            actions={<PillButton title="Advance" size="sm" variant="ghost" onPress={advance} />}
            renderNode={(n, i) => (
              <FlowNode
                node={n}
                index={i}
                settled={n.status !== 'busy'}
                onEdit={n.text ? () => {} : undefined}
                onRetry={i > 0 ? () => {} : undefined}
                editAction={i === 0 ? 'Rewrite & re-run' : 'Use this exactly'}
                icons={{ edit: <Dot />, retry: <Dot />, close: <Dot /> }}
                footer={i === 3 && n.status === 'ok' ? <PillButton title="Open in 3D" variant="solid" size="sm" /> : undefined}
              />
            )}
          />
        </Section>

        <Section title="Gallery" note="Metadata is always visible — there is no hover to hide it behind, and at two columns that is better anyway.">
          <ShelfTabs
            tabs={[{ value: 'mine', label: 'Asset', count: 16 }, { value: 'all', label: 'Explore', count: 23 }]}
            value={tab}
            onChange={setTab}
          />
          {tab === 'mine' ? (
            <View style={{ flexDirection: 'row', gap: t.space(3) }}>
              {['Ember Golem', 'Retro Van'].map((title, i) => (
                <MediaCard
                  key={title}
                  title={title}
                  meta={`you · ${12 + i}k faces`}
                  hint={i === 1 ? 'Tap to view in 3D' : undefined}
                  badges={i === 0 ? [{ label: '3' }] : [{ label: '3D', tone: 'ok' }]}
                  toggle={{ active: i === 0, onToggle: () => {}, icon: <Dot />, label: 'Like' }}
                  onPress={() => {}}
                  onLongPress={() => setSheet(true)}
                  style={{ flex: 1 }}
                />
              ))}
            </View>
          ) : (
            <EmptyState
              title="Nothing to explore yet."
              hint="Finished projects land here."
              action={<PillButton title="Start one" size="sm" />}
            />
          )}
          <HistoryStrip
            style={{ marginHorizontal: -t.space(4) }}
            items={[
              { id: '1', title: 'run one', status: 'ok' },
              { id: '2', title: 'run two', status: 'busy' },
              { id: '3', title: 'run three', status: 'danger' },
            ]}
            activeId="2"
            onPick={() => {}}
          />
        </Section>

        <Section title="Workspace">
          <InfoPanel
            title="Model info"
            collapsible
            chevron={<Dot />}
            rows={[
              { label: 'Triangles', value: '29,510' },
              { label: 'Vertices', value: '19,199' },
              { label: 'File size', value: '5.13 MB' },
            ]}
          />
          <Divider />
          <PillButton title="Open the lightbox" size="sm" variant="ghost" onPress={() => setZoom(true)} />
        </Section>
      </ScrollView>

      <Toolbar
        insets={insets}
        items={[
          { id: 'fit', icon: <Dot />, label: 'Fit' },
          { id: 'grid', icon: <Dot />, label: 'Grid', active: true },
          { id: 'light', icon: <Dot />, label: 'Light' },
          { id: 'info', icon: <Dot />, label: 'Info', disabled: true },
        ]}
      />

      <Sheet visible={sheet} onClose={() => setSheet(false)} title="A bottom sheet" closeIcon={<Dot />}>
        <Text style={[type.body, { color: t.textDim, lineHeight: 22 }]}>
          This is the mobile Popover. Anchoring a panel beside its trigger assumes room beside
          the trigger and a cursor to aim with — neither exists here, so it comes from the
          bottom where the thumb already is.
        </Text>
        <Slider
          label="Exposure"
          value={slider}
          onChange={setSlider}
          min={0}
          max={3}
          format={(v) => `${v.toFixed(2)}×`}
          style={{ marginTop: t.space(5) }}
        />
      </Sheet>

      <Lightbox visible={zoom} onClose={() => setZoom(false)} caption="Tap anywhere to close" closeIcon={<Dot color="#fff" />}>
        <View style={{ width: 240, height: 240, borderRadius: t.radiusMd, backgroundColor: t.surface3, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={[type.mono, { color: t.textFaint }]}>image</Text>
        </View>
      </Lightbox>
    </Screen>
  );
};
