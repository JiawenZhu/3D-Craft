# iOS and Android

One codebase, two platforms that disagree about a surprising number of things.
These are the disagreements the kit handles, and the ones it cannot handle for
you.

The pattern to notice: almost none of these produce an error. They produce an
app that looks right on the machine it was built on and wrong on the other one,
which is why they are worth reading before rather than after.

---

## Shadows

**iOS** draws from `shadowColor`, `shadowOffset`, `shadowOpacity`,
`shadowRadius`. **Android** ignores all four and reads `elevation`.

Set only the iOS props and every Android device renders your card flat. Set only
`elevation` and iOS renders it flat. `elevation(level)` in `theme.ts` sets both,
which is why nothing in the kit writes shadow styles directly.

Two Android-specific consequences that catch people:

- **`elevation` also controls z-order.** Two overlapping siblings on Android
  stack by elevation, not by source order. `Stage` gives a floating header
  `elevation: 4` for exactly this reason — without it a canvas rendered first
  can paint over a header rendered after it.
- **`elevation` paints an opaque background.** It fights translucency, so a
  glass panel with elevation stops showing what is behind it. The kit keeps
  `lift` off glass surfaces and uses it on sheets and floating bars, which are
  meant to be opaque anyway.

## Safe areas

A notch, a Dynamic Island, a punch-hole camera, a home indicator and a gesture
bar all take bites out of the screen, and the sizes differ per device.

Nothing in the kit hardcodes an inset. `Screen`, `Toolbar` and `Stage` take an
`insets` prop; pass `useSafeAreaInsets()` from
`react-native-safe-area-context` straight in:

```tsx
const insets = useSafeAreaInsets();
<Screen insets={insets}>…<Toolbar items={items} insets={insets} /></Screen>
```

The bottom inset is the one that bites. A toolbar flush to `bottom: 0` sits
under the iOS home indicator and under Android's gesture bar, where roughly the
bottom 20–34pt of it cannot be tapped at all. `Toolbar` takes
`max(space(2), insets.bottom)` for its bottom padding rather than adding them,
so it does not grow a gap on devices with a physical button.

## The Android back button

Android has a hardware/gesture back, and **it fires whether or not you handle
it**. An open sheet that does not intercept it gets dismissed *along with* the
screen underneath, because the default handler pops the navigation stack.

`Sheet` registers a `BackHandler` while visible and returns `true` to swallow
the press. Any other overlay you build needs the same three lines. `Modal`'s
`onRequestClose` covers the simple case, which is why the kit sets it too — but
`onRequestClose` is Android-only, so it is not a substitute for handling
dismissal properly on both.

## Blur

`GlassPanel` renders a translucent fill, not a blur, and takes an optional
`blurComponent`.

That default is not laziness. `expo-blur` on iOS maps to `UIVisualEffectView`
and is essentially free. On Android it is a much more expensive approximation,
it behaves differently across API levels, and on mid-range hardware a scrolling
list of blurred cards will drop frames. So:

```tsx
import { BlurView } from 'expo-blur';
<GlassPanel blurComponent={Platform.OS === 'ios' ? BlurView : undefined}>
```

Blur on iOS, honest translucency on Android, is a defensible product decision
and the one the kit is built to make easy. Blur everywhere is a decision to make
deliberately after testing on a cheap Android phone, not by default.

## Dashed borders

`borderStyle: 'dashed'` combined with `borderRadius` **does not render
correctly on Android** — depending on version you get a solid border, or
corners that ignore the radius.

`GlassPanel dashed` and `EmptyState` both use it, so on Android they degrade to
a solid hairline. That is acceptable — the border is still there and still
reads as an edge. If the dashed look matters to your design, draw it with an
SVG rect and `strokeDasharray` instead; there is no style-level fix.

## TextInput

Android adds its own vertical padding inside a `TextInput` and iOS does not, so
the same field is visibly taller on Android. `Field` sets
`paddingVertical: 0` on Android to bring them back into line.

Two more worth knowing when you build your own:

- `textAlignVertical: 'top'` is required for multiline on Android; iOS ignores
  it and does the right thing anyway.
- `clearButtonMode` is iOS-only. `SearchField` renders its own clear button so
  both platforms have one.

## Press feedback

iOS convention is opacity; Android's is a ripple. The kit uses opacity and scale
everywhere, which reads as correct on both but slightly non-native on Android.

If you want the platform-native feel, `Pressable` takes
`android_ripple={{ color, borderless }}`. It is a per-component decision — worth
it for list rows and toolbar buttons, less so for a card that already scales on
press.

## Type and fonts

`type.mono` resolves to Menlo on iOS and `monospace` on Android; there is no
font present on both. Anything else you add needs the same treatment, because a
missing font family on Android silently falls back to the system sans and your
monospaced numbers stop lining up.

Both platforms let users scale text system-wide, and the kit respects it —
`ScreenHeader`, `Toolbar` and `ModeTabs` cap the multiplier (1.2–1.4) because
they anchor a layout, while body copy is uncapped. Never cap at 1.0; that is
overriding an accessibility setting rather than accommodating it.

## Status bar

`Screen` sets `barStyle="light-content"` and a translucent background, which on
Android means content draws under the status bar and `insets.top` becomes
load-bearing. If your app is light-themed, change `barStyle` there — a dark
status bar on a dark ground is invisible on both platforms, and it is the kind
of thing nobody notices until a screenshot.

## Keyboard

Neither platform gets this for free. `KeyboardAvoidingView` needs
`behavior="padding"` on iOS and usually `behavior="height"` or nothing on
Android, where `windowSoftInputMode` in the manifest does most of the work.

The kit does not wrap anything in a `KeyboardAvoidingView` on purpose: the right
behaviour depends on the screen's own layout, and a component that guesses is
worse than one that leaves it to the screen. The generator recipe in
`recipes.md` shows the arrangement that works for a field pinned near the
bottom.

---

## What to test on, and why

If you only ever run one device, run **a mid-range Android phone**. Almost every
issue above degrades in the same direction — iOS gets the pretty path, Android
gets the flat, slow, or untappable one — so an app that is good on cheap Android
is nearly always fine on iOS, and the reverse is not true.
