import React, { useRef, useState } from 'react';
import {
  ActivityIndicator, Animated, PanResponder, Platform, Pressable, StyleSheet, Text,
  TextInput, View,
  type LayoutChangeEvent, type StyleProp, type TextStyle, type ViewStyle,
} from 'react-native';
import { elevation, tone, type, useTheme, type Status, type Theme } from '../theme';

/* ===========================================================================
 * studio-ui-native — primitives
 *
 * Three rules, and the third is the one that makes this a different kit from
 * its web sibling rather than a translation of it.
 *
 *   1. No colour literals. Everything comes off the theme via useTheme().
 *   2. No dependencies beyond react-native. Icons arrive as ReactNode; blur and
 *      gradients arrive as optional render props. A project on bare RN with no
 *      Expo modules can use every component here.
 *   3. TOUCH, NOT POINTER. There is no hover, so nothing hides behind one. Hit
 *      targets are 44pt minimum. Press feedback is immediate and visible,
 *      because a phone has no cursor to tell you the tap registered.
 * ========================================================================= */

/* ------------------------------------------------------------------ Glass */

export type Surface = 1 | 2 | 3 | 'sunk';
export type Radius = 'sm' | 'md' | 'lg' | 'pill';

const surfaceOf = (t: Theme, s: Surface) =>
  s === 'sunk' ? t.surfaceSunk : s === 1 ? t.surface1 : s === 2 ? t.surface2 : t.surface3;

const radiusOf = (t: Theme, r: Radius) =>
  r === 'sm' ? t.radiusSm : r === 'md' ? t.radiusMd : r === 'lg' ? t.radiusLg : t.radiusPill;

/**
 * The base surface.
 *
 * On the web this is `backdrop-filter: blur()`. React Native has no such style,
 * and the honest default is a translucent fill rather than a fake: it reads
 * correctly, costs nothing, and looks the same on both platforms.
 *
 * If the project has `expo-blur`, pass its BlurView in as `blurComponent` and
 * the panel becomes real glass. That is a prop rather than an import because a
 * kit that hard-requires an Expo module cannot be used in a bare RN app — and
 * because blur is genuinely expensive on Android, where you often want it off
 * even when it is available. See references/platform.md.
 */
export const GlassPanel: React.FC<{
  children?: React.ReactNode;
  surface?: Surface;
  radius?: Radius;
  bordered?: boolean;
  dashed?: boolean;
  lift?: 0 | 1 | 2 | 3;
  /** e.g. `BlurView` from expo-blur. Rendered behind the content when given. */
  blurComponent?: React.ComponentType<{ intensity?: number; tint?: string; style?: StyleProp<ViewStyle> }>;
  blurIntensity?: number;
  style?: StyleProp<ViewStyle>;
}> = ({
  children, surface = 1, radius = 'md', bordered = true, dashed,
  lift = 0, blurComponent: Blur, blurIntensity = 40, style,
}) => {
  const t = useTheme();
  return (
    <View
      style={[
        {
          backgroundColor: surfaceOf(t, surface),
          borderRadius: radiusOf(t, radius),
          overflow: 'hidden',
        },
        bordered && {
          borderWidth: StyleSheet.hairlineWidth * 2,
          borderColor: t.border,
          borderStyle: dashed ? 'dashed' : 'solid',
        },
        elevation(lift),
        style,
      ]}
    >
      {Blur && <Blur intensity={blurIntensity} tint="dark" style={StyleSheet.absoluteFill} />}
      {children}
    </View>
  );
};

/* -------------------------------------------------------------- IconButton */

/**
 * Icon control.
 *
 * `hitSlop` grows the touch area beyond the visual one, which is how a 28pt
 * icon stays comfortably tappable without a 44pt box of empty space around it.
 * Getting this wrong is the most common reason a nice-looking RN toolbar feels
 * broken in the hand.
 */
