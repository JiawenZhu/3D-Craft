---
name: studio-ui
description: A dark-glass, colour-agnostic UI component kit for creative and generative tools — React + Tailwind, every colour behind a CSS variable so it takes any brand. Ships pipeline node graphs with per-stage retry and editable intermediate values, media galleries with lazy-loading cards, generator panels with drop zones and prompt fields, viewer chrome, and the primitives under them — glass panels, pill buttons with inline progress, segmented controls, popovers, tooltips, sliders, status chips. Use it when building or restyling an AI or generative product, a creative or media tool, a job dashboard, an asset gallery, a pipeline view, a 3D/image/video workspace, or any dark studio-style interface — and whenever someone asks for a component library, a design system, reusable components, or says a UI looks unfinished or generic. Reach for it even when only one component is named (a card grid, a progress button, a node graph), because taking that piece from the kit is what keeps the rest consistent.
---

# studio-ui

A component kit for tools where **the work is the product** — generators,
pipelines, asset libraries, viewers — and the interface is the frame around it.

It came out of a 3D generation studio, but nothing in it is about 3D. What it
encodes is a set of decisions that keep recurring in this kind of app: how to
show a job that takes two minutes across three models, how to render a grid of
forty generated images without melting a laptop, how to put chrome around a
canvas without stealing the canvas.

## Two rules that shape everything

**1. No colour literals.** Every colour resolves through `var(--su-*)`. The kit
ships achromatic — greys on a dark ground — so it never smuggles someone else's
brand into your project. You add the colour by overriding eight variables. This
is why the same components can sit in two products that look nothing alike.

**2. No icon dependency.** Icons arrive as `ReactNode` props. The kit works with
lucide, heroicons, inline SVG, or emoji, and adds nothing to `package.json`.
Components that need a glyph to be usable at all ship a plain-SVG fallback.

## Install

Copy `assets/components/` into the project (e.g. `src/studio-ui/`) and import
`assets/tokens.css` once, at the root:

```tsx
import './studio-ui/tokens.css';
import { GlassPanel, MediaCard, FlowBoard } from './studio-ui';
```

Requires React 17+ and Tailwind (v3 or v4). Nothing in `theme.extend` needs to
change — every colour is an arbitrary value pointing at a CSS variable — but
**the kit's path must be in Tailwind's `content` globs**:

```js
content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],   // add the kit's path
```

This is the one install step that fails silently and confusingly. Tailwind only
emits classes it can see in a scanned file, so a kit outside `content` renders
as unstyled boxes: no radius, no surface, no spacing — while the inline styles
(`backdropFilter`, the accent gradient) still apply, which makes it look like a
half-broken component rather than a missing config line. **Restart the dev
server after editing the config**; a running Tailwind will not pick it up.

Without Tailwind entirely, the class names are the spec — read them as the
styling contract and port them.

Mount `<SliderStyles />` once near the root if you use `Slider` —
`::-webkit-slider-thumb` cannot be expressed as a utility or an inline style.

## Platforms

The kit is **React DOM**. That is a real boundary, and it is worth knowing which
side a project is on before reaching for it.

**Works as-is** — anything rendering in a browser engine: desktop and mobile
web, PWAs, Electron and Tauri, and WebView-wrapped mobile (Capacitor, Ionic,
Cordova). On a phone browser it is responsive already; the grids collapse and
`FlowBoard` stacks below `lg`.

**Does not work as-is** — React Native and Expo, SwiftUI, Jetpack Compose. There
is no DOM there, so `div`/`span`/`img`/`button`/`input` and the class strings
have nothing to attach to.

### What a React Native port would actually take

Not a rewrite, but not a find-and-replace either. Six things, and only the first
is solved for you:

1. **Tokens.** NativeWind v4 supports CSS variables through its `vars()`
   function, with normal inheritance down the tree — so the token contract
   survives. `tokens.css` becomes a JS object passed to `vars()` at the root
   rather than a stylesheet.
2. **Elements.** `div`→`View`, `span`/`p`→`Text`, `img`→`Image`,
   `button`→`Pressable`, `input`/`textarea`→`TextInput`. Mechanical, and every
   component needs it.
3. **The glass.** There is no `backdrop-filter` in React Native. `GlassPanel`
   has to wrap `expo-blur`'s `BlurView`, which is a component rather than a
   style — so the panel's structure changes, not just its props.
4. **Overlays.** No `position: fixed`. `StageOverlay`, `Popover` and `Lightbox`
   become `Modal`.
5. **SVG and gradients.** `ProgressRing` and the fallback glyphs need
   `react-native-svg`; `PillButton`'s accent needs `expo-linear-gradient`.
6. **Lists.** `loading="lazy"` does nothing. `CardGrid` becomes a `FlatList`
   with windowing — same goal, different mechanism, and on mobile it matters
   more, not less.

### The part that is not mechanical

**There is no hover on a touch screen**, and several components put real
information there: `MediaCard`'s title and metadata, `Tooltip` entirely,
`PillButton`'s `hoverLabel`, every label in `Toolbar`.

Porting those means redesigning them, not translating them. Metadata moves under
the tile or into a long-press sheet; tooltips become visible labels or
disappear; `hoverLabel`'s cost-on-hover becomes a line under the button. A port
that maps hover onto tap ends up with a gallery where the first tap reveals the
caption and the second opens the item, which is worse than either.

