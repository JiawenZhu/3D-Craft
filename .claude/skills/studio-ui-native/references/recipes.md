# Recipes

Four screens. Copy one and replace the data.

All of them assume the provider is already mounted and `insets` comes from
`useSafeAreaInsets()`.

---

## 1. App shell

The wiring every other recipe sits inside.

```tsx
import { SafeAreaProvider, useSafeAreaInsets } from 'react-native-safe-area-context';
import { ThemeProvider } from './studio-ui/theme';

export default function App() {
  return (
    <SafeAreaProvider>
      <ThemeProvider
        scheme="dark"
        overrides={{
          accent: '#d8a1f1',
          accentInk: '#121317',
          accentSoft: 'rgba(216,161,241,0.14)',
          ok: '#6ee7a8', okSoft: 'rgba(110,231,168,0.14)',
          danger: '#f08a8a', dangerSoft: 'rgba(240,138,138,0.14)',
        }}
      >
        <Navigation />
      </ThemeProvider>
    </SafeAreaProvider>
  );
}
```

Those five lines of `overrides` are the entire brand. Everything else in the kit
is structural and inherits.

---

## 2. Gallery screen

Two tabs over one grid. The header scrolls with the content rather than pinning,
because a phone cannot spend fixed vertical space on chrome.

```tsx
import { MediaGrid, MediaCard, ShelfTabs, SearchField, EmptyState, Screen, PillButton } from './studio-ui';

export function GalleryScreen({ navigation }) {
  const insets = useSafeAreaInsets();
  const [tab, setTab] = useState('mine');
  const [q, setQ] = useState('');
  const items = useItems(tab, q);

  return (
    <Screen insets={insets}>
      <MediaGrid
        data={items}
        keyExtractor={(a) => a.id}
        minColumnWidth={170}
        header={
          <View style={{ gap: 16, paddingBottom: 8 }}>
            <ShelfTabs
              tabs={[
                { value: 'mine', label: 'Asset', count: mine.length },
                { value: 'all', label: 'Explore', count: everyones.length },
              ]}
              value={tab}
              onChange={setTab}
            />
            <SearchField
              value={q}
              onChangeText={setQ}
              icon={<Feather name="search" size={16} color="#9c9c9c" />}
              clearIcon={<Feather name="x" size={14} />}
            />
          </View>
        }
        empty={
          <EmptyState
            title="Nothing here yet."
            hint="Tap + to start from a photo, or pull one in from Explore."
            action={<PillButton title="Browse Explore" size="sm" onPress={() => setTab('all')} />}
          />
        }
        renderItem={(a) => (
          <MediaCard
            title={a.name}
            uri={a.thumbUrl}
            meta={`${a.author} · ${compact(a.faces)} faces`}
            hint={a.modelUrl ? 'Tap to view in 3D' : 'Tap to use as reference'}
            badges={[
              a.versions > 1 && { label: `${a.versions}` },
              a.private && { label: 'private' },
            ].filter(Boolean)}
            toggle={{
              active: a.liked,
              onToggle: () => like(a.id),
              icon: <Feather name="heart" size={15} />,
              label: 'Like',
            }}
            onPress={() => navigation.navigate('Viewer', { id: a.id })}
            onLongPress={() => openActions(a)}
          />
        )}
      />
    </Screen>
  );
}
```

`onLongPress` is where a web app would have put hover actions — open a `Sheet`
with rename, duplicate, delete.

---

## 3. Generator screen

Image in, words beside it, one action out. The keyboard is the whole difficulty
here.

```tsx
import { KeyboardAvoidingView, Platform, ScrollView } from 'react-native';
import { Screen, ImagePickerTile, Field, Segmented, PillButton, Notice } from './studio-ui';

export function GeneratorScreen() {
  const insets = useSafeAreaInsets();
  const [image, setImage] = useState<string>();
  const [prompt, setPrompt] = useState('');
  const [route, setRoute] = useState<'concept' | 'direct'>('concept');
  const { run, job, notice } = useGeneration();

  return (
    <Screen insets={insets}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        // iOS needs padding; Android does the work in the manifest via
        // windowSoftInputMode and usually needs nothing here.
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={insets.top + 52}
      >
        <ScrollView
          contentContainerStyle={{ padding: 16, gap: 16 }}
          keyboardShouldPersistTaps="handled"   // otherwise the first tap only dismisses the keyboard
        >
          <ImagePickerTile
            uri={image}
            label="Image to 3D"
            hint="A clear photo of one object works best"
            onPickLibrary={pickFromLibrary}
            onPickCamera={takePhoto}
            onClear={() => setImage(undefined)}
            addIcon={<Feather name="plus" size={34} color="#9c9c9c" />}
            cameraIcon={<Feather name="camera" size={16} />}
            clearIcon={<Feather name="trash-2" size={16} />}
          />

          <Segmented
            value={route}
            onChange={setRoute}
            options={[
              { value: 'concept', label: 'Concept → 3D' },
              { value: 'direct', label: 'Direct → 3D' },
            ]}
          />

          <Field
            value={prompt}
            onChangeText={setPrompt}
            label="What to change"
            placeholder="e.g. make it a forest ranger with a lantern"
            onSubmit={run}
          />

          {notice && <Notice tone="warn" onDismiss={notice.dismiss}>{notice.text}</Notice>}

          <PillButton
            title="GENERATE"
            subLabel={cost > 0 ? `$${cost.toFixed(2)}` : 'Free'}
            size="lg"
            variant="accent"
            busy={job?.status === 'busy'}
            busyLabel={job?.stage}
            progress={job?.progress}
            disabled={!image && !prompt.trim()}
            onPress={run}
          />
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}
```

