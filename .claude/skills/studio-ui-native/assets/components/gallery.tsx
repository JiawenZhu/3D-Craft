import React, { useCallback, useState } from 'react';
import {
  FlatList, Image, Pressable, StyleSheet, Text, TextInput, View, useWindowDimensions,
  type ImageStyle, type ListRenderItemInfo, type StyleProp, type ViewStyle,
} from 'react-native';
import { tone, type, useTheme, type Status } from '../theme';
import { GlassPanel, IconButton } from './primitives';

/* ===========================================================================
 * studio-ui-native — gallery
 *
 * Grids of generated things.
 *
 * The web kit's gallery is built around lazy image decoding. Here the same
 * concern is sharper and the mechanism is different: FlatList windowing, which
 * unmounts rows that leave the viewport instead of merely deferring their
 * decode. A phone has a fraction of the memory and the OS kills you rather than
 * swapping, so this is the difference between a gallery and a crash report.
 *
 * The bigger change is not technical. THERE IS NO HOVER, so the web card's
 * hidden metadata has nowhere to hide. It is always visible here, under the
 * image, and secondary actions move to a long press. That is not a downgrade —
 * on a phone the caption being permanently readable is better; it was hidden on
 * the web only because a dense grid of captions reads as a spreadsheet at
 * desktop scale.
 * ========================================================================= */

/* ------------------------------------------------------------------- Thumb */

export const Thumb: React.FC<{
  uri?: string;
  label: string;
  fallback?: React.ReactNode;
  resizeMode?: 'cover' | 'contain';
  /**
   * Typed as ImageStyle because that is the stricter of the two — RN's
   * ImageStyle forbids `overflow: 'scroll'`, which ViewStyle allows. Taking the
   * strict type publicly and widening it for the fallback View is the only
   * direction that cannot produce an invalid style at a call site.
   */
  style?: StyleProp<ImageStyle>;
}> = ({ uri, label, fallback, resizeMode = 'cover', style }) => {
  const t = useTheme();
  const [failed, setFailed] = useState(false);

  if (!uri || failed) {
    return (
      <View
        style={[
          { backgroundColor: t.surfaceSunk, alignItems: 'center', justifyContent: 'center' },
          style as StyleProp<ViewStyle>,
        ]}
      >
        {fallback ?? <Text style={[type.caption, { color: t.textGhost }]}>{label}</Text>}
      </View>
    );
  }
  return (
    <Image
      source={{ uri }}
      resizeMode={resizeMode}
      onError={() => setFailed(true)}
      accessibilityLabel={label}
      style={style}
    />
  );
};

/* --------------------------------------------------------------- MediaCard */

export interface Badge {
  label: string;
  icon?: React.ReactNode;
  tone?: Status;
}

/**
 * A gallery tile.
 *
 * `onLongPress` is where the web kit's hover actions go. Long press is the
 * native idiom for "more about this thing" and it does not compete with the
 * tap, so a card can open on tap and offer a menu on hold without either
 * gesture being ambiguous.
 */