So: the **tokens and the decisions** port cleanly to any platform. The
**components** are for the web.

## Branding it

Override in your own CSS, after the import:

```css
:root {
  --su-accent:      #d8a1f1;   /* the one colour that carries the brand   */
  --su-accent-ink:  #121317;   /* what sits ON the accent — must flip     */
  --su-accent-soft: rgb(216 161 241 / 0.14);
  --su-gradient:    linear-gradient(96deg, #ff989b, #d8a1f1);
}
```

Status colours (`--su-ok`, `--su-warn`, `--su-danger`) are deliberately separate
from the accent. A brand that happens to be red must not make every panel look
like an error.

Full token reference, including the surface/text ramps and the light-ground
overrides: **`references/tokens.md`**.

## What is in the kit

Read **`references/components.md`** for props, states and usage notes on each.
Read **`references/recipes.md`** for the four screens these compose into.

| | |
|---|---|
| **primitives.tsx** | `GlassPanel` `IconButton` `PillButton` `Segmented` `StatusChip` `StepMarker` `ProgressRing` `Tooltip` `Popover` `Slider` `Field` `TextArea` `useMeasure` |
| **flow.tsx** | `FlowBoard` `FlowNode` `Connector` — a pipeline drawn as its stages |
| **gallery.tsx** | `MediaCard` `CardGrid` `Thumb` `EmptyState` `ShelfTabs` `SearchField` `HistoryStrip` `DropZone` `Lightbox` |
| **workspace.tsx** | `Toolbar` `InfoPanel` `Notice` `StatusPill` `StageHeader` `ModeRail` `StageOverlay` |

## Seeing it

`assets/demo.tsx` renders every component in every state on one page.

```tsx
import './studio-ui/tokens.css';
import { Demo } from './studio-ui/demo';
createRoot(el).render(<Demo />);
```

Mount it **after rebranding**. A kit this size has too many states to check by
reading, and the failure mode of a token swap is never a crash — it is one
panel that went unreadable, which you only find by looking at all of them at
once.

## The decisions worth understanding

These are the parts where the kit is opinionated, and the reasons matter more
than the components — if you build something new for one of these apps, build
it to agree with them.

### A long job is a row of stages, not a progress bar

One bar covering a multi-model job tells the user nothing they can act on: not
which stage is slow, not which one failed, not what the machine decided on
their behalf along the way. `FlowBoard` splits it, and that buys three things:

- failure is attributed to a **stage**, not to "the job"
- a retry starts **from** that stage, so the expensive stages before it are not
  paid for twice
- intermediate artefacts become visible and, where it makes sense, **editable**

That last one is the big one. A generated prompt you can correct before it is
rendered is a different product from one you watch scroll past. `FlowNode` takes
an `onEdit` and turns its text into a committed draft — and note that *where an
edit re-enters the pipeline is a product decision, not a UI one*: editing the
user's own words should re-run the step that interprets them, while editing a
generated value should skip that step and use the value verbatim. Wire those to
different entry points or the edit is cosmetic.

### The gallery's real constraint is memory, not looks

A grid of generated media is dozens of full-size images a browser will happily
decode all at once. Three consequences, all built in:

- `Thumb` sets `loading="lazy"` and `decoding="async"`. One line; the single
  biggest performance decision in the kit.
- `MediaCard` fixes an aspect ratio, so nothing reflows as images land.
- A viewer is `StageOverlay` — **a page, not a modal**. Opening a canvas over a
  still-mounted grid keeps every thumbnail decoded and every canvas running
  behind it. Unmount the grid and render the stage instead.

### Metadata hides until hover

A grid of generated work is looked at before it is read. Captions on every tile
turn a gallery into a spreadsheet. `MediaCard` puts title and meta behind hover
and reserves `badges` for the few things that must survive without it — state,
counts, a lock.

### One control, one meaning

`PillButton` fills itself with `progress` rather than growing a bar underneath,
because a separate bar says the same thing twice and shifts the layout when it
appears. It swaps its label on hover via `hoverLabel` — good for the cost or the
shortcut of what you are about to do, which matters at the moment of committing
and is noise before it. And `busy` replaces the label outright, because a button
still reading "Generate" while generating invites a second click.

### Three radii, one easing

`--su-radius-lg` for the outer shell, `-md` for panels inside it, `-sm` for the
things inside those. Mixing more than three is what makes an interface feel
assembled rather than designed. Same for motion: one curve
(`cubic-bezier(.16,1,.3,1)`, which decelerates hard and reads as *settling*)
and three durations.

### Empty states name the next action

"No items" tells the user what they can already see. `EmptyState`'s `hint` is
for the specific thing to do about it — "Drop an image above, or pick one from
the gallery."

## Extending it

When you need something the kit does not have, compose from `GlassPanel` and the
primitives rather than starting from a bare `div` — that is what keeps a new
panel looking like it belongs. Two habits to keep:

- reach for a token, never a hex value; if no token fits, add one to
  `tokens.css` with a semantic name (`--su-surface-4`, not `--su-grey-800`)
- pass icons in, do not import them

And a check worth running on anything new: does it still read correctly with
`--su-accent` set to plain grey? If it does not, the component is leaning on
colour to carry meaning that should be carried by position, weight, or a label.
