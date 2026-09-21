import SwiftUI
import WidgetKit
import ActivityKit

/// Lock Screen banner and Dynamic Island for a running creation job.
///
/// Everything here is a snapshot: WidgetKit re-renders only when the job sends
/// new state, so the mascot is a still that steps forward with real progress
/// and never implies motion the job has not made. The elapsed time is the one
/// thing that moves by itself, because the system renders that text.
struct GenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CraftGenerationAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.06, blue: 0.11))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MascotBadge(context: context, size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(percent(context)).font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit().foregroundStyle(.white)
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.system(.caption2, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: 54, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(CraftActivityText.title(kind: context.attributes.kind, chinese: context.attributes.chinese))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline(context)).font(.footnote.weight(.medium)).foregroundStyle(.white)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        ProgressBar(context: context, height: 8)
                    }
                }
            } compactLeading: {
                MascotBadge(context: context, size: 24, ring: true)
            } compactTrailing: {
                CompactProgress(context: context)
            } minimal: {
                MascotBadge(context: context, size: 22, ring: true)
            }
            .widgetURL(URL(string: "studio.craft.ios://project/\(context.attributes.projectId)"))
            .keylineTint(context.attributes.mascot == .panda
                ? Color(red: 0.45, green: 0.85, blue: 0.65)
                : Color(red: 0.85, green: 0.63, blue: 0.95))
        }
    }

    private func headline(_ context: ActivityViewContext<CraftGenerationAttributes>) -> String {
        CraftActivityText.headline(context.state, kind: context.attributes.kind, chinese: context.attributes.chinese)
    }

    private func percent(_ context: ActivityViewContext<CraftGenerationAttributes>) -> String {
        context.state.failed ? "—" : "\(Int((context.state.progress * 100).rounded()))%"
    }
}

// MARK: - Lock Screen

/// The banner people see when the screen turns on, and, dimmed, while it is
/// off on an always-on display.
private struct LockScreenView: View {
    let context: ActivityViewContext<CraftGenerationAttributes>
    /// True on an always-on display: iOS asks for a dimmer, quieter layout.
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            MascotBadge(context: context, size: dimmed ? 52 : 64)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(CraftActivityText.title(kind: context.attributes.kind, chinese: context.attributes.chinese))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(dimmed ? 0.55 : 0.7))
                    Spacer(minLength: 0)
                    if !context.state.finished && !context.state.failed {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.system(.caption2, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.white.opacity(dimmed ? 0.4 : 0.55))
                            .frame(maxWidth: 46, alignment: .trailing)
                    }
                }
                Text(CraftActivityText.headline(context.state, kind: context.attributes.kind,
                                                chinese: context.attributes.chinese))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(dimmed ? 0.8 : 1))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                ProgressBar(context: context, height: dimmed ? 6 : 9)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

private final class WidgetBundleToken {}

/// The waiting mascot for this phase: thinking while queued, drawing for
/// concept images, shaping for 3D. A still, stepped by real progress.
private struct MascotBadge: View {
    let context: ActivityViewContext<CraftGenerationAttributes>
    var size: CGFloat
    var ring: Bool = true
    @Environment(\.isLuminanceReduced) private var dimmed

    private var name: String {
        CraftActivityText.frameName(context.attributes.mascot,
                                    context.state.phase,
                                    // A still image is honest when the screen is off.
                                    dimmed ? 1 : context.state.frame)
    }

    private var isPanda: Bool {
        context.attributes.mascot == .panda
    }

    private var themeColor: Color {
        isPanda ? Color(red: 0.45, green: 0.85, blue: 0.65) // Emerald green
                : Color(red: 0.85, green: 0.63, blue: 0.95) // Lavender purple (Rodin)
    }

    private var themeBackground: Color {
        isPanda ? Color(red: 0.90, green: 0.96, blue: 0.93)
                : Color(red: 0.94, green: 0.92, blue: 0.98)
    }