export const IconButton: React.FC<{
  children: React.ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
  label: string;
  active?: boolean;
  disabled?: boolean;
  size?: number;
  tone?: 'default' | 'danger';
  style?: StyleProp<ViewStyle>;
}> = ({ children, onPress, onLongPress, label, active, disabled, size = 36, tone: kind = 'default', style }) => {
  const t = useTheme();
  const slop = Math.max(0, (t.tap - size) / 2);
  return (
    <Pressable
      onPress={onPress}
      onLongPress={onLongPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ selected: active, disabled }}
      hitSlop={{ top: slop, bottom: slop, left: slop, right: slop }}
      style={({ pressed }) => [
        {
          width: size, height: size, borderRadius: t.radiusPill,
          alignItems: 'center', justifyContent: 'center',
          backgroundColor: active ? t.surface3 : pressed ? t.surface2 : 'transparent',
          opacity: disabled ? 0.4 : 1,
        },
        style,
      ]}
    >
      <View style={{ opacity: disabled ? 0.6 : 1 }}>
        {React.isValidElement(children)
          ? React.cloneElement(children as React.ReactElement<{ color?: string }>, {
              color: kind === 'danger' ? t.danger : active ? t.text : t.textFaint,
            })
          : children}
      </View>
    </Pressable>
  );
};

/* -------------------------------------------------------------- PillButton */

/**
 * The primary action.
 *
 * Two differences from the web kit, both forced by touch:
 *
 *   - `hoverLabel` becomes `subLabel`, rendered under the title. The price of
 *     what you are about to do cannot live behind a hover on a phone, and it is
 *     exactly the information a user wants before committing.
 *   - press feedback is explicit. With no cursor and no :hover, a button that
 *     does not visibly react to touch reads as broken, and the user taps again.
 */
export const PillButton: React.FC<{
  title: string;
  subLabel?: string;
  onPress?: () => void;
  variant?: 'accent' | 'solid' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
  disabled?: boolean;
  busy?: boolean;
  busyLabel?: string;
  /** 0–100. Fills the button from the left — the button IS the progress bar. */
  progress?: number;
  icon?: React.ReactNode;
  /** e.g. LinearGradient from expo-linear-gradient, for the accent variant. */
  gradientComponent?: React.ComponentType<{ colors: string[]; start?: { x: number; y: number }; end?: { x: number; y: number }; style?: StyleProp<ViewStyle> }>;
  gradientColors?: string[];
  style?: StyleProp<ViewStyle>;
}> = ({
  title, subLabel, onPress, variant = 'ghost', size = 'md', disabled, busy,
  busyLabel, progress, icon, gradientComponent: Gradient, gradientColors, style,
}) => {
  const t = useTheme();
  const H = { sm: 36, md: 46, lg: 56 }[size];
  const fg = variant === 'accent' ? t.accentInk : variant === 'solid' ? t.bg : t.text;
  const bg = variant === 'accent' ? t.accent : variant === 'solid' ? t.text : t.surface1;

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || busy}
      accessibilityRole="button"
      accessibilityLabel={subLabel ? `${title}, ${subLabel}` : title}
      accessibilityState={{ disabled: !!disabled, busy: !!busy }}
      style={({ pressed }) => [
        {
          minHeight: H,
          paddingHorizontal: t.space(5),
          paddingVertical: t.space(2),
          borderRadius: t.radiusPill,
          alignItems: 'center',
          justifyContent: 'center',
          flexDirection: 'row',
          overflow: 'hidden',
          backgroundColor: bg,
          borderWidth: variant === 'ghost' ? StyleSheet.hairlineWidth * 2 : 0,
          borderColor: t.border,
          opacity: disabled ? 0.45 : 1,
          transform: [{ scale: pressed ? 0.985 : 1 }],
        },
        style,
      ]}
    >
      {variant === 'accent' && Gradient && (
        <Gradient
          colors={gradientColors ?? [t.accent, t.accent]}
          start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }}
          style={StyleSheet.absoluteFill}
        />
      )}
      {progress != null && !busy && (
        <View
          style={[
            StyleSheet.absoluteFill,
            { backgroundColor: t.surface3, right: `${100 - Math.max(0, Math.min(100, progress))}%` },
          ]}
        />
      )}

      {busy ? (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          <ActivityIndicator size="small" color={fg} />
          <Text style={[type.label, { color: fg }]}>{busyLabel ?? title}</Text>
        </View>
      ) : (
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
          {icon}
          <View>
            <Text style={[type.label, { color: fg, fontWeight: '700', textAlign: 'center' }]}>{title}</Text>
            {subLabel && (
              <Text style={[type.caption, { color: fg, opacity: 0.65, textAlign: 'center' }]}>{subLabel}</Text>
            )}
          </View>
        </View>
      )}
    </Pressable>
  );
};

