# Token reference

Every colour, radius, blur and duration in the kit resolves through one of
these. The components are the shapes; this is the paint.

## The eight you override

Branding the kit is these, and only these:

```css
:root {
  --su-accent:        #d8a1f1;                          /* the brand         */
  --su-accent-ink:    #121317;                          /* what sits ON it   */
  --su-accent-soft:   rgb(216 161 241 / 0.14);          /* tinted background */
  --su-gradient:      linear-gradient(96deg, #ff989b, #d8a1f1);

  --su-ok:            #6ee7a8;
  --su-warn:          #ffd98e;
  --su-danger:        #f08a8a;
  --su-bg:            #121317;                          /* the ground        */
}
```

`--su-accent-ink` exists because what sits *on* the accent has to flip when the
accent goes light or dark. One variable cannot express that pairing, and
hardcoding white text on an accent is how a kit breaks the day someone picks a
pale yellow.

Each status colour has a `-soft` partner used for tinted backgrounds. If you
change a status hue, change its soft form to match or the tint will fight it.

## Surfaces

Translucent whites over `--su-bg`, not opaque greys. One set of values then
works over *any* backdrop — a gradient, a photo, an ambient glow — which is what
makes the glass look like glass instead of like flat panels.

| token | use |
|---|---|
| `--su-surface-1` | resting panel |
| `--su-surface-2` | hover, or a panel sitting on another |
| `--su-surface-3` | pressed / active |
| `--su-surface-sunk` | wells: inputs, image beds, anything you put things *into* |
| `--su-bg` / `-raised` / `-sunken` | opaque grounds, for full pages |

Because surfaces are alpha, stacking them compounds. Three nested
`--su-surface-1` panels are visibly lighter than one, which is usually a bug —
use `sunk` for the inner well rather than another translucent layer.

## Borders

| token | use |
|---|---|
| `--su-border` | default hairline |
| `--su-border-strong` | hover, scrollbar thumbs, secondary emphasis |
| `--su-border-focus` | selection and focus rings |

Borders do the structural work that colour would otherwise do. That is why the
achromatic default still reads as a designed interface: the hierarchy is in
surface, border and weight, and the accent only marks *what to look at next*.

## Text

Four steps, and a hierarchy rather than a gradient:

| token | use |
|---|---|
| `--su-text` | headings, active labels, values you must read |
| `--su-text-dim` | body |
| `--su-text-faint` | labels, metadata, uppercase micro-copy |
| `--su-text-ghost` | present but not asking to be read — hints, placeholders, counts |

Uppercase tracked-out labels can sit at `--su-text-faint` and stay legible; the
letterspacing buys back what the contrast gives up. That pairing is used
throughout `InfoPanel` and the flow headers.

## Shape

```
--su-radius-lg    28px   gallery cards, modal shells
--su-radius-md    20px   panels, node cards
--su-radius-sm    12px   image beds, inputs, wells
--su-radius-pill  999px  buttons, chips, tabs
```

Three radii used consistently. Mixing more is what makes an interface feel
assembled from parts rather than designed. The rule is nesting: outer shell
`lg`, panels inside it `md`, things inside those `sm`.

```
--su-blur         16px   the glass
--su-blur-heavy   24px   over busy content: modals, popovers
```

## Motion

```
--su-ease   cubic-bezier(0.16, 1, 0.3, 1)
--su-fast   180ms   hover, toggle
--su-base   300ms   entrance, layout
--su-slow   700ms   connector fills, image scale on hover
```

One curve for everything that enters. It decelerates hard, which reads as *the
interface is settling* rather than *the interface is animating* — the difference
between motion you stop noticing after a day and motion you start resenting.

Utility classes in `tokens.css`: `.su-rise`, `.su-pop`, `.su-spin`,
`.su-pulse`, plus `.su-scroll` for panel scrollbars (a default scrollbar on a
glass panel is the fastest way to make it stop looking designed).

All of it is disabled under `prefers-reduced-motion`. Nothing in the kit
conveys information that requires the animation to read.

## Light ground

`:root[data-theme='light']` flips the ground and the text ramp; the contract is
otherwise identical, so components need no changes. The kit is designed
dark-first because it is for tools where the work on screen is the bright thing
— but if your product is a document editor rather than a studio, the light
overrides are there.

## Adding a token

Name it for its **role**, never its value. There is no `--su-purple`, because
the day the brand stops being purple every component using it would start lying.
`--su-surface-4` is a fine addition; `--su-grey-800` is not.
