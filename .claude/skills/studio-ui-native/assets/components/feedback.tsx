import React, { useEffect, useRef } from 'react';
import {
  Animated, BackHandler, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, View,
  useWindowDimensions,
  type StyleProp, type ViewStyle,
} from 'react-native';
import { elevation, tone, type, useTheme, type Status } from '../theme';
import { IconButton } from './primitives';

/* ===========================================================================
 * studio-ui-native — feedback
 *
 * The things that appear over a screen, and the replacements for two web
 * patterns that do not survive the crossing.
 *
 * Popover and Tooltip both anchor to a pointer. On a phone there is no pointer
 * and not enough room to float a panel beside its trigger, so both become the
 * same thing: a sheet from the bottom, where the thumb already is.
 * ========================================================================= */

/* ------------------------------------------------------------------- Sheet */

/**
 * Bottom sheet. This is the mobile Popover.
 *
 * Anchoring a panel next to what opened it is a desktop idea: it assumes room
 * beside the trigger and a cursor to aim with. On a phone the reachable area is
 * the bottom third of the screen, which is why every native picker lives there.
 *
 * Android's hardware back button must dismiss it. Miss that and the back press
 * pops the whole navigation stack out from under an open sheet, which users
 * read as the app losing their place.
 */
export const Sheet: React.FC<{
  visible: boolean;
  onClose: () => void;
  title?: string;
  children: React.ReactNode;
  /** Fraction of screen height the sheet may grow to. */
  maxHeight?: number;
  closeIcon?: React.ReactNode;
}> = ({ visible, onClose, title, children, maxHeight = 0.75, closeIcon }) => {
  const t = useTheme();
  const { height } = useWindowDimensions();
  const slide = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.timing(slide, {
      toValue: visible ? 1 : 0,
      duration: visible ? t.base : t.fast,
      useNativeDriver: true,
    }).start();
  }, [visible, slide, t.base, t.fast]);

  useEffect(() => {
    if (!visible || Platform.OS !== 'android') return;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => { onClose(); return true; });
    return () => sub.remove();
  }, [visible, onClose]);

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose}>
      <Pressable
        onPress={onClose}
        accessibilityLabel="Close"
        style={[StyleSheet.absoluteFill, { backgroundColor: 'rgba(0,0,0,0.6)' }]}
      />
      <Animated.View
        style={{
          position: 'absolute', left: 0, right: 0, bottom: 0,
          maxHeight: height * maxHeight,
          backgroundColor: t.bgRaised,
          borderTopLeftRadius: t.radiusLg, borderTopRightRadius: t.radiusLg,
          borderTopWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border,
          paddingBottom: t.space(8),
          transform: [{ translateY: slide.interpolate({ inputRange: [0, 1], outputRange: [height, 0] }) }],
          ...elevation(3),
        }}
      >
        {/* Grab handle. Not decorative — it is the only affordance saying this
            panel can be dismissed by dragging rather than by finding a button. */}
        <View style={{ alignItems: 'center', paddingVertical: t.space(3) }}>
          <View style={{ width: 36, height: 4, borderRadius: 2, backgroundColor: t.borderStrong }} />
        </View>

        {title && (
          <View
            style={{
              flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
              paddingHorizontal: t.space(5), paddingBottom: t.space(3),
            }}
          >
            <Text style={[type.heading, { color: t.text }]}>{title}</Text>
            {closeIcon && <IconButton label="Close" onPress={onClose}>{closeIcon}</IconButton>}
          </View>
        )}

        <ScrollView
          contentContainerStyle={{ paddingHorizontal: t.space(5), paddingBottom: t.space(4) }}
          showsVerticalScrollIndicator={false}
        >
          {children}
        </ScrollView>
      </Animated.View>
    </Modal>
  );
};

/* -------------------------------------------------------------------- Hint */

/**
 * The mobile Tooltip.
 *
 * A hover label has no touch equivalent, and mapping it to a tap collides with
 * whatever the control already does. So the explanation gets its own small
 * target — an (i) beside the thing — and opens a sheet.
 *
 * If a control needs a Hint to be understandable at all, that is worth noticing
 * rather than papering over: on a phone the label usually belongs in the
 * interface, visible.
 */
