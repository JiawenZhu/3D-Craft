# Component reference

Props, states, and the reasoning that is not obvious from the signature. Every
component takes colours from `useTheme()`; none takes a colour prop.

Shared vocabulary:

```ts
type Status = 'idle' | 'busy' | 'ok' | 'warn' | 'danger';
```

`idle` is *not yet*, never *disabled*. A step that has not run is `idle`; one
that cannot run should not be in the flow.

---

## theme

### `ThemeProvider` / `useTheme` / `themes`

`overrides` is a `Partial<Theme>` on purpose — a project should state the four
or five values that make it itself and inherit everything structural.

`scheme` takes `'dark' | 'light'`. Wire it to `useColorScheme()` if the app
follows the system; leave it fixed if the product is deliberately dark, which
studio tools usually are.

**Token names match the web kit's `--su-*` variables exactly** (`surface1`,
`textFaint`, `accentInk`, …). When one product ships both, a designer changing
"accent" changes one word in two files rather than translating vocabularies.

### `type`

One ramp: `title` `heading` `body` `label` `caption` `micro` `mono`. Sizes run a
little larger than the web kit's — 11px is fine on a monitor at arm's length and
is a squint on a phone.

### `elevation(0 | 1 | 2 | 3)`

Sets iOS shadow props *and* Android `elevation`. Never write shadow styles
directly; see `platform.md` for why one without the other is invisible on half
your users' devices.

### `space(n)`

4pt scale. `space(3)` is 12. Mobile has less room and more need for a consistent
beat — hardcoded margins are what make a scrolling screen feel assembled out of
unrelated cards.

### `tap`

44. The minimum hit target, and the number `IconButton` and `Slider` grow
towards with `hitSlop` rather than with visible padding.

---

## primitives

### GlassPanel

| prop | note |
|---|---|
| `surface` | `1 \| 2 \| 3 \| 'sunk'` — resting, hover-equivalent, active, and wells you put things *into* |
| `radius` | `'sm' \| 'md' \| 'lg' \| 'pill'` |
| `dashed` | reads as "nothing here yet". **Renders solid on Android** — see platform.md |
| `lift` | `0–3`, sets both shadow systems |
| `blurComponent` | e.g. `BlurView` from expo-blur, rendered behind the content |

The default is a translucent fill, not a blur. That is the honest cross-platform
answer: it costs nothing, looks identical on both, and blur is genuinely
expensive on Android. Opt in per-platform.

Do not combine `lift` with a surface meant to show what is behind it — Android's
`elevation` paints an opaque background.

### IconButton

Requires `label` — it becomes `accessibilityLabel`, and an icon-only control
without one is invisible to a screen reader. There are no tooltips here to carry
it either.

Clones its child to inject `color`, so `<IconButton><Feather name="x" /></IconButton>`
picks up the right tone automatically. Pass a plain `<View>` if you need to opt
out.

`hitSlop` fills the gap between `size` and `tap`, which is how a 28pt icon stays
comfortably tappable without a 44pt box of empty space around it. This is the
most common reason a good-looking RN toolbar feels broken in the hand.

### PillButton

| prop | note |
|---|---|
| `subLabel` | the web kit's `hoverLabel`, rendered under the title |
| `progress` | 0–100; fills from the left — the button IS the progress bar |
| `busy` / `busyLabel` | replaces the label with a spinner; also disables |
| `gradientComponent` | e.g. `LinearGradient`, for the accent variant |

Press feedback (scale 0.985) is not decoration. With no cursor and no hover, a
button that does not visibly react reads as broken and gets tapped twice — which
on a paid generation is a real cost.

### Segmented

Caps at three options on a phone. Four across 375pt gives each about 80pt, which
truncates any label worth reading; past three, use a `Sheet` with a list.

### StepMarker

Shows its number only while `idle`. Once something has happened to a step, what
happened matters more than where it sits, and the position is already obvious
from the layout. Falls back to a spinner for `busy` if you pass no icon.

### ProgressRing

Two rotated half-discs, no SVG. There is a shorter version using
`react-native-svg` and it is not worth a dependency in a kit whose selling point
is that it drops into any RN project.

### Slider

PanResponder, not a community package. The readout is always visible — a slider
with no number is unusable for anything you would want to reproduce or describe,
and on mobile there is no tooltip to hide it in. The touch row is `tap` tall
regardless of the 4pt track, because otherwise a 4pt track is a 4pt target.

**Test any slider you add by sweeping its full range and confirming the output
moves.** The web kit lost a light control that measured 48.17 → 48.16 across a
0–3× sweep; it looked like a control and was decoration.

### Field

One component for single-line and multiline (`multiline`). Sets
`paddingVertical: 0` on Android, where TextInput adds its own and otherwise
makes the same field two different heights across platforms.

`action` sits inside the border so the whole thing reads as one control.

---

## feedback

### Sheet

The mobile Popover. Bottom-anchored because that is where the thumb is.

Handles Android's hardware back — without it, back dismisses the sheet *and*
pops the screen underneath. The grab handle is not decorative: it is the only
affordance saying the panel can be dragged away rather than hunted for a button.

`maxHeight` is a fraction of screen height (default `0.75`), so a long list
scrolls inside the sheet instead of pushing its top off screen.

