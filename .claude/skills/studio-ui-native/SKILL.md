---
name: studio-ui-native
description: A React Native UI kit for iOS and Android, built for creative and generative apps — touch-first, colour-agnostic, and dependency-free beyond react-native itself. Ships stage-by-stage pipeline boards with per-step retry and editable values, memory-safe media grids on FlatList windowing, bottom sheets, image picker tiles, viewer chrome with safe-area handling, and the primitives under them — panels, pill buttons with inline progress, segmented controls, sliders, status chips, notices. Use it when building or restyling any React Native or Expo screen, an iOS or Android app for an AI or generative product, a media gallery, a pipeline view, or a mobile companion to a web tool — and whenever someone asks for mobile components, a native design system, or how to make an RN screen look designed rather than default. It is the mobile sibling of the studio-ui web kit and shares its token names exactly, so one product can ship both and stay one product.
---

# studio-ui-native

The mobile sibling of **studio-ui**. Same design language, same token names,
rebuilt for touch.

This is not a port. Roughly half the components changed shape, because the web
kit leans on three things a phone does not have — hover, a pointer, and room —
and pretending otherwise produces an app that looks like a website in a
WebView. What carried over unchanged is the part worth carrying: the token
contract, and the reasoning.

## Three rules

**1. No colour literals.** Everything comes off `useTheme()`. The kit ships
achromatic — greys on a dark ground — so it never smuggles another product's
brand into yours. You add the colour with a partial theme.

**2. No dependencies beyond `react-native`.** Not Expo, not NativeWind, not
`react-native-svg`. Blur, gradients and safe-area insets arrive as *props*, so
the kit drops into a bare RN app and into an Expo app equally. `ProgressRing` is
built from two rotated half-discs rather than SVG for exactly this reason.

**3. Touch, not pointer.** Nothing hides behind a hover, because there is none.
Hit targets are 44pt minimum, grown with `hitSlop` rather than padding. Press
feedback is always visible — with no cursor, a control that does not react to
touch reads as broken and gets tapped again.

## Install

Copy `assets/` into the project (e.g. `src/studio-ui/`), wrap the app once:

```tsx
import { ThemeProvider } from './studio-ui/theme';

<ThemeProvider scheme="dark" overrides={{
  accent: '#d8a1f1',
  accentInk: '#121317',
  accentSoft: 'rgba(216,161,241,0.14)',
}}>
  <App />
</ThemeProvider>
```

Then `import { MediaGrid, FlowBoard, PillButton } from './studio-ui'`.

That is the whole install. No babel plugin, no metro config, no content globs —
the web kit's one silent failure mode does not exist here.

**Optional peers**, each wired through a prop rather than an import:

| package | what it upgrades |
|---|---|
| `react-native-safe-area-context` | pass `useSafeAreaInsets()` as `insets` to `Screen` / `Toolbar` / `Stage` |
| `expo-blur` | pass `BlurView` as `blurComponent` to `GlassPanel` — **iOS only, see below** |
| `expo-linear-gradient` | pass `LinearGradient` as `gradientComponent` to `PillButton` |
| `expo-image-picker` | wire your own picker to `ImagePickerTile`'s callbacks |

## iOS and Android

They disagree about shadows, safe areas, the back button, blur cost, dashed
borders, `TextInput` padding, press feedback and fonts — and almost none of it
raises an error. It just looks right on the machine you built on and wrong on
the other one.

**Read `references/platform.md` before shipping.** The short version:

- **Shadows.** iOS reads `shadowColor`/`Offset`/`Opacity`/`Radius`; Android
  reads `elevation` and ignores the rest. `elevation(level)` sets both. On
  Android `elevation` also controls z-order *and* paints an opaque background,
  so it fights translucency.
- **Blur is nearly free on iOS and expensive on Android.**
  `blurComponent={Platform.OS === 'ios' ? BlurView : undefined}` is the
  defensible default, and the kit is built to make it easy.