    private var mascotImage: Image? {
        let bundle = Bundle(for: WidgetBundleToken.self)
        // 1. Try named asset from Asset Catalog
        if let uiImage = UIImage(named: name, in: bundle, with: nil) {
            return Image(uiImage: uiImage)
        }
        // 2. Try loose file in extension bundle
        if let path = bundle.path(forResource: name, ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }
        // 3. Try main bundle
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let uiImage = UIImage(contentsOfFile: path) {
            return Image(uiImage: uiImage)
        }
        if let uiImage = UIImage(named: name, in: .main, with: nil) {
            return Image(uiImage: uiImage)
        }
        return nil
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(themeBackground)
                .frame(width: size, height: size)

            if let img = mascotImage {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(name, bundle: Bundle(for: WidgetBundleToken.self))
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentTransition(.opacity)
        .overlay {
            if ring {
                Circle().strokeBorder(themeColor.opacity(dimmed ? 0.35 : 0.8), lineWidth: size > 40 ? 1.5 : 1)
            }
        }
        .opacity(dimmed ? 0.75 : 1)
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.35), value: context.state.frame)
    }
}

/// A rounded track with a gradient fill, a soft leading edge and the stage
/// named underneath. Queued work shows a small indeterminate nub rather than a
/// bar pretending to be at zero.
private struct ProgressBar: View {
    let context: ActivityViewContext<CraftGenerationAttributes>
    var height: CGFloat
    @Environment(\.isLuminanceReduced) private var dimmed

    private var isPanda: Bool {
        context.attributes.mascot == .panda
    }

    private var fraction: Double {
        context.state.finished ? 1 : max(context.state.progress, context.state.phase == .thinking ? 0.06 : 0.02)
    }
    private var tint: LinearGradient {
        let colors: [Color] = context.state.failed
            ? [Color(red: 0.95, green: 0.55, blue: 0.45), Color(red: 0.85, green: 0.35, blue: 0.30)]
            : context.state.finished
                ? [Color(red: 0.60, green: 0.90, blue: 0.75), Color(red: 0.45, green: 0.82, blue: 0.65)]
                : isPanda
                    ? [Color(red: 0.45, green: 0.85, blue: 0.65), Color(red: 0.30, green: 0.75, blue: 0.55)]
                    : [Color(red: 0.85, green: 0.63, blue: 0.95), Color(red: 0.62, green: 0.78, blue: 0.98)]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(dimmed ? 0.12 : 0.18))
                    Capsule().fill(tint)
                        .frame(width: max(height, geometry.size.width * fraction))
                        .opacity(dimmed ? 0.75 : 1)
                }
            }
            .frame(height: height)
            HStack(spacing: 4) {
                Text(CraftActivityText.stageLabel(context.state, chinese: context.attributes.chinese))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(dimmed ? 0.45 : 0.6))
                Spacer(minLength: 0)
                if !context.state.failed {
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.caption2.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(dimmed ? 0.45 : 0.6))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(CraftActivityText.stageLabel(context.state, chinese: context.attributes.chinese)))
        .accessibilityValue(Text("\(Int((context.state.progress * 100).rounded())) percent"))
    }
}

/// A ring in the compact trailing slot: the percentage is too small to read
/// there, but a filling ring reads at a glance.
private struct CompactProgress: View {
    let context: ActivityViewContext<CraftGenerationAttributes>

    private var activeColor: Color {
        context.attributes.mascot == .panda
            ? Color(red: 0.45, green: 0.85, blue: 0.65)
            : Color(red: 0.85, green: 0.63, blue: 0.95)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.04, context.state.finished ? 1 : context.state.progress))
                .stroke(context.state.failed ? Color.orange
                        : context.state.finished ? Color.green
                        : activeColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if context.state.finished {
                Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityLabel(Text("\(Int((context.state.progress * 100).rounded())) percent"))
    }
}

// MARK: - Character Gadget Widget (Desktop Widgets & Looping Showcase)

struct CharacterGadgetEntry: TimelineEntry {
    let date: Date
    let gadget: CraftGadgetData
    let heroImage: UIImage?
}

struct CharacterGadgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CharacterGadgetEntry {
        let gadget = CraftGadgetCenter.shared.activeGadget()
        let image = CraftGadgetCenter.shared.loadHeroImage(for: gadget)
        return CharacterGadgetEntry(
            date: .now,
            gadget: gadget,
            heroImage: image
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CharacterGadgetEntry) -> Void) {
        let gadget = CraftGadgetCenter.shared.activeGadget()
        let image = CraftGadgetCenter.shared.loadHeroImage(for: gadget)
        completion(CharacterGadgetEntry(date: .now, gadget: gadget, heroImage: image))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CharacterGadgetEntry>) -> Void) {
        let gadget = CraftGadgetCenter.shared.activeGadget()
        let image = CraftGadgetCenter.shared.loadHeroImage(for: gadget)
        let entry = CharacterGadgetEntry(date: .now, gadget: gadget, heroImage: image)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }
}

