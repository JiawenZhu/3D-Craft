import SwiftUI
import WidgetKit
import ActivityKit

/// Lock Screen banner and Dynamic Island for a running creation job.
///
/// Everything here is a snapshot: WidgetKit re-renders only when the job sends
/// new state, so the mascot is a still that steps forward with real progress
/// and never implies motion the job has not made.
struct GenerationLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CraftGenerationAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    mascot(context, size: 44).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(percent(context)).font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit().foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(CraftActivityText.title(kind: context.attributes.kind, chinese: context.attributes.chinese))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline(context)).font(.footnote).foregroundStyle(.white)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        progress(context)
                    }
                }
            } compactLeading: {
                mascot(context, size: 20)
            } compactTrailing: {
                Text(percent(context)).font(.caption2.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                mascot(context, size: 18)
            }
            .widgetURL(URL(string: "studio.craft.ios://project/\(context.attributes.projectId)"))
        }
    }

    private func lockScreen(_ context: ActivityViewContext<CraftGenerationAttributes>) -> some View {
        HStack(spacing: 14) {
            mascot(context, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(CraftActivityText.title(kind: context.attributes.kind, chinese: context.attributes.chinese))
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                Text(headline(context)).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                progress(context)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func mascot(_ context: ActivityViewContext<CraftGenerationAttributes>, size: CGFloat) -> some View {
        Image(CraftActivityText.frameName(context.attributes.mascot, context.state.phase, context.state.frame))
            .resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func progress(_ context: ActivityViewContext<CraftGenerationAttributes>) -> some View {
        if context.state.finished || context.state.failed {
            Text(context.attributes.chinese ? (context.state.failed ? "未消耗的代币已退回。" : "在 3D Craft 中查看")
                                            : (context.state.failed ? "Unused Tokens were released." : "Open in 3D Craft"))
                .font(.caption2).foregroundStyle(.white.opacity(0.7))
        } else {
            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear).tint(.white)
        }
    }

    private func headline(_ context: ActivityViewContext<CraftGenerationAttributes>) -> String {
        CraftActivityText.headline(context.state, kind: context.attributes.kind, chinese: context.attributes.chinese)
    }

    private func percent(_ context: ActivityViewContext<CraftGenerationAttributes>) -> String {
        context.state.failed ? "—" : "\(Int((context.state.progress * 100).rounded()))%"
    }
}

@main
struct CraftStudioWidgetsBundle: WidgetBundle {
    var body: some Widget { GenerationLiveActivity() }
}