export const MediaCard: React.FC<{
  title: string;
  uri?: string;
  fallback?: React.ReactNode;
  onPress?: () => void;
  onLongPress?: () => void;
  badges?: Badge[];
  toggle?: { active: boolean; onToggle: () => void; icon: React.ReactNode; label: string };
  meta?: string;
  /** One line under the title — what tapping will do, when it is not obvious. */
  hint?: string;
  style?: StyleProp<ViewStyle>;
}> = ({ title, uri, fallback, onPress, onLongPress, badges, toggle, meta, hint, style }) => {
  const t = useTheme();
  return (
    <Pressable
      onPress={onPress}
      onLongPress={onLongPress}
      accessibilityRole="button"
      accessibilityLabel={[title, meta, hint].filter(Boolean).join(', ')}
      style={({ pressed }) => [
        {
          borderRadius: t.radiusLg,
          overflow: 'hidden',
          backgroundColor: t.surface1,
          borderWidth: StyleSheet.hairlineWidth * 2,
          borderColor: pressed ? t.borderStrong : t.border,
          opacity: pressed ? 0.85 : 1,
        },
        style,
      ]}
    >
      <View style={{ aspectRatio: 1 }}>
        <Thumb uri={uri} label={title} fallback={fallback} style={{ width: '100%', height: '100%' }} />

        {badges && badges.length > 0 && (
          <View style={{ position: 'absolute', top: t.space(2), left: t.space(2), gap: 4 }}>
            {badges.map((b, i) => {
              const c = tone(t, b.tone ?? 'idle');
              return (
                <View
                  key={i}
                  style={{
                    flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start',
                    paddingHorizontal: t.space(2), paddingVertical: 3,
                    borderRadius: t.radiusPill,
                    backgroundColor: b.tone ? c.bg : 'rgba(0,0,0,0.55)',
                  }}
                >
                  {b.icon}
                  <Text style={[type.caption, { color: b.tone ? c.fg : t.textDim, fontWeight: '700', fontSize: 11 }]}>
                    {b.label}
                  </Text>
                </View>
              );
            })}
          </View>
        )}

        {toggle && (
          <View style={{ position: 'absolute', top: t.space(2), right: t.space(2) }}>
            <IconButton
              size={34}
              label={toggle.label}
              active={toggle.active}
              onPress={toggle.onToggle}
              style={{ backgroundColor: toggle.active ? t.text : 'rgba(0,0,0,0.45)' }}
            >
              {toggle.icon}
            </IconButton>
          </View>
        )}
      </View>

      {/* Always visible. There is no hover to hide it behind, and on a phone
          that is the better answer anyway. */}
      <View style={{ padding: t.space(2.5) }}>
        <Text numberOfLines={1} style={[type.label, { color: t.text }]}>{title}</Text>
        {hint && (
          <Text numberOfLines={1} style={[type.caption, { color: t.accent, marginTop: 2 }]}>{hint}</Text>
        )}
        {meta && (
          <Text numberOfLines={1} style={[type.caption, { color: t.textGhost, marginTop: 2 }]}>{meta}</Text>
        )}
      </View>
    </Pressable>
  );
};

/* --------------------------------------------------------------- MediaGrid */

/**
 * FlatList, not a mapped View.
 *
 * `numColumns` derives from available width rather than being fixed, so the
 * same screen gives two columns on a phone and four on a tablet without a
 * second layout. The windowing props are conservative on purpose: generated
 * images are large, and holding twenty off-screen rows in memory is how a
 * gallery gets killed by the OS on a mid-range Android device.
 */
