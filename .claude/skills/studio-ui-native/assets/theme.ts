import React, { createContext, useContext, useMemo } from 'react';
import { Platform, type TextStyle, type ViewStyle } from 'react-native';

/* ===========================================================================
 * studio-ui-native — theme
 *
 * The same token contract as the web kit, in the only form React Native can
 * consume: a plain object behind a context, rather than CSS variables.
 *
 * The NAMES are identical to `--su-*` on the web on purpose. When the two apps
 * are the same product, a designer changing "accent" should change one word in
 * two files and be done — not translate between two vocabularies and discover
 * six months later that mobile's "surface2" means something else.
 *
 * ACHROMATIC BY DEFAULT, same as the web kit. Greys on a dark ground, so the
 * kit never smuggles someone else's brand into a project. You add the colour by
 * passing a partial theme to the provider.
 * ========================================================================= */

export interface Theme {
  /* --- the ground --------------------------------------------------- */
  bg: string;
  bgRaised: string;
  bgSunken: string;

  /* Surfaces are translucent whites over `bg`, exactly as on the web, so one
     set of values works over any backdrop — a gradient, a photo, a blur. */
  surface1: string;
  surface2: string;
  surface3: string;
  surfaceSunk: string;

  border: string;
  borderStrong: string;
  borderFocus: string;

  /* --- text --------------------------------------------------------- */
  text: string;
  textDim: string;
  textFaint: string;
  textGhost: string;

  /* --- the paint (override these) ----------------------------------- */
  accent: string;
  /** What sits ON the accent. Flips when the accent goes light or dark. */
  accentInk: string;
  accentSoft: string;

  /* Status stays separate from the brand: a red brand must not make every
     panel look like an error. */
  ok: string; okSoft: string;
  warn: string; warnSoft: string;
  danger: string; dangerSoft: string;
  busy: string; busySoft: string;

  /* --- shape -------------------------------------------------------- */
  radiusLg: number;
  radiusMd: number;
  radiusSm: number;
  radiusPill: number;

  /* --- rhythm ------------------------------------------------------- */
  /* A 4pt scale. Mobile has less room than the web and more need for a
     consistent beat; hardcoded margins are what make a scrolling screen feel
     assembled out of unrelated cards. */
  space: (n: number) => number;

  /* --- motion ------------------------------------------------------- */
  fast: number;
  base: number;
  slow: number;

  /* --- touch -------------------------------------------------------- */
  /**
   * Minimum hit target. 44 is Apple's floor and 48dp is Google's; the kit uses
   * 44 as the number and grows targets with hitSlop rather than with visible
   * padding, so a control can look small and still be reliably tappable.
   */
  tap: number;
}

const DARK: Theme = {
  bg: '#121317',
  bgRaised: '#17181c',
  bgSunken: '#0d0e11',

  surface1: 'rgba(255,255,255,0.03)',
  surface2: 'rgba(255,255,255,0.06)',
  surface3: 'rgba(255,255,255,0.10)',
  surfaceSunk: 'rgba(0,0,0,0.25)',

  border: 'rgba(255,255,255,0.08)',
  borderStrong: 'rgba(255,255,255,0.20)',
  borderFocus: 'rgba(255,255,255,0.45)',

  text: '#ffffff',
  textDim: '#cfcfcf',
  textFaint: '#9c9c9c',
  textGhost: '#6b6b6b',

  accent: '#e8e8ea',
  accentInk: '#121317',
  accentSoft: 'rgba(255,255,255,0.12)',

  ok: '#a9d8b8', okSoft: 'rgba(169,216,184,0.14)',
  warn: '#e8d5a8', warnSoft: 'rgba(232,213,168,0.14)',
  danger: '#e2a8a8', dangerSoft: 'rgba(226,168,168,0.14)',
  busy: '#e8e8ea', busySoft: 'rgba(255,255,255,0.12)',

  radiusLg: 24,
  radiusMd: 18,
  radiusSm: 12,
  radiusPill: 999,

  space: (n: number) => n * 4,

  fast: 150,
  base: 260,
  slow: 600,

  tap: 44,
};