/* --------------------------------------------------------------- Segmented */

/**
 * Mutually exclusive choice.
 *
 * Caps at three options on a phone. A four-way segmented control at 375pt gives
 * each option about 80pt, which truncates any label worth reading — past three,
 * use a Sheet with a list.
 */
export function Segmented<T extends string | number | boolean>({
  options, value, onChange, style,
}: {
  options: { value: T; label: string; icon?: React.ReactNode; disabled?: boolean }[];
  value: T;
  onChange: (v: T) => void;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  return (
    <View
      accessibilityRole="tablist"
      style={[
        {
          flexDirection: 'row', alignSelf: 'flex-start', padding: 3, gap: 2,
          borderRadius: t.radiusPill, backgroundColor: t.surface1,
          borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border,
        },
        style,
      ]}
    >
      {options.map((o) => {
        const active = value === o.value;
        return (
          <Pressable
            key={String(o.value)}
            onPress={() => !o.disabled && onChange(o.value)}
            disabled={o.disabled}
            accessibilityRole="tab"
            accessibilityState={{ selected: active, disabled: o.disabled }}
            style={{
              flexDirection: 'row', alignItems: 'center', gap: 6,
              minHeight: 34, paddingHorizontal: t.space(3.5),
              borderRadius: t.radiusPill,
              backgroundColor: active ? t.text : 'transparent',
              opacity: o.disabled ? 0.45 : 1,
            }}
          >
            {o.icon}
            <Text
              style={[
                type.label,
                { color: active ? t.bg : t.textFaint, fontWeight: active ? '700' : '500' },
              ]}
            >
              {o.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

/* --------------------------------------------------- StatusChip / StepMarker */

export const StatusChip: React.FC<{
  status: Status; label: string; icon?: React.ReactNode; style?: StyleProp<ViewStyle>;
}> = ({ status, label, icon, style }) => {
  const t = useTheme();
  const c = tone(t, status);
  return (
    <View
      style={[
        {
          flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start',
          paddingHorizontal: t.space(2), paddingVertical: t.space(1),
          borderRadius: t.radiusPill, backgroundColor: c.bg,
        },
        style,
      ]}
    >
      {icon}
      <Text style={[type.caption, { color: c.fg, fontWeight: '700' }]}>{label}</Text>
    </View>
  );
};

/**
 * The numbered dot on a step. Shows its number only while idle — once something
 * has happened to a step, what happened matters more than where it sits, and
 * the position is already obvious from the layout.
 */
export const StepMarker: React.FC<{
  index: number; status: Status; size?: number;
  icons?: Partial<Record<'busy' | 'ok' | 'warn' | 'danger', React.ReactNode>>;
}> = ({ index, status, size = 24, icons }) => {
  const t = useTheme();
  const c = tone(t, status);
  const glyph = status === 'idle' ? null : icons?.[status];
  return (
    <View
      style={{
        width: size, height: size, borderRadius: t.radiusPill,
        alignItems: 'center', justifyContent: 'center',
        borderWidth: 1.5, borderColor: c.line,
      }}
    >
      {glyph ?? (
        status === 'busy' && !icons?.busy
          ? <ActivityIndicator size="small" color={c.fg} />
          : <Text style={[type.caption, { color: c.fg, fontWeight: '700' }]}>{index}</Text>
      )}
    </View>
  );
};

/* ------------------------------------------------------------- ProgressRing */

/**
 * Determinate ring, built from two rotated half-discs.
 *
 * There is a shorter version of this using react-native-svg, and it is not
 * worth a dependency in a kit whose whole selling point is that it drops into
 * any React Native project. The trick: clip each half to its own side, rotate
 * the right half from 0-180 degrees for the first half of the value, then park
 * it and rotate the left half for the second.
 */
export const ProgressRing: React.FC<{
  value: number; size?: number; thickness?: number; color?: string; trackColor?: string;
}> = ({ value, size = 28, thickness = 3, color, trackColor }) => {
  const t = useTheme();
  const v = Math.max(0, Math.min(100, value));
  const fg = color ?? t.accent;
  const track = trackColor ?? t.border;
  const half = size / 2;

  const Disc = ({ side, deg }: { side: 'left' | 'right'; deg: number }) => (
    <View
      style={{
        position: 'absolute', width: half, height: size, overflow: 'hidden',
        [side]: 0,
      } as ViewStyle}
    >
      <View
        style={{
          width: half, height: size, borderRadius: half,
          borderWidth: thickness, borderColor: fg,
          [side === 'right' ? 'borderLeftColor' : 'borderRightColor']: 'transparent',
          [side === 'right' ? 'borderBottomColor' : 'borderTopColor']: 'transparent',
          transform: [{ rotate: `${deg}deg` }],
          ...(side === 'right' ? { marginLeft: 0 } : {}),
        } as ViewStyle}
      />
    </View>
  );

  return (
    <View
      accessibilityRole="progressbar"
      accessibilityValue={{ now: Math.round(v), min: 0, max: 100 }}
      style={{ width: size, height: size }}
    >
      <View
        style={{
          position: 'absolute', width: size, height: size, borderRadius: half,
          borderWidth: thickness, borderColor: track,
        }}
      />
      <Disc side="right" deg={-45 + Math.min(50, v) * 3.6} />
      {v > 50 && <Disc side="left" deg={-45 + (v - 50) * 3.6} />}
    </View>
  );
};

/* ------------------------------------------------------------------ Slider */

/**
 * Range control, on PanResponder rather than a community package.
 *
 * Two things it does that matter more on a phone than on a desktop:
 *
 *   - the readout is always visible. A slider with no number is unusable for
 *     anything you would want to reproduce or describe, and on mobile there is
 *     no tooltip to hide it in.
 *   - the thumb's touch area is `tap` tall regardless of how thin the track
 *     looks, because a 4pt track is a 4pt target otherwise.
 */
export const Slider: React.FC<{
  label: string;
  value: number;
  onChange: (v: number) => void;
  min?: number;
  max?: number;
  step?: number;
  format?: (v: number) => string;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
}> = ({ label, value, onChange, min = 0, max = 1, step = 0.01, format, disabled, style }) => {
  const t = useTheme();
  const [width, setWidth] = useState(0);
  const widthRef = useRef(0);
  const valueRef = useRef(value);
  valueRef.current = value;

  const clampToStep = (raw: number) => {
    const snapped = Math.round(raw / step) * step;
    return Math.max(min, Math.min(max, Number(snapped.toFixed(6))));
  };

  const responder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: (e) => {
        if (disabled || !widthRef.current) return;
        onChange(clampToStep(min + (e.nativeEvent.locationX / widthRef.current) * (max - min)));
      },
      onPanResponderMove: (_e, g) => {
        if (disabled || !widthRef.current) return;
        const start = ((valueRef.current - min) / (max - min)) * widthRef.current;
        onChange(clampToStep(min + ((start + g.dx) / widthRef.current) * (max - min)));
      },
    }),
  ).current;

  const pct = max === min ? 0 : ((value - min) / (max - min)) * 100;

  return (
    <View style={[{ opacity: disabled ? 0.5 : 1 }, style]}>
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <Text style={[type.micro, { color: t.textFaint }]}>{label}</Text>
        <Text style={[type.mono, { color: t.textDim }]}>
          {format ? format(value) : value.toFixed(2)}
        </Text>
      </View>

      <View
        {...(disabled ? {} : responder.panHandlers)}
        onLayout={(e: LayoutChangeEvent) => {
          widthRef.current = e.nativeEvent.layout.width;
          setWidth(e.nativeEvent.layout.width);
        }}
        accessibilityRole="adjustable"
        accessibilityLabel={label}
        accessibilityValue={{ now: value, min, max }}
        style={{ height: t.tap, justifyContent: 'center', marginTop: t.space(1) }}
      >
        <View style={{ height: 4, borderRadius: 2, backgroundColor: t.surface3 }}>
          <View style={{ width: `${pct}%`, height: 4, borderRadius: 2, backgroundColor: t.accent }} />
        </View>
        <View
          pointerEvents="none"
          style={{
            position: 'absolute',
            left: Math.max(0, (width * pct) / 100 - 9),
            width: 18, height: 18, borderRadius: 9, backgroundColor: t.text,
            ...elevation(1),
          }}
        />
      </View>
    </View>
  );
};

/* ------------------------------------------------------------ Field / Area */

export const Field: React.FC<{
  value: string;
  onChangeText: (v: string) => void;
  placeholder?: string;
  label?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
  multiline?: boolean;
  onSubmit?: () => void;
  autoFocus?: boolean;
  style?: StyleProp<ViewStyle>;
  inputStyle?: StyleProp<TextStyle>;
}> = ({
  value, onChangeText, placeholder, label, icon, action,
  multiline, onSubmit, autoFocus, style, inputStyle,
}) => {
  const t = useTheme();
  const [focused, setFocused] = useState(false);
  return (
    <View style={style}>
      {label && (
        <Text style={[type.micro, { color: t.textFaint, marginBottom: t.space(1.5) }]}>{label}</Text>
      )}
      <View
        style={{
          flexDirection: multiline ? 'column' : 'row',
          alignItems: multiline ? 'stretch' : 'center',
          gap: t.space(2),
          paddingHorizontal: t.space(3.5),
          paddingVertical: multiline ? t.space(3) : t.space(2),
          borderRadius: multiline ? t.radiusSm : t.radiusMd,
          backgroundColor: multiline ? t.surfaceSunk : t.surface1,
          borderWidth: StyleSheet.hairlineWidth * 2,
          borderColor: focused ? t.borderStrong : t.border,
        }}
      >
        {icon}
        <TextInput
          value={value}
          onChangeText={onChangeText}
          placeholder={placeholder}
          placeholderTextColor={t.textGhost}
          multiline={multiline}
          autoFocus={autoFocus}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          onSubmitEditing={onSubmit}
          returnKeyType={onSubmit ? 'go' : undefined}
          // Android adds its own vertical padding to TextInput and iOS does not,
          // which makes an otherwise identical field two different heights.
          style={[
            type.body,
            {
              flex: multiline ? undefined : 1,
              color: t.textDim,
              minHeight: multiline ? 96 : undefined,
              textAlignVertical: multiline ? 'top' : 'center',
              paddingVertical: Platform.OS === 'android' ? 0 : undefined,
            },
            inputStyle,
          ]}
        />
        {action}
      </View>
    </View>
  );
};

/* --------------------------------------------------------------- Divider */

export const Divider: React.FC<{ style?: StyleProp<ViewStyle> }> = ({ style }) => {
  const t = useTheme();
  return <View style={[{ height: StyleSheet.hairlineWidth, backgroundColor: t.border }, style]} />;
};

/* ------------------------------------------------------------ useFadeIn ---
 * Entrance animation on the JS-free driver, so it keeps running while the
 * bridge is busy — which, on a screen that just kicked off a job, it is. */
export function useFadeIn(deps: unknown[] = []) {
  const t = useTheme();
  const v = useRef(new Animated.Value(0)).current;
  React.useEffect(() => {
    v.setValue(0);
    Animated.timing(v, { toValue: 1, duration: t.base, useNativeDriver: true }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return {
    opacity: v,
    transform: [{ translateY: v.interpolate({ inputRange: [0, 1], outputRange: [8, 0] }) }],
  };
}