Two things that are easy to miss and annoying to debug:
`keyboardShouldPersistTaps="handled"` (without it the first tap on the button
only dismisses the keyboard), and `keyboardVerticalOffset` matching your header
height (without it the field hides behind the keyboard on iOS).

---

## 4. Pipeline screen

The stage board, vertical on a phone.

```tsx
import { Screen, ScreenHeader, FlowBoard, FlowNode, PillButton, IconButton, Lightbox } from './studio-ui';

const toStatus = (s) => s === 'running' ? 'busy' : s === 'done' ? 'ok' : s === 'failed' ? 'danger' : 'idle';

export function RunScreen({ run, onRetry, onEdit, navigation }) {
  const insets = useSafeAreaInsets();
  const [zoom, setZoom] = useState<string | null>(null);
  const settled = run.status !== 'running';

  return (
    <Screen insets={insets}>
      <ScreenHeader
        title={run.title}
        subtitle={`${run.nodes.filter(n => n.status === 'done').length} of ${run.nodes.length} stages`}
        onBack={navigation.goBack}
        backIcon={<Feather name="chevron-left" size={20} />}
      />

      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <FlowBoard
          nodes={run.nodes.map((n) => ({ ...n, status: toStatus(n.status) }))}
          subtitle="Concept run"
          statusLabel={{ status: toStatus(run.status), label: run.status }}
          error={run.status === 'failed' ? run.error : undefined}
          renderNode={(node, i) => (
            <FlowNode
              node={node}
              index={i}
              settled={settled}
              onPressImage={setZoom}
              onRetry={i > 0 ? () => onRetry(node.kind) : undefined}
              // Editing your own words re-runs the interpreter; editing a
              // generated value skips it. Different entry points, deliberately.
              onEdit={
                node.kind === 'source' ? (t) => onEdit('interpret', t)
                : node.kind === 'prompt' ? (t) => onEdit('render', t)
                : undefined
              }
              editAction={node.kind === 'source' ? 'Rewrite & re-run' : 'Use this exactly'}
              icons={{
                edit: <Feather name="edit-2" size={13} />,
                retry: <Feather name="refresh-cw" size={13} />,
                close: <Feather name="x" size={13} />,
                ok: <Feather name="check" size={13} />,
                danger: <Feather name="alert-triangle" size={13} />,
              }}
              footer={
                node.kind === 'result' && node.status === 'ok' && (
                  <PillButton
                    title="Open in 3D"
                    variant="solid"
                    size="sm"
                    onPress={() => navigation.navigate('Viewer', { id: run.assetId })}
                  />
                )
              }
            />
          )}
        />
      </ScrollView>

      <Lightbox
        visible={!!zoom}
        onClose={() => setZoom(null)}
        closeIcon={<Feather name="x" size={20} color="#fff" />}
      >
        {zoom && <Image source={{ uri: zoom }} resizeMode="contain" style={{ width: '100%', height: '70%' }} />}
      </Lightbox>
    </Screen>
  );
}
```

The layout is the easy part. What matters is that each stage's retry re-enters
the pipeline at its own point, keeping everything upstream — a board whose every
button restarts from the top is a nicer-looking progress bar.

---

## 5. Viewer screen

A canvas with chrome floating over it.

```tsx
import { Stage, ScreenHeader, Toolbar, InfoPanel, IconButton } from './studio-ui';

export function ViewerScreen({ asset, navigation }) {
  const insets = useSafeAreaInsets();
  const [showInfo, setShowInfo] = useState(false);

  return (
    <Stage
      insets={insets}
      header={
        <ScreenHeader
          title={asset.name}
          subtitle={`${asset.engine} · ${compact(asset.faces)} tris`}
          onBack={navigation.goBack}
          backIcon={<Feather name="chevron-left" size={20} />}
          actions={<IconButton label="Export" onPress={exportAsset}><Feather name="download" size={18} /></IconButton>}
        />
      }
      toolbar={
        <Toolbar
          floating
          insets={insets}
          items={[
            { id: 'fit',   icon: <Feather name="maximize" size={18} />,  label: 'Fit',   onPress: fit },
            { id: 'grid',  icon: <Feather name="grid" size={18} />,      label: 'Grid',  active: grid, onPress: toggleGrid },
            { id: 'light', icon: <Feather name="sun" size={18} />,       label: 'Light', onPress: openLightSheet },
            { id: 'info',  icon: <Feather name="info" size={18} />,      label: 'Info',  active: showInfo, onPress: () => setShowInfo(v => !v) },
          ]}
        />
      }
    >
      <GLView style={{ flex: 1 }} />

      {showInfo && (
        <InfoPanel
          style={{ position: 'absolute', left: 16, top: insets.top + 60, width: 200 }}
          title="Model info"
          rows={[
            { label: 'Triangles', value: asset.faces.toLocaleString() },
            { label: 'Meshes', value: String(asset.meshes) },
            { label: 'Size', value: `${asset.fileSizeMb.toFixed(2)} MB` },
          ]}
        />
      )}
    </Stage>
  );
}
```

`Stage`, not an overlay — navigate here so the gallery's FlatList unmounts. A
grid of decoded images held in memory behind a GL canvas is how a phone app gets
killed.

Light controls go in a `Sheet` rather than a panel pinned to the canvas: sliders
need a comfortable touch row, and there is no room for that over a viewport.
