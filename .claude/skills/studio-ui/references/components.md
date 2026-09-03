# Component reference

Props, states, and the reasoning that is not obvious from the signature.

- [primitives](#primitives) — GlassPanel, IconButton, PillButton, Segmented, StatusChip, StepMarker, ProgressRing, Tooltip, Popover, Slider, Field, TextArea
- [flow](#flow) — FlowBoard, FlowNode, Connector
- [gallery](#gallery) — MediaCard, CardGrid, Thumb, EmptyState, ShelfTabs, SearchField, HistoryStrip, DropZone, Lightbox
- [workspace](#workspace) — Toolbar, InfoPanel, Notice, StatusPill, StageHeader, ModeRail, StageOverlay

A shared vocabulary first, because five components take it:

```ts
type Status = 'idle' | 'busy' | 'ok' | 'warn' | 'danger';
```

`idle` is *not yet*, not *disabled*. A step that has not run is `idle`; a step
that cannot run is absent from the flow.

---

## primitives

### GlassPanel

The base surface. Nearly every panel in the kit is one.

| prop | type | note |
|---|---|---|
| `surface` | `1 \| 2 \| 3 \| 'sunk'` | 1 resting, 2 hover/nested, 3 active, `sunk` for wells you put things *into* |
| `radius` | `'sm' \| 'md' \| 'lg' \| 'pill'` | |
| `bordered` | `boolean` | default true |
| `dashed` | `boolean` | reads as "nothing here yet" — empty slots, drop targets |
| `blur` | `boolean \| 'heavy'` | |
| `lifted` | `boolean` | drop shadow; for things that float over content |

**On `blur`.** It is what separates glass from a grey rectangle, and it only
reads as glass when there is something behind it worth blurring. Over flat
ground it is wasted GPU. Pass `blur={false}` in long scrolling lists, where the
cost multiplies by the number of rows.

### IconButton

`active` is a visual state, not a disabled one — an active IconButton is still
pressable, which is what a toggle needs. `tone="danger"` tints only on hover, so
a delete button is not shouting from across the screen.

Always give it an `aria-label` or wrap it in a `Tooltip`. An icon-only control
with neither is unusable to a screen reader and merely guessable to everyone
else.

### PillButton

The primary action.

| prop | type | note |
|---|---|---|
| `variant` | `'accent' \| 'solid' \| 'ghost'` | accent uses `--su-gradient` |
| `size` | `'sm' \| 'md' \| 'lg'` | `lg` is the 60px hero button |
| `progress` | `number` | 0–100; fills the button from the left |
| `hoverLabel` | `ReactNode` | swaps the label on hover |
| `busy` | `ReactNode` | replaces the label entirely while working |
| `icon` | `ReactNode` | |

```tsx
<PillButton
  variant="accent" size="lg"
  progress={running ? job.progress : undefined}
  hoverLabel={cost > 0 ? `$${cost.toFixed(2)}` : 'Free'}
  busy={running && <><ProgressRing value={job.progress} /> {job.stage}</>}
  onClick={run}
>
  GENERATE
</PillButton>
```

`hoverLabel` is for information that matters *at the moment of committing* and
is noise before it — the price, the shortcut, the destination. Not for the
button's own explanation; that belongs in a Tooltip or nowhere.

### Segmented

Mutually exclusive choice, 2–4 options. Past four the labels stop fitting and it
wants to be a `<select>`. Options take a `hint`, surfaced as `title` — a
segmented control has room for a word and the choice usually needs a sentence.

### StatusChip / StepMarker / ProgressRing

`StatusChip` labels the thing beside it and is deliberately quiet; a chip that
outshouts its own heading has the hierarchy backwards.

`StepMarker` carries four states in a 22px circle. The number shows only while
the step is `idle` — once something has happened to a step, *what* happened
matters more than where it sits, and the position is already obvious from the
layout. Pass `icons` to supply the glyphs:

```tsx
<StepMarker index={2} status="busy" icons={{
  busy: <Loader2 className="h-3 w-3 su-spin" />,
  ok: <Check className="h-3 w-3" strokeWidth={3} />,
  danger: <AlertTriangle className="h-3 w-3" />,
}} />
```

### Tooltip / Popover

`Tooltip` is hover-and-focus, and holds a hint — never the only copy of
something a keyboard user needs. If the tooltip is the only place the
information exists, it belongs in the interface instead.

`Popover` renders a real scrim element rather than a document listener, because
the scrim also blocks the click reaching what is underneath. Dismissing a
popover should not simultaneously press the button behind it — that is the
classic bug in the listener version. Escape closes it.

### Slider

Always shows its value. A slider with no number is unusable for anything you
might want to reproduce, come back to, or tell somebody about, and in a tool
like this every slider is eventually one of those. `format` controls the
readout (`v => \`${v.toFixed(1)}×\``).

Mount `<SliderStyles />` once near your root.

**A test worth running on any slider you add:** change it across its full range
and confirm the output actually moves. This kit lost an ambient-light slider
that measured 48.17 → 48.16 across a 0–3× sweep — it looked like a control and
was decoration. Delete those rather than shipping them.

### Field / TextArea

`Field` puts its `action` inside the border so the whole thing reads as one
control rather than an input next to a button. `TextArea` is `sunk` because you
are putting something into it.

---

## flow

### FlowBoard

```tsx
<FlowBoard
  nodes={run.nodes}
  title={run.title}
  subtitle="Concept run"
  status={{ status: toStatus(run.status), label: run.status }}
  actions={<IconButton onClick={close}><X /></IconButton>}
  error={run.error}
  renderNode={(node, i) => (
    <FlowNode node={toFlowNode(node)} index={i} settled={run.status !== 'running'} … />
  )}
/>
```

`renderNode` rather than a baked-in FlowNode: a board is a *layout*, and the
moment one stage needs something the others do not, a fixed renderer becomes a
fork of the whole component.

Stacks vertically below `lg`, where four across would be four unreadable
columns. Connectors hide when stacked.

### FlowNode

| prop | note |
|---|---|
| `node` | `{ id, label, status, meta?, imageUrl?, text?, note?, progress?, message?, error? }` |
| `settled` | gates edit and retry — a control that fights a running job is worse than none |
| `onEdit(text)` | makes the node's text editable |
| `onRetry()` | re-run from this stage |
| `editAction` | button copy. Name the **action** — the user is starting work, not filing something |
| `footer` | e.g. an "Open result" button on the last node |
| `children` | takes over the body entirely when a stage needs custom rendering |

The body picks a renderer in this order: editor → `children` → error → image →
text → progress → waiting. Give a node both `imageUrl` and `text` and the image
wins; that is usually right, but pass `children` if you need both.

**`label` should say what the stage does, not what it is called internally.**
"Gemini writes the prompt" beats "prompt_stage". The board is often the first
place a user learns what your pipeline actually is.

**Where an edit re-enters the pipeline is a product decision.** Editing the
user's own words should re-run the step that interprets them; editing a
*generated* value should skip that step and use the value verbatim. If both go
to the same entry point, one of them is a lie — the user edits generated text,
watches it get regenerated, and concludes the field does nothing.

### Connector

`self-center` is load-bearing. An explicit height inside an `items-stretch` row
cannot stretch, so without it the arrows sit at the top edge of the row and the
board stops reading as one line. Do not remove it.

Fills as the node *after* it starts working, so the connector shows where the
work currently is without reading a label.

---

## gallery

### MediaCard

| prop | note |
|---|---|
| `badges` | top-left. State that must be readable **without** hovering |
| `toggle` | top-right. A like, a pin, a select — stops propagation for you |
| `meta` | hover only. Author, counts, engine |
| `hint` | hover only. What clicking will do |
| `aspect` | default `1 / 1`; fixed so nothing reflows as images land |

Keyboard-accessible: `Enter` and `Space` fire `onOpen`, and the toggle handles
its own keys without triggering the card.

**Use `hint` when a card's click does something surprising.** In a gallery
mixing built and unbuilt items, "Click to view in 3D" versus "Click to load as
reference" is the difference between a predictable grid and a lottery.

### Thumb

`loading="lazy"` and `decoding="async"` are the point. `fallback` is drawn when
there is no `src` or the image 404s — a seeded shape beats a grey box, and the
`onError` fallback matters more than it sounds: a stale URL otherwise renders as
a broken-image glyph in the middle of an otherwise polished grid.

### ShelfTabs

Counts live inside the label, because the number is what people navigate by
once they have used the app twice ("the tab with 40 in it").

If two tabs show the same items under different rules — every attempt vs. one
per project — make sure something on the card explains the gap. A count
mismatch with no explanation reads as a bug.

### SearchField

Collapsed to an icon until used. A permanently-open search box on a gallery
header competes with the content and is used maybe once a session. Escape clears
and closes.

### DropZone

Drag, click, **and paste** — paste is how people actually move a screenshot into
a tool and it is three lines to support.

It reports files and never owns them. Object URLs must be revoked by whoever
created them; a component that both creates and forgets them is a leak with a
nice border.

### Lightbox / HistoryStrip

`Lightbox` dismisses on backdrop click and Escape. `HistoryStrip` marks
selection with a border rather than a scale or glow — the row is dense, and
anything that changes an item's *size* makes its neighbours move.

---

## workspace

### Toolbar

Every item gets a Tooltip, and that is not politeness: an icon-only rail is
unusable without one, and the tooltip is the only place the control's name
exists. If an item cannot survive being reduced to one glyph plus a hover label,
it belongs in a menu.

`separated: true` draws a hairline above an item — group things that belong
together.

### InfoPanel

Values are monospaced and right-aligned so a column of numbers lines up. Labels
are uppercase, tracked out, and low-contrast; that contrast gap is what makes
the values scannable.

Fill it from data you already have. Counting geometry on the client to populate
a panel means it stays empty until the model loads, and empty-then-populated
reads as broken.

### Notice

Dismissible by default. A notice that stays until something replaces it trains
people to stop reading the spot it appears in. If a message must be
acknowledged, it is a dialog.

`role` is `alert` for `danger` and `status` otherwise, so screen readers
interrupt for the first and queue the second.

**Give failures a Notice rather than a silent console error.** A rejected fetch
with no handler is invisible, and the user's only signal is that nothing
happened.

### StatusPill

States what *is*, and stays visible when everything is fine. A health indicator
that only appears on failure is one the user has no reason to trust, because
they have never seen it working.

### StageHeader / StageOverlay

The title is centred and controls are pinned to the edges, so the header stays
symmetric no matter how many actions there are.

`StageOverlay` renders its own opaque background because it is a **page, not a
modal**. A viewer opened over a still-mounted gallery keeps every thumbnail
decoded and every canvas running behind it. Unmount the grid; render the stage.

### ModeRail

Icon over a two-word caption. The caption is what separates this from a
`Toolbar`: a mode changes what the whole workspace is *for*, and that is too
consequential to communicate with a glyph and a hover.
