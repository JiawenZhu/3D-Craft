import React, { useState } from 'react';
import {
  Image, Pressable, ScrollView, StyleSheet, Text, View, useWindowDimensions,
  type StyleProp, type ViewStyle,
} from 'react-native';
import { tone, type, useTheme, type Status } from '../theme';
import { Field, GlassPanel, IconButton, PillButton, StatusChip, StepMarker } from './primitives';

/* ===========================================================================
 * studio-ui-native — flow
 *
 * A multi-stage job, drawn as its stages.
 *
 *   input ──► transform ──► render ──► result
 *
 * Same argument as the web kit — a single bar across a two-minute, three-model
 * job tells the user nothing they can act on, and splitting it lets a failure
 * be attributed to a stage and a retry start from that stage instead of the
 * top.
 *
 * BUT THE AXIS FLIPS. On the web the stages sit in a row, because a monitor is
 * wide and four cards across read as one flow. A phone is 390pt wide; four
 * columns is four unreadable slivers. So the board runs DOWN by default, with
 * the connectors vertical, and only goes horizontal on a tablet where the room
 * actually exists. Rotating a layout to fit the device is not a compromise
 * here — a vertical list of stages is arguably the more honest picture of a
 * sequence anyway, and it scrolls the way a phone already wants to.
 * ========================================================================= */

export interface FlowNodeData {
  id: string;
  /** Say what the stage DOES, not what it is called internally. */
  label: string;
  status: Status;
  /** Sub-line: which engine ran, how long it took. */
  meta?: string;
  imageUri?: string;
  text?: string;
  /** One line about the choice this stage made. The machine's voice. */
  note?: string;
  progress?: number;
  message?: string;
  error?: string;
}

/* --------------------------------------------------------------- Connector */

/** The run of track between two stages. Fills as the stage after it starts. */
export const Connector: React.FC<{
  active?: boolean; done?: boolean; horizontal?: boolean;
}> = ({ active, done, horizontal }) => {
  const t = useTheme();
  const color = done ? t.ok : active ? t.busy : t.border;
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={
        horizontal
          ? { width: 24, alignSelf: 'center', height: 2, backgroundColor: color }
          : { height: 20, marginLeft: 12 + 11, width: 2, backgroundColor: color }
      }
    />
  );
};

/* ---------------------------------------------------------------- FlowNode */

export const FlowNode: React.FC<{
  node: FlowNodeData;
  index: number;
  /** Edit and retry appear only once the run has come to rest. */
  settled?: boolean;
  onEdit?: (text: string) => void;
  onRetry?: () => void;
  onPressImage?: (uri: string) => void;
  /** Name the ACTION — the user is starting work, not filing something. */
  editAction?: string;
  icons?: Partial<Record<'busy' | 'ok' | 'warn' | 'danger' | 'edit' | 'retry' | 'close', React.ReactNode>>;
  footer?: React.ReactNode;
  children?: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}> = ({
  node, index, settled = true, onEdit, onRetry, onPressImage,
  editAction = 'Run with this', icons, footer, children, style,
}) => {
  const t = useTheme();
  const [draft, setDraft] = useState<string | null>(null);
  const [expanded, setExpanded] = useState(false);
  const c = tone(t, node.status);
  const editing = draft !== null;

  const commit = () => {
    const next = (draft ?? '').trim();
    setDraft(null);
    if (next && onEdit) onEdit(next);
  };

  return (
    <GlassPanel
      surface={1}
      dashed={node.status === 'idle'}
      style={[
        { padding: t.space(3) },
        node.status === 'busy' && { borderColor: t.busy },
        node.status === 'danger' && { borderColor: t.danger },
        style,
      ]}
    >
      {/* header ------------------------------------------------------- */}
      <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: t.space(2) }}>
        <StepMarker index={index + 1} status={node.status} icons={icons} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <Text numberOfLines={1} style={[type.label, { color: node.status === 'busy' ? t.text : t.textDim, fontWeight: '700' }]}>
            {node.label}
          </Text>
          {node.meta && (
            <Text numberOfLines={1} style={[type.mono, { color: t.textGhost, marginTop: 2, fontSize: 11 }]}>
              {node.meta}
            </Text>
          )}
        </View>
        <View style={{ flexDirection: 'row', gap: 2 }}>
          {onEdit && settled && !editing && icons?.edit && (
            <IconButton size={28} label={`Edit ${node.label}`} onPress={() => setDraft(node.text ?? '')}>
              {icons.edit}
            </IconButton>
          )}
          {onRetry && settled && !editing && icons?.retry && (
            <IconButton size={28} label={`Re-run from ${node.label}`} onPress={onRetry}>
              {icons.retry}
            </IconButton>
          )}
          {editing && icons?.close && (
            <IconButton size={28} label="Discard edit" onPress={() => setDraft(null)}>
              {icons.close}
            </IconButton>
          )}
        </View>
      </View>

      {/* body --------------------------------------------------------- */}
      <View style={{ marginTop: t.space(3) }}>
        {editing ? (
          <View>
            <Field
              value={draft}
              onChangeText={setDraft}
              multiline
              autoFocus
              placeholder="…"
            />
            <PillButton
              title={editAction}
              variant="accent"
              size="sm"
              disabled={!draft.trim()}
              onPress={commit}
              style={{ marginTop: t.space(2) }}
            />
          </View>
        ) : children ? (
          children
        ) : node.status === 'danger' && node.error ? (
          <View style={{ backgroundColor: c.bg, padding: t.space(2.5), borderRadius: t.radiusSm }}>
            <Text style={[type.caption, { color: c.fg, lineHeight: 18 }]}>{node.error}</Text>
          </View>
        ) : node.imageUri ? (
          <Pressable
            onPress={() => node.imageUri && onPressImage?.(node.imageUri)}
            accessibilityRole="imagebutton"
            accessibilityLabel={`${node.label} image`}
            style={{
              height: 150, borderRadius: t.radiusSm, overflow: 'hidden',
              backgroundColor: t.surfaceSunk,
              borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border,
            }}
          >
            <Image source={{ uri: node.imageUri }} resizeMode="contain" style={{ flex: 1 }} />
          </Pressable>
        ) : node.text ? (
          <View style={{ backgroundColor: t.surface1, padding: t.space(2.5), borderRadius: t.radiusSm }}>
            {node.note && (
              <Text style={[type.caption, { color: t.accent, lineHeight: 18, marginBottom: t.space(1.5) }]}>
                {node.note}
              </Text>
            )}
            <Text
              numberOfLines={expanded ? undefined : 4}
              style={[type.caption, { color: t.textFaint, lineHeight: 18 }]}
            >
              {node.text}
            </Text>
            <Pressable
              onPress={() => setExpanded((v) => !v)}
              hitSlop={10}
              accessibilityRole="button"
              style={{ marginTop: t.space(1.5) }}
            >
              <Text style={[type.caption, { color: t.textGhost }]}>{expanded ? 'less' : 'show all'}</Text>
            </Pressable>
          </View>
        ) : node.status === 'busy' ? (
          <View style={{ paddingVertical: t.space(4) }}>
            <View style={{ height: 3, borderRadius: 2, backgroundColor: t.surface3 }}>
              <View style={{ width: `${node.progress ?? 3}%`, height: 3, borderRadius: 2, backgroundColor: t.busy }} />
            </View>
            {node.message && (
              <Text numberOfLines={1} style={[type.mono, { color: t.textFaint, marginTop: t.space(2), fontSize: 11 }]}>
                {node.message}
              </Text>
            )}
          </View>
        ) : (
          <View
            style={{
              height: 56, borderRadius: t.radiusSm, alignItems: 'center', justifyContent: 'center',
              borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.border, borderStyle: 'dashed',
            }}
          >
            <Text style={[type.caption, { color: t.textGhost }]}>waiting</Text>
          </View>
        )}
      </View>

      {footer && !editing && <View style={{ marginTop: t.space(3) }}>{footer}</View>}
    </GlassPanel>
  );
};