const LIGHT: Theme = {
  ...DARK,
  bg: '#f6f6f7',
  bgRaised: '#ffffff',
  bgSunken: '#ececee',

  surface1: 'rgba(0,0,0,0.03)',
  surface2: 'rgba(0,0,0,0.06)',
  surface3: 'rgba(0,0,0,0.10)',
  surfaceSunk: 'rgba(0,0,0,0.05)',

  border: 'rgba(0,0,0,0.10)',
  borderStrong: 'rgba(0,0,0,0.22)',
  borderFocus: 'rgba(0,0,0,0.45)',

  text: '#101012',
  textDim: '#3d3d42',
  textFaint: '#6b6b72',
  textGhost: '#9a9aa2',

  accent: '#2a2a30',
  accentInk: '#ffffff',
  accentSoft: 'rgba(0,0,0,0.08)',
};

export const themes = { dark: DARK, light: LIGHT };

const ThemeCtx = createContext<Theme>(DARK);

/**
 * Wrap the app once.
 *
 * `overrides` is where the brand goes, and it is deliberately a partial: a
 * project should be able to state the four or five values that make it itself
 * and inherit everything structural.
 *
 *   <ThemeProvider scheme={colorScheme ?? 'dark'} overrides={{
 *     accent: '#d8a1f1', accentInk: '#121317',
 *     accentSoft: 'rgba(216,161,241,0.14)',
 *   }}>
 */
export const ThemeProvider: React.FC<{
  children: React.ReactNode;
  scheme?: 'dark' | 'light';
  overrides?: Partial<Theme>;
}> = ({ children, scheme = 'dark', overrides }) => {
  const value = useMemo(
    () => ({ ...themes[scheme], ...overrides }),
    [scheme, overrides],
  );
  return React.createElement(ThemeCtx.Provider, { value }, children);
};

export const useTheme = () => useContext(ThemeCtx);

/* ------------------------------------------------------------------ type ---
 * One type ramp, so a screen assembled from five components still reads as one
 * screen. Sizes are a little larger than the web kit's: 11px is fine on a
 * monitor at arm's length and is a squint on a phone.
 */
export const type = {
  title: { fontSize: 22, fontWeight: '600' } as TextStyle,
  heading: { fontSize: 17, fontWeight: '600' } as TextStyle,
  body: { fontSize: 15, fontWeight: '400' } as TextStyle,
  label: { fontSize: 13, fontWeight: '500' } as TextStyle,
  caption: { fontSize: 12, fontWeight: '400' } as TextStyle,
  micro: { fontSize: 11, fontWeight: '600', letterSpacing: 1.2, textTransform: 'uppercase' } as TextStyle,
  mono: {
    fontSize: 12,
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
  } as TextStyle,
};

/* ------------------------------------------------------------- elevation ---
 * iOS draws shadows from shadowColor/Offset/Opacity/Radius; Android ignores all
 * of those and reads `elevation`, which also controls z-ordering. Getting one
 * and not the other is the single most common way an RN interface looks right
 * on the reviewer's phone and flat on half the users'.
 *
 * Android's elevation additionally paints an opaque background behind the view,
 * so it fights translucent surfaces — which is why `lift` is used sparingly
 * here and never on a glass panel that is meant to show what is behind it.
 */
export const elevation = (level: 0 | 1 | 2 | 3): ViewStyle => {
  if (level === 0) return {};
  const ios = {
    1: { shadowOpacity: 0.18, shadowRadius: 6, shadowOffset: { width: 0, height: 2 } },
    2: { shadowOpacity: 0.28, shadowRadius: 14, shadowOffset: { width: 0, height: 6 } },
    3: { shadowOpacity: 0.4, shadowRadius: 28, shadowOffset: { width: 0, height: 14 } },
  }[level];
  return Platform.select<ViewStyle>({
    ios: { shadowColor: '#000', ...ios },
    android: { elevation: level * 4 },
    default: {},
  })!;
};

/* ------------------------------------------------------------------ tone ---
 * The five states, mapped to their colours in one place so every component
 * agrees. `idle` is "not yet", never "disabled".
 */
export type Status = 'idle' | 'busy' | 'ok' | 'warn' | 'danger';

export const tone = (t: Theme, s: Status) => ({
  idle: { fg: t.textGhost, bg: t.surface2, line: t.border },
  busy: { fg: t.busy, bg: t.busySoft, line: t.busy },
  ok: { fg: t.ok, bg: t.okSoft, line: t.ok },
  warn: { fg: t.warn, bg: t.warnSoft, line: t.warn },
  danger: { fg: t.danger, bg: t.dangerSoft, line: t.danger },
}[s]);
