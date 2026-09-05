import React from 'react';
import {
  Platform, Pressable, ScrollView, StatusBar, StyleSheet, Text, View,
  type StyleProp, type ViewStyle,
} from 'react-native';
import { elevation, type, useTheme } from '../theme';
import { GlassPanel, IconButton } from './primitives';

/* ===========================================================================
 * studio-ui-native — workspace
 *
 * The chrome around a working canvas.
 *
 * Same governing rule as the web kit — the canvas is the product, the chrome is
 * not — with one addition that only exists on phones: SAFE AREAS. A notch, a
 * home indicator and a gesture bar all eat into the screen, and a header pinned
 * to y=0 sits under the clock while a toolbar pinned to the bottom sits under
 * the swipe-up bar and becomes untappable.
 *
 * The components here take `insets` as a prop rather than importing
 * react-native-safe-area-context, for the same reason nothing else in the kit
 * imports its dependencies: an app that already has a provider should not get a
 * second one, and an app without the package should still be able to use the
 * kit. Pass `useSafeAreaInsets()` straight in.
 * ========================================================================= */

export interface Insets { top: number; bottom: number; left: number; right: number }

const NO_INSETS: Insets = { top: 0, bottom: 0, left: 0, right: 0 };

/* ------------------------------------------------------------------ Screen */

/**
 * The page shell. Paints the ground and holds the top inset.
 *
 * `StatusBar` is set here rather than per-screen because a dark app with a dark
 * status bar needs light content in it, and forgetting that on one screen is
 * the kind of thing nobody notices until a user screenshots it.
 */
export const Screen: React.FC<{
  children: React.ReactNode;
  insets?: Insets;
  /** Skip the top inset when a full-bleed image or canvas runs under the notch. */
  edgeToEdge?: boolean;
  style?: StyleProp<ViewStyle>;
}> = ({ children, insets = NO_INSETS, edgeToEdge, style }) => {
  const t = useTheme();
  return (
    <View
      style={[
        {
          flex: 1,
          backgroundColor: t.bg,
          paddingTop: edgeToEdge ? 0 : insets.top,
          paddingLeft: insets.left,
          paddingRight: insets.right,
        },
        style,
      ]}
    >
      <StatusBar barStyle="light-content" backgroundColor="transparent" translucent />
      {children}
    </View>
  );
};

/* ------------------------------------------------------------ ScreenHeader */

/**
 * Title bar.
 *
 * The title is centred and the actions are pinned to the edges, so it stays
 * symmetric however many actions there are. `maxFontSizeMultiplier` is on the
 * title because a user with large text turned on will otherwise push a
 * two-line title into the content — respecting the setting matters, but a
 * header that grows without bound breaks the layout it anchors.
 */
export const ScreenHeader: React.FC<{
  title: string;
  subtitle?: string;
  onBack?: () => void;
  backIcon?: React.ReactNode;
  actions?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({ title, subtitle, onBack, backIcon, actions, style }) => {
  const t = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row', alignItems: 'center',
          minHeight: 52, paddingHorizontal: t.space(2),
        },
        style,
      ]}
    >
      <View style={{ width: 88, alignItems: 'flex-start' }}>
        {onBack && backIcon && (
          <IconButton label="Back" onPress={onBack}>{backIcon}</IconButton>
        )}
      </View>

      <View style={{ flex: 1, alignItems: 'center' }} pointerEvents="none">
        <Text
          numberOfLines={1}
          maxFontSizeMultiplier={1.4}
          accessibilityRole="header"
          style={[type.heading, { color: t.text }]}
        >
          {title}
        </Text>
        {subtitle && (
          <Text numberOfLines={1} maxFontSizeMultiplier={1.3} style={[type.caption, { color: t.textGhost }]}>
            {subtitle}
          </Text>
        )}
      </View>

      <View style={{ width: 88, flexDirection: 'row', justifyContent: 'flex-end', gap: t.space(1) }}>
        {actions}
      </View>
    </View>
  );
};