/* --------------------------------------------------------------- FlowBoard */

/**
 * Vertical on a phone, horizontal on a tablet.
 *
 * The breakpoint is width, not `Platform.isPad`: a phone in landscape and a
 * split-screen tablet both exist, and both are decided by how much room there
 * actually is rather than by what kind of device it nominally is.
 */
export function FlowBoard<T extends { id: string; status: Status }>({
  nodes, renderNode, title, subtitle, statusLabel, actions, error, horizontalAt = 700, style,
}: {
  nodes: T[];
  renderNode: (node: T, index: number) => React.ReactNode;
  title?: string;
  subtitle?: string;
  statusLabel?: { status: Status; label: string };
  actions?: React.ReactNode;
  error?: string;
  /** Width in pt at or above which the board lays out in a row. */
  horizontalAt?: number;
  style?: StyleProp<ViewStyle>;
}) {
  const t = useTheme();
  const { width } = useWindowDimensions();
  const horizontal = width >= horizontalAt;

  const body = nodes.map((node, i) => (
    <React.Fragment key={node.id}>
      <View style={horizontal ? { width: 260 } : undefined}>{renderNode(node, i)}</View>
      {i < nodes.length - 1 && (
        <Connector
          horizontal={horizontal}
          active={nodes[i + 1].status === 'busy'}
          done={nodes[i + 1].status === 'ok'}
        />
      )}
    </React.Fragment>
  ));

  return (
    <View style={style}>
      {(title || statusLabel || actions) && (
        <View
          style={{
            flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between',
            gap: t.space(3), marginBottom: t.space(4),
          }}
        >
          <View style={{ flex: 1, minWidth: 0 }}>
            {(subtitle || statusLabel) && (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: t.space(2) }}>
                {subtitle && <Text style={[type.micro, { color: t.textFaint }]}>{subtitle}</Text>}
                {statusLabel && <StatusChip status={statusLabel.status} label={statusLabel.label} />}
              </View>
            )}
            {title && (
              <Text numberOfLines={1} style={[type.title, { color: t.text, marginTop: t.space(1) }]}>
                {title}
              </Text>
            )}
          </View>
          {actions && <View style={{ flexDirection: 'row', gap: t.space(1.5) }}>{actions}</View>}
        </View>
      )}

      {horizontal ? (
        <ScrollView horizontal showsHorizontalScrollIndicator={false}>
          <View style={{ flexDirection: 'row', alignItems: 'stretch' }}>{body}</View>
        </ScrollView>
      ) : (
        <View>{body}</View>
      )}

      {error && (
        <View
          style={{
            marginTop: t.space(3), padding: t.space(3), borderRadius: t.radiusSm,
            backgroundColor: t.dangerSoft,
            borderWidth: StyleSheet.hairlineWidth * 2, borderColor: t.danger,
          }}
        >
          <Text style={[type.caption, { color: t.danger, lineHeight: 18 }]}>{error}</Text>
        </View>
      )}
    </View>
  );
}