- **Android's back button fires whether you handle it or not.** An overlay that
  ignores it gets dismissed along with the screen under it. `Sheet` handles this;
  anything you build alongside needs to as well.
- **Test on a mid-range Android phone.** Every difference degrades in the same
  direction, so what is good there is almost always fine on iOS. The reverse is
  not true.

## What is in the kit

`references/components.md` for props and states. `references/recipes.md` for
whole screens.

| | |
|---|---|
| **primitives** | `GlassPanel` `IconButton` `PillButton` `Segmented` `StatusChip` `StepMarker` `ProgressRing` `Slider` `Field` `Divider` `useFadeIn` |
| **feedback** | `Sheet` `Hint` `Notice` `StatusPill` `Lightbox` |
| **flow** | `FlowBoard` `FlowNode` `Connector` |
| **gallery** | `MediaCard` `MediaGrid` `Thumb` `EmptyState` `ShelfTabs` `SearchField` `HistoryStrip` `ImagePickerTile` |
| **workspace** | `Screen` `ScreenHeader` `Toolbar` `InfoPanel` `ModeTabs` `Stage` |

## What changed from the web kit, and why

The interesting part. Each of these is a redesign, not a translation.

### Popover and Tooltip both became a bottom sheet

Anchoring a panel beside its trigger assumes room beside the trigger and a
cursor to aim with. Neither exists. The reachable area on a phone is the bottom
third of the screen, which is why every native picker lives there — so `Popover`
became `Sheet`, and `Tooltip` became `Hint`: a small (i) that opens the same
sheet.

`Hint` is deliberately a little inconvenient. If a control needs one to be
understandable, that is worth noticing rather than papering over — on a phone
the label usually belongs in the interface, visible.

### The flow board turned ninety degrees

Four stages across a 390pt screen is four unreadable slivers, so `FlowBoard`
runs **down** by default and only goes horizontal above ~700pt of width. The
breakpoint is width rather than `Platform.isPad`, because a phone in landscape
and a split-screen tablet are both real and both decided by actual room.

A vertical list of stages is arguably the more honest picture of a sequence
anyway, and it scrolls the way a phone already wants to.

### Card metadata came out of hiding

The web card hides its title and meta until hover. There is no hover, and the
reason for hiding them was desktop-specific — at desktop scale, captions on
every tile turn a gallery into a spreadsheet. At phone scale, with two columns,
a permanently readable caption is simply better. Secondary actions moved to
`onLongPress`, which is the native idiom and does not compete with the tap.

### `hoverLabel` became `subLabel`

The web kit hides the price of an action behind a hover, revealed at the moment
of committing. On a phone it just goes under the title, where it is visible
before the tap — which is where it should probably have been all along.

### The toolbar moved to the bottom and grew labels

A vertical icon rail down the right edge is a desktop shape; one-handed, the top
half of it is unreachable. `Toolbar` is horizontal and bottom-pinned, and
**every item is labelled** — the web version leans on tooltips and there are
none here, so an unlabelled icon is not merely unhelpful, it is unusable.

### The grid became a FlatList

Same concern as the web kit's lazy decoding, sharper mechanism. Windowing
*unmounts* off-screen rows rather than deferring their decode, and the windowing
props are set conservatively because generated images are large and a phone gets
killed by the OS rather than swapping. `MediaGrid` also derives its column count
from available width, so one screen serves phone and tablet.

## Extending it

Compose from `GlassPanel` and the primitives rather than a bare `View` — that is
what keeps a new panel looking like it belongs. Three habits:

- take colours from `useTheme()`, never a literal; add a token if none fits
- take icons, insets, blur and gradients as **props**, never imports
- give every `Pressable` an `accessibilityRole` and `accessibilityLabel`, and
  check the target is at least 44pt including `hitSlop`

And the same check as the web kit: does it still read correctly with `accent`
left at its achromatic default? If not, the component is leaning on colour to
carry meaning that position, weight or a label should be carrying.