/// Native iOS Desktop Gadget (Widget) supporting Small (2x2), Medium (4x2), and Large (4x4)
struct CharacterGadgetWidget: Widget {
    let kind: String = "CharacterGadgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CharacterGadgetProvider()) { entry in
            CharacterGadgetView(entry: entry)
                .containerBackground(Color(red: 0.08, green: 0.08, blue: 0.11), for: .widget)
        }
        .configurationDisplayName("3D Craft Gadget")
        .description("Display your favorite 3D character animation loops on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CharacterGadgetView: View {
    let entry: CharacterGadgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallGadgetView(entry: entry)
            case .systemMedium:
                MediumGadgetView(entry: entry)
            case .systemLarge:
                LargeGadgetView(entry: entry)
            default:
                SmallGadgetView(entry: entry)
            }
        }
        .widgetURL(URL(string: "studio.craft.ios://animation/\(entry.gadget.id)"))
    }
}

// MARK: - Small Widget (Circled Icon 2)
private struct SmallGadgetView: View {
    let entry: CharacterGadgetEntry

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.11)
            heroImageView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    @ViewBuilder
    private var heroImageView: some View {
        if let uiImg = entry.heroImage {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if let dragonImg = UIImage(named: "fire-dragon", in: Bundle(for: WidgetBundleToken.self), with: nil) {
            Image(uiImage: dragonImg)
                .resizable()
                .scaledToFill()
        } else {
            Image("mascot-dragon-model-1", bundle: Bundle(for: WidgetBundleToken.self))
                .resizable()
                .scaledToFill()
        }
    }
}

// MARK: - Medium Widget (Circled Icon 5)
private struct MediumGadgetView: View {
    let entry: CharacterGadgetEntry

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                heroImageView
                    .frame(width: 130, height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("Loop")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(6)
            }
            .padding(8)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.gadget.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(entry.gadget.modelName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.28))

                Text("4-second seamless physics motion loop")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 8))
                    Text("Tap to inspect in 3D")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .padding(.trailing, 10)
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var heroImageView: some View {
        if let uiImg = entry.heroImage {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if let dragonImg = UIImage(named: "fire-dragon", in: Bundle(for: WidgetBundleToken.self), with: nil) {
            Image(uiImage: dragonImg)
                .resizable()
                .scaledToFill()
        } else {
            Image("mascot-dragon-model-1", bundle: Bundle(for: WidgetBundleToken.self))
                .resizable()
                .scaledToFill()
        }
    }
}

// MARK: - Large Widget (Circled Icon 4)
private struct LargeGadgetView: View {
    let entry: CharacterGadgetEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                heroImageView
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("4s Physics Loop")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.gadget.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("3D Craft")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.28))
                }

                HStack(spacing: 6) {
                    tag(icon: "cube.fill", text: "PBR 3D")
                    tag(icon: "repeat", text: "Looping")
                    tag(icon: "gamecontroller.fill", text: "Playable")
                }

                Spacer(minLength: 2)

                HStack {
                    Label("Tap to inspect 360° in app", systemImage: "hand.draw")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(8)
    }

    private func tag(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8)).foregroundStyle(Color(red: 1.0, green: 0.48, blue: 0.28))
            Text(text).font(.system(size: 8, weight: .medium)).foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var heroImageView: some View {
        if let uiImg = entry.heroImage {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if let dragonImg = UIImage(named: "fire-dragon", in: Bundle(for: WidgetBundleToken.self), with: nil) {
            Image(uiImage: dragonImg)
                .resizable()
                .scaledToFill()
        } else {
            Image("mascot-dragon-model-1", bundle: Bundle(for: WidgetBundleToken.self))
                .resizable()
                .scaledToFill()
        }
    }
}

@main
struct CraftStudioWidgetsBundle: WidgetBundle {
    var body: some Widget {
        GenerationLiveActivity()
        CharacterGadgetWidget()
    }
}