/* ----------------------------------------------------------------- Toolbar */

export interface ToolbarItem {
  id: string;
  icon: React.ReactNode;
  label: string;
  onPress?: () => void;
  active?: boolean;
  disabled?: boolean;
}

/**
 * A bar of tools, pinned to the bottom by default.
 *
 * Two deliberate departures from the web kit's vertical icon rail:
 *
 *   - IT IS HORIZONTAL AND AT THE BOTTOM, because that is the part of a phone
 *     screen a thumb reaches. A rail down the right edge is a desktop shape;
 *     on a phone the top half of it is unreachable one-handed.
 *   - EVERY ITEM IS LABELLED. The web version leans on tooltips, and there are
 *     no tooltips here. An icon whose meaning is not obvious and has no label
 *     is simply unusable — so the label is not optional, it is the fix.
 */
export const Toolbar: React.FC<{
  items: ToolbarItem[];
  insets?: Insets;
  floating?: boolean;
  style?: StyleProp<ViewStyle>;
}> = ({ items, insets = NO_INSETS, floating, style }) => {
  const t = useTheme();

  const body = (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-around',
        paddingTop: t.space(2),
        paddingBottom: floating ? t.space(2) : Math.max(t.space(2), insets.bottom),
        paddingHorizontal: t.space(2),
      }}
    >
      {items.map((item) => (
        <Pressable
          key={item.id}
          onPress={item.onPress}
          disabled={item.disabled}
          accessibilityRole="button"
          accessibilityLabel={item.label}
          accessibilityState={{ selected: item.active, disabled: item.disabled }}
          style={({ pressed }) => ({
            flex: 1,
            minHeight: t.tap,
            alignItems: 'center',
            justifyContent: 'center',
            gap: 3,
            borderRadius: t.radiusSm,
            opacity: item.disabled ? 0.4 : pressed ? 0.6 : 1,
            backgroundColor: item.active ? t.surface2 : 'transparent',
          })}
        >
          {item.icon}
          <Text
            numberOfLines={1}
            maxFontSizeMultiplier={1.2}
            style={{ fontSize: 10, fontWeight: '600', color: item.active ? t.text : t.textFaint }}
          >
            {item.label}
          </Text>
        </Pressable>
      ))}
    </View>
  );

  if (floating) {
    return (
      <GlassPanel
        radius="lg"
        lift={2}
        style={[
          { position: 'absolute', left: t.space(4), right: t.space(4), bottom: insets.bottom + t.space(4) },
          style,
        ]}
      >
        {body}
      </GlassPanel>
    );
  }

  return (
    <View
      style={[
        {
          backgroundColor: t.bgRaised,
          borderTopWidth: StyleSheet.hairlineWidth * 2,
          borderTopColor: t.border,
        },
        style,
      ]}
    >
      {body}
    </View>
  );
};

/* --------------------------------------------------------------- InfoPanel */

/**
 * Key/value readout.
 *
 * Values are monospaced and right-aligned so a column of numbers lines up.
 * `collapsible` exists because a phone screen cannot afford a permanent
 * ten-row stats panel over a canvas the way a desktop can.
 */