export const Hint: React.FC<{
  title: string;
  body: string;
  icon: React.ReactNode;
  closeIcon?: React.ReactNode;
}> = ({ title, body, icon, closeIcon }) => {
  const t = useTheme();
  const [open, setOpen] = React.useState(false);
  return (
    <>
      <IconButton size={28} label={`About ${title}`} onPress={() => setOpen(true)}>{icon}</IconButton>
      <Sheet visible={open} onClose={() => setOpen(false)} title={title} closeIcon={closeIcon}>
        <Text style={[type.body, { color: t.textDim, lineHeight: 22 }]}>{body}</Text>
      </Sheet>
    </>
  );
};

/* ------------------------------------------------------------------ Notice */

/**
 * A line of feedback that is not a dialog.
 *
 * `live` announces it to VoiceOver and TalkBack — a message that only exists
 * visually is invisible to anyone who did not happen to be looking at that part
 * of the screen, which on a phone is most of it.
 */
export const Notice: React.FC<{
  tone?: Status;
  children: React.ReactNode;
  icon?: React.ReactNode;
  onDismiss?: () => void;
  dismissIcon?: React.ReactNode;
  action?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({ tone: kind = 'idle', children, icon, onDismiss, dismissIcon, action, style }) => {
  const t = useTheme();
  const c = tone(t, kind);
  return (
    <View
      accessibilityLiveRegion={kind === 'danger' ? 'assertive' : 'polite'}
      accessibilityRole={kind === 'danger' ? 'alert' : undefined}
      style={[
        {
          flexDirection: 'row', alignItems: 'flex-start', gap: t.space(2),
          padding: t.space(3), borderRadius: t.radiusSm,
          backgroundColor: c.bg, borderWidth: StyleSheet.hairlineWidth * 2, borderColor: c.line,
        },
        style,
      ]}
    >
      {icon}
      <View style={{ flex: 1 }}>
        {typeof children === 'string'
          ? <Text style={[type.caption, { color: c.fg, lineHeight: 18 }]}>{children}</Text>
          : children}
      </View>
      {action}
      {onDismiss && dismissIcon && (
        <IconButton size={24} label="Dismiss" onPress={onDismiss}>{dismissIcon}</IconButton>
      )}
    </View>
  );
};

/* -------------------------------------------------------------- StatusPill */

/**
 * Health readout. States what IS, and stays visible when everything is fine —
 * an indicator that only appears on failure is one nobody has reason to trust,
 * because they have never seen it working.
 */
export const StatusPill: React.FC<{
  status: Status; label: string; style?: StyleProp<ViewStyle>;
}> = ({ status, label, style }) => {
  const t = useTheme();
  const c = tone(t, status);
  const pulse = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    if (status !== 'busy') { pulse.setValue(1); return; }
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 0.35, duration: 700, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 1, duration: 700, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [status, pulse]);

  return (
    <View
      accessibilityLabel={`${label}, ${status}`}
      style={[
        {
          flexDirection: 'row', alignItems: 'center', gap: 6, alignSelf: 'flex-start',
          paddingHorizontal: t.space(2.5), paddingVertical: t.space(1.5),
          borderRadius: t.radiusPill, backgroundColor: t.surface1,
          borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border,
        },
        style,
      ]}
    >
      <Animated.View
        style={{ width: 6, height: 6, borderRadius: 3, backgroundColor: c.fg, opacity: pulse }}
      />
      <Text style={[type.mono, { color: t.textFaint }]}>{label}</Text>
    </View>
  );
};

/* ---------------------------------------------------------------- Lightbox */

/**
 * Full-screen image viewer.
 *
 * `animationType="fade"` rather than a slide, because the image is already on
 * screen behind it and a slide implies you have navigated somewhere else.
 */
export const Lightbox: React.FC<{
  visible: boolean;
  onClose: () => void;
  children: React.ReactNode;
  caption?: string;
  closeIcon?: React.ReactNode;
}> = ({ visible, onClose, children, caption, closeIcon }) => {
  const t = useTheme();
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable
        onPress={onClose}
        accessibilityLabel="Close image"
        style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.94)', alignItems: 'center', justifyContent: 'center' }}
      >
        {children}
        {caption && (
          <Text style={[type.caption, { color: t.textFaint, marginTop: t.space(4) }]}>{caption}</Text>
        )}
        {closeIcon && (
          <View style={{ position: 'absolute', top: t.space(12), right: t.space(5) }}>
            <IconButton label="Close" onPress={onClose}>{closeIcon}</IconButton>
          </View>
        )}
      </Pressable>
    </Modal>
  );
};