### Hint

The mobile Tooltip: an (i) that opens a `Sheet`. See the note in SKILL.md about
why needing one is a signal.

### Notice

`accessibilityLiveRegion` is `assertive` for `danger` and `polite` otherwise, so
a screen reader interrupts for the first and queues the second. A message that
exists only visually is invisible to anyone not looking at that part of the
screen — on a phone, most of it.

Give failures a `Notice` rather than a silent console error. A rejected promise
with no handler leaves the user with nothing but "nothing happened".

### StatusPill

States what *is* and stays visible when everything is fine. A health indicator
that only appears on failure is one nobody trusts, because they have never seen
it working. Pulses when `busy`, on the native driver.

### Lightbox

`animationType="fade"`, not a slide — the image is already on screen behind it
and a slide implies you navigated elsewhere.

---

## flow

### FlowBoard

Vertical below `horizontalAt` (default 700pt), horizontal above. `renderNode`
rather than a baked-in node: a board is a *layout*, and the moment one stage
needs something the others do not, a fixed renderer becomes a fork.

### FlowNode

| prop | note |
|---|---|
| `node` | `{ id, label, status, meta?, imageUri?, text?, note?, progress?, message?, error? }` |
| `settled` | gates edit and retry — a control that fights a running job is worse than none |
| `onEdit(text)` | makes the node's text editable in place |
| `onRetry()` | re-run from this stage |
| `icons` | supply `edit` / `retry` / `close` or those controls do not render |

Body renderer order: editor → `children` → error → image → text → progress →
waiting.

**`label` should say what the stage does, not what it is called internally.**
"Gemini writes the prompt" beats "prompt_stage" — the board is often where a
user learns what your pipeline actually is.

**Where an edit re-enters the pipeline is a product decision.** Editing the
user's own words should re-run the step that interprets them; editing a
*generated* value should skip that step and use the value verbatim. Wire both to
the same entry point and one of them is a lie — the user edits generated text,
watches it get regenerated, and concludes the field does nothing.

---

## gallery

### MediaCard

Metadata is **always visible**, under the image. There is no hover, and at phone
scale with two columns a permanently readable caption is better anyway.

`onLongPress` is where the web kit's hover actions go — the native idiom for
"more about this", and it does not compete with the tap.

Use `hint` when the tap does something surprising. In a grid mixing built and
unbuilt items, "Tap to view in 3D" versus "Tap to use as reference" is the
difference between a predictable grid and a lottery.

### MediaGrid

Derives `numColumns` from available width against `minColumnWidth`, so one
screen serves phone and tablet. Remounts on column change (`key={columns}`),
which RN requires when `numColumns` changes.

Windowing props are conservative on purpose (`windowSize: 5`,
`maxToRenderPerBatch: columns * 2`, `removeClippedSubviews`). The defaults are
tuned for text rows; generated images are large, and a phone gets killed by the
OS rather than swapping.

### ShelfTabs

Smaller than the web kit's 30px headings — a phone cannot spend 40pt of vertical
space on navigation and still show cards above the fold.

If two tabs show the same items under different rules, put something on the card
explaining the gap. A count mismatch with no explanation reads as a bug.

### SearchField

Always open, unlike the web kit's collapsing version. On a wide header a
permanent box competes with content; on a phone, expanding-on-tap is an extra
tap plus a layout shift with no room for the animation to read.

Renders its own clear button because `clearButtonMode` is iOS-only.

### ImagePickerTile

The mobile DropZone. No drag-and-drop, no reliable paste — so it collapses to
"tap to choose", with separate callbacks for library and camera because those
are genuinely two different actions on a phone.

It does **not** import `expo-image-picker`. A kit that hard-requires a
permissions-carrying native module cannot be dropped into an existing app, and
the app almost certainly has its own picker and its own permission copy already.

---

## workspace

### Screen / Stage

`Screen` paints the ground and takes the top inset. `Stage` is the full-screen
working view — a **separate screen, not an overlay**. On a phone, keeping a
FlatList of decoded images mounted behind a GL canvas is how an app gets killed
for memory. Navigate to it.

`Stage` gives a floating header `elevation: 4` on Android, where overlapping
siblings stack by elevation rather than source order.

### ScreenHeader

Title centred, actions pinned to fixed-width edges, so it stays symmetric
however many actions there are. `maxFontSizeMultiplier` caps growth at 1.4 —
respecting large-text settings matters, but a header that grows without bound
breaks the layout it anchors. Never cap at 1.0.

### Toolbar

Horizontal, bottom-pinned, **every item labelled**. `floating` makes it a
detached bar over a canvas; otherwise it sits on a solid ground with a hairline.

Bottom padding is `max(space(2), insets.bottom)` rather than a sum, so it does
not grow a gap on devices without a gesture bar.

### InfoPanel

`collapsible` exists because a phone cannot afford a permanent ten-row stats
panel over a canvas the way a desktop can.

Fill it from data you already have. Counting geometry on the client leaves the
panel empty until the model loads, and empty-then-populated reads as broken.

### ModeTabs

The mobile ModeRail — horizontal scroll, icon over label. A mode changes what
the whole screen is *for*, which is too consequential for a bare glyph.