export const InfoPanel: React.FC<{
  title?: string;
  rows: { label: string; value: string }[];
  collapsible?: boolean;
  defaultOpen?: boolean;
  chevron?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({ title, rows, collapsible, defaultOpen = true, chevron, style }) => {
  const t = useTheme();
  const [open, setOpen] = React.useState(defaultOpen);

  return (
    <GlassPanel style={[{ padding: t.space(3) }, style]}>
      {title && (
        <Pressable
          onPress={collapsible ? () => setOpen((v) => !v) : undefined}
          disabled={!collapsible}
          accessibilityRole={collapsible ? 'button' : 'header'}
          accessibilityState={collapsible ? { expanded: open } : undefined}
          style={{
            flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
            minHeight: collapsible ? 32 : undefined,
          }}
        >
          <Text style={[type.micro, { color: t.textFaint }]}>{title}</Text>
          {collapsible && chevron}
        </Pressable>
      )}

      {open && (
        <View style={{ marginTop: title ? t.space(1) : 0 }}>
          {rows.map((r, i) => (
            <View
              key={i}
              style={{
                flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
                gap: t.space(3), paddingVertical: t.space(2),
                borderBottomWidth: i === rows.length - 1 ? 0 : StyleSheet.hairlineWidth,
                borderBottomColor: t.border,
              }}
            >
              <Text style={[type.micro, { color: t.textFaint }]}>{r.label}</Text>
              <Text numberOfLines={1} style={[type.mono, { color: t.textDim, flexShrink: 1, textAlign: 'right' }]}>
                {r.value}
              </Text>
            </View>
          ))}
        </View>
      )}
    </GlassPanel>
  );
};

/* ---------------------------------------------------------------- ModeTabs */

/**
 * The mobile ModeRail.
 *
 * The web version is a vertical rail down the left edge; that space does not
 * exist on a phone. This scrolls horizontally instead, and keeps the icon-over-
 * label shape, because a mode changes what the whole screen is FOR and that is
 * too consequential to leave to a glyph.
 */
export function ModeTabs<T extends string>({
  items, value, onChange, style,
}: {
  items: { value: T; label: string; icon: React.ReactNode; disabled?: boolean }[];
  value: T;
  onChange: (v: T) => void;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  return (
    <ScrollView
      horizontal
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: t.space(2), paddingHorizontal: t.space(4) }}
      style={style}
    >
      {items.map((item) => {
        const active = value === item.value;
        return (
          <Pressable
            key={item.value}
            onPress={() => !item.disabled && onChange(item.value)}
            disabled={item.disabled}
            accessibilityRole="tab"
            accessibilityState={{ selected: active, disabled: item.disabled }}
            style={{
              minWidth: 74, minHeight: 64,
              alignItems: 'center', justifyContent: 'center', gap: 5,
              paddingHorizontal: t.space(2),
              borderRadius: t.radiusSm,
              backgroundColor: active ? t.surface3 : t.surface1,
              borderWidth: StyleSheet.hairlineWidth * 2,
              borderColor: active ? t.borderStrong : t.border,
              opacity: item.disabled ? 0.4 : 1,
            }}
          >
            {item.icon}
            <Text
              numberOfLines={1}
              maxFontSizeMultiplier={1.2}
              style={{ fontSize: 10, fontWeight: '600', color: active ? t.text : t.textFaint }}
            >
              {item.label}
            </Text>
          </Pressable>
        );
      })}
    </ScrollView>
  );
}

/* ------------------------------------------------------------------- Stage */

/**
 * A full-screen working view — the viewer, the canvas.
 *
 * A separate screen rather than something layered over a live grid, for the
 * same reason as the web kit and more so: on a phone, keeping a FlatList of
 * decoded images mounted behind a GL canvas is how an app gets killed for
 * memory. Navigate to this; do not overlay it.
 *
 * `edgeToEdge` lets the canvas run under the status bar while the header floats
 * above it, which is what makes a viewer feel like a native one.
 */
export const Stage: React.FC<{
  children: React.ReactNode;
  header?: React.ReactNode;
  toolbar?: React.ReactNode;
  insets?: Insets;
  style?: StyleProp<ViewStyle>;
}> = ({ children, header, toolbar, insets = NO_INSETS, style }) => {
  const t = useTheme();
  return (
    <View style={[{ flex: 1, backgroundColor: t.bg }, style]}>
      <View style={{ flex: 1 }}>{children}</View>

      {header && (
        <View
          style={{
            position: 'absolute', top: insets.top, left: 0, right: 0,
            // Android draws overlapping siblings by elevation, not source order,
            // so a floating header needs one or the canvas can cover it.
            ...(Platform.OS === 'android' ? { elevation: 4 } : {}),
          }}
        >
          {header}
        </View>
      )}

      {toolbar}
    </View>
  );
};

/* ------------------------------------------------------------------ export */
export { elevation };