export function MediaGrid<T>({
  data, renderItem, keyExtractor, minColumnWidth = 170, gap, header, empty, onEndReached, style,
}: {
  data: T[];
  renderItem: (item: T, index: number, width: number) => React.ReactElement | null;
  keyExtractor: (item: T, index: number) => string;
  minColumnWidth?: number;
  gap?: number;
  header?: React.ReactElement;
  empty?: React.ReactElement;
  onEndReached?: () => void;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  const { width } = useWindowDimensions();
  const space = gap ?? t.space(3);
  const pad = t.space(4);
  const columns = Math.max(2, Math.floor((width - pad * 2 + space) / (minColumnWidth + space)));
  const cellWidth = (width - pad * 2 - space * (columns - 1)) / columns;

  const render = useCallback(
    ({ item, index }: ListRenderItemInfo<T>) => (
      <View style={{ width: cellWidth }}>{renderItem(item, index, cellWidth)}</View>
    ),
    [cellWidth, renderItem],
  );

  return (
    <FlatList
      data={data}
      key={columns}                    // remount when the column count changes
      numColumns={columns}
      keyExtractor={keyExtractor}
      renderItem={render}
      ListHeaderComponent={header}
      ListEmptyComponent={empty}
      onEndReached={onEndReached}
      onEndReachedThreshold={0.6}
      columnWrapperStyle={columns > 1 ? { gap: space } : undefined}
      contentContainerStyle={{ padding: pad, gap: space }}
      showsVerticalScrollIndicator={false}
      // Keep memory bounded. The defaults are tuned for text rows, not for
      // grids of full-size generated images.
      initialNumToRender={columns * 3}
      maxToRenderPerBatch={columns * 2}
      windowSize={5}
      removeClippedSubviews
      style={style}
    />
  );
}

/* -------------------------------------------------------------- EmptyState */

export const EmptyState: React.FC<{
  title: string; hint?: string; action?: React.ReactNode; style?: StyleProp<ViewStyle>;
}> = ({ title, hint, action, style }) => {
  const t = useTheme();
  return (
    <View
      style={[
        {
          paddingVertical: t.space(16), paddingHorizontal: t.space(6),
          alignItems: 'center', justifyContent: 'center',
          borderRadius: t.radiusLg, borderWidth: StyleSheet.hairlineWidth * 2,
          borderColor: t.border, borderStyle: 'dashed',
        },
        style,
      ]}
    >
      <Text style={[type.body, { color: t.textFaint, textAlign: 'center' }]}>{title}</Text>
      {/* The second line is the important one: it names the next action.
          "No items" only tells the user what they can already see. */}
      {hint && (
        <Text style={[type.caption, { color: t.textGhost, textAlign: 'center', marginTop: t.space(2), lineHeight: 18 }]}>
          {hint}
        </Text>
      )}
      {action && <View style={{ marginTop: t.space(4) }}>{action}</View>}
    </View>
  );
};

/* --------------------------------------------------------------- ShelfTabs */

/**
 * Section switch with counts.
 *
 * Smaller than the web kit's 30px headings — a phone cannot spend 40pt of
 * vertical space on navigation and still show a row of cards above the fold.
 */
export function ShelfTabs<T extends string>({
  tabs, value, onChange, style,
}: {
  tabs: { value: T; label: string; count?: number }[];
  value: T;
  onChange: (v: T) => void;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  return (
    <View style={[{ flexDirection: 'row', gap: t.space(5), alignItems: 'baseline' }, style]}>
      {tabs.map((tab) => {
        const active = value === tab.value;
        return (
          <Pressable
            key={tab.value}
            onPress={() => onChange(tab.value)}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            hitSlop={10}
            style={{ flexDirection: 'row', alignItems: 'baseline', gap: 6 }}
          >
            <Text
              style={{
                fontSize: 20, fontWeight: '700', letterSpacing: 0.3,
                textTransform: 'uppercase',
                color: active ? t.text : t.textGhost,
              }}
            >
              {tab.label}
            </Text>
            {tab.count != null && (
              <Text style={[type.caption, { color: t.textGhost }]}>{tab.count}</Text>
            )}
          </Pressable>
        );
      })}
    </View>
  );
}

/* ------------------------------------------------------------- SearchField */

/**
 * Always open, unlike the web kit's collapsing version.
 *
 * The web collapses it because a permanently-open box competes with the content
 * on a wide header. On a phone the opposite is true: an icon that expands into
 * a field is an extra tap and a layout shift, and there is no spare horizontal
 * room for the animation to look like anything.
 */
export const SearchField: React.FC<{
  value: string;
  onChangeText: (v: string) => void;
  placeholder?: string;
  icon?: React.ReactNode;
  clearIcon?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({ value, onChangeText, placeholder = 'Search…', icon, clearIcon, style }) => {
  const t = useTheme();
  return (
    <View
      style={[
        {
          flexDirection: 'row', alignItems: 'center', gap: t.space(2),
          height: t.tap, paddingHorizontal: t.space(3.5),
          borderRadius: t.radiusPill, backgroundColor: t.surface1,
          borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border,
        },
        style,
      ]}
    >
      {icon}
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor={t.textGhost}
        returnKeyType="search"
        clearButtonMode="never"
        accessibilityLabel={placeholder}
        style={[type.body, { flex: 1, color: t.textDim, paddingVertical: 0 }]}
      />
      {value.length > 0 && clearIcon && (
        <IconButton size={26} label="Clear search" onPress={() => onChangeText('')}>{clearIcon}</IconButton>
      )}
    </View>
  );
};

/* ------------------------------------------------------------ HistoryStrip */

export const HistoryStrip: React.FC<{
  items: { id: string; uri?: string; title: string; status?: Status }[];
  activeId?: string;
  onPick: (id: string) => void;
  size?: number;
  style?: StyleProp<ViewStyle>;
}> = ({ items, activeId, onPick, size = 68, style }) => {
  const t = useTheme();
  return (
    <FlatList
      horizontal
      data={items}
      keyExtractor={(i) => i.id}
      showsHorizontalScrollIndicator={false}
      contentContainerStyle={{ gap: t.space(2), paddingHorizontal: t.space(4) }}
      style={style}
      renderItem={({ item }) => {
        const c = item.status ? tone(t, item.status) : null;
        return (
          <Pressable
            onPress={() => onPick(item.id)}
            accessibilityRole="button"
            accessibilityLabel={item.title}
            accessibilityState={{ selected: activeId === item.id }}
            style={{
              width: size, height: size, borderRadius: t.radiusSm, overflow: 'hidden',
              borderWidth: 2,
              borderColor: activeId === item.id ? t.borderFocus : t.border,
            }}
          >
            <Thumb uri={item.uri} label={item.title} style={{ width: '100%', height: '100%' }} />
            {c && (
              <View
                style={{
                  position: 'absolute', bottom: 4, right: 4,
                  width: 7, height: 7, borderRadius: 4, backgroundColor: c.fg,
                }}
              />
            )}
          </Pressable>
        );
      }}
    />
  );
};

/* ----------------------------------------------------------- ImagePickerTile */

/**
 * The mobile DropZone.
 *
 * There is no drag-and-drop and no clipboard paste worth relying on, so the
 * whole component collapses to "tap to choose" — and the choice itself is two
 * different things on a phone, camera or library, which is why both callbacks
 * exist rather than one.
 *
 * It deliberately does NOT import expo-image-picker. A kit that hard-requires
 * a permissions-carrying native module cannot be dropped into an existing app,
 * and the app almost certainly already has its own picker and its own
 * permission copy.
 */
export const ImagePickerTile: React.FC<{
  uri?: string;
  onPickLibrary: () => void;
  onPickCamera?: () => void;
  onClear?: () => void;
  label?: string;
  hint?: string;
  addIcon?: React.ReactNode;
  cameraIcon?: React.ReactNode;
  clearIcon?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({
  uri, onPickLibrary, onPickCamera, onClear, label, hint,
  addIcon, cameraIcon, clearIcon, style,
}) => {
  const t = useTheme();
  return (
    <GlassPanel surface="sunk" style={[{ padding: t.space(2.5) }, style]}>
      {label && (
        <Text style={[type.label, { color: t.text, fontWeight: '700', marginBottom: t.space(2) }]}>{label}</Text>
      )}

      <Pressable
        onPress={onPickLibrary}
        accessibilityRole="button"
        accessibilityLabel={uri ? 'Change image' : 'Choose an image'}
        style={({ pressed }) => ({
          aspectRatio: 1,
          borderRadius: t.radiusSm,
          overflow: 'hidden',
          alignItems: 'center',
          justifyContent: 'center',
          backgroundColor: pressed ? t.surface2 : 'transparent',
          borderWidth: uri ? 0 : StyleSheet.hairlineWidth * 2,
          borderColor: t.border,
          borderStyle: 'dashed',
        })}
      >
        {uri
          ? <Image source={{ uri }} resizeMode="cover" style={{ width: '100%', height: '100%' }} />
          : addIcon}
      </Pressable>

      <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: t.space(2), marginTop: t.space(2) }}>
        {onPickCamera && cameraIcon && (
          <IconButton size={32} label="Take a photo" onPress={onPickCamera}>{cameraIcon}</IconButton>
        )}
        {uri && onClear && clearIcon && (
          <IconButton size={32} label="Remove image" onPress={onClear}>{clearIcon}</IconButton>
        )}
      </View>

      {hint && (
        <Text style={[type.caption, { color: t.textGhost, textAlign: 'center', marginTop: t.space(1) }]}>
          {hint}
        </Text>
      )}
    </GlassPanel>
  );
};
