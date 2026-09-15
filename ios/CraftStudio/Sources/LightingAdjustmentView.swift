import SwiftUI
import UIKit

/// Compact lighting dock. One stable slider stays under the finger while the
/// surrounding chrome fades, leaving the live model unobscured.
///
/// The `Done` and `Reset` labels are queried by two UI suites and must stay
/// exactly as written.
struct LightingAdjustmentView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let chinese: Bool
    var onClose: (() -> Void)? = nil
    var onFocusChange: (Bool) -> Void = { _ in }
    @Binding var directional: Double
    @Binding var environment: Double
    @Binding var exposure: Double
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resetCount = 0
    @State private var activeSlider: String?
    @State private var selectedControl = "lighting.directional"
    @Environment(\.scenePhase) private var scenePhase

    private func t(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    /// True while any dial sits away from its neutral position — the header
    /// lamp lights up so the sheet reports its own state.
    private var touched: Bool {
        abs(directional - 1) > 0.01 || abs(environment - 1) > 0.01 || abs(exposure - 1) > 0.01
    }

    var body: some View {
        VStack(spacing: 12) {
            header
                .opacity(activeSlider == nil ? 1 : 0)
                .allowsHitTesting(activeSlider == nil)
            HStack(spacing: 6) {
                controlTab("Key light", "主光", id: "lighting.directional")
                controlTab("Environment", "环境光", id: "lighting.environment")
                controlTab("Exposure", "曝光", id: "lighting.exposure")
            }
            .opacity(activeSlider == nil ? 1 : 0)
            .allowsHitTesting(activeSlider == nil)

            adjustment(controlTitle, icon: controlIcon, value: controlValue,
                       range: selectedControl == "lighting.exposure" ? 0.5...1.6 : 0...2,
                       id: selectedControl)
        }
        .padding(16)
        .background { StudioAtmosphere(intensity: 1.15).opacity(activeSlider == nil ? 1 : 0) }
        .animation(reduceMotion ? nil : .easeInOut(duration: activeSlider == nil ? 0.25 : 0.15), value: activeSlider)
        .onChange(of: scenePhase) { _, phase in if phase != .active { activeSlider = nil } }
        .onChange(of: activeSlider) { _, value in onFocusChange(value != nil) }
        .onDisappear { activeSlider = nil; onFocusChange(false) }
        .tint(appearance.ink)
        .preferredColorScheme(.light)
        .craftFeedback(.viewReset, trigger: resetCount)
        .craftAmbientHost()
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(appearance.ink)
                    .frame(width: 38, height: 38)
                    .background(appearance.washStrong, in: Circle())
                    .craftGlow(appearance.fill, active: touched, radius: 46, opacity: 0.30)
                    .accessibilityHidden(true)
            }

            Text(t("Lighting studio", "灯光工作室"))
                .font(.subheadline.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)
            Button {
                directional = 1; environment = 1; exposure = 1
                resetCount += 1
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(t("Reset", "重置"))
            .accessibilityIdentifier("lighting.reset")
            Button { if let onClose { onClose() } else { dismiss() } } label: {
                Text(t("Done", "完成"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(appearance.washStrong, in: Capsule())
            }
            .buttonStyle(CraftPressStyle())
            .accessibilityIdentifier("lighting.done")
        }
    }

    private var controlTitle: String {
        switch selectedControl {
        case "lighting.environment": return t("Environment fill", "环境柔光")
        case "lighting.exposure": return t("Exposure", "曝光")
        default: return t("Key & rim light", "主光与轮廓光")
        }
    }
    private var controlIcon: String {
        switch selectedControl {
        case "lighting.environment": return "circle.lefthalf.filled"
        case "lighting.exposure": return "camera.aperture"
        default: return "sun.max"
        }
    }
    private var controlValue: Binding<Double> {
        switch selectedControl {
        case "lighting.environment": return $environment
        case "lighting.exposure": return $exposure
        default: return $directional
        }
    }
    private func controlTab(_ en: String, _ zh: String, id: String) -> some View {
        Button { selectedControl = id } label: {
            Text(t(en, zh))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selectedControl == id ? appearance.washStrong : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id + ".select")
        .accessibilityAddTraits(selectedControl == id ? .isSelected : [])
    }

    private func adjustment(_ title: String,
                            icon: String,
                            value: Binding<Double>,
                            range: ClosedRange<Double>,
                            id: String) -> some View {
        let span = range.upperBound - range.lowerBound
        let level = span > 0 ? (value.wrappedValue - range.lowerBound) / span : 0
        let reading = value.wrappedValue.formatted(.number.precision(.fractionLength(2))) + "×"
        return VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(appearance.ink)
                    .frame(width: 28, height: 28)
                    .background(appearance.washSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(reading)
                    .font(.caption.monospaced())
                    .fixedSize()
                    .foregroundStyle(appearance.ink)
                    .craftNumeric(reading, reduceMotion: reduceMotion)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(appearance.fill.opacity(0.08 + 0.16 * level), in: Capsule())
                    .animation(CraftMotion.gated(.brush, reduceMotion), value: level)
            }
            LightingTrackingSlider(value: value, range: range, tint: UIColor(appearance.ink),
                                   title: title, identifier: id) { editing in
                activeSlider = editing ? id : nil
            }
            .frame(height: 44)

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .craftSurface(.raised, cornerRadius: 20)
        .opacity(activeSlider == nil || activeSlider == id ? 1 : 0)
    }
}

/// Track the complete touch lifecycle, including cancellation. SwiftUI's editing
/// callback can be lost when the surrounding presentation fades during a drag.
private struct LightingTrackingSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let tint: UIColor
    let title: String
    let identifier: String
    var editing: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> TrackingSlider {
        let slider = TrackingSlider()
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.trackingChanged = { [weak coordinator = context.coordinator] active in
            coordinator?.parent.editing(active)
        }
        return slider
    }
    func updateUIView(_ slider: TrackingSlider, context: Context) {
        context.coordinator.parent = self
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        if !slider.isTracking { slider.value = Float(value) }
        slider.minimumTrackTintColor = tint
        slider.accessibilityLabel = title
        slider.accessibilityIdentifier = identifier
    }
    final class Coordinator: NSObject {
        var parent: LightingTrackingSlider
        init(_ parent: LightingTrackingSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) { parent.value = Double(slider.value) }
    }
    final class TrackingSlider: UISlider {
        var trackingChanged: ((Bool) -> Void)?
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            let began = super.beginTracking(touch, with: event)
            if began { trackingChanged?(true) }
            return began
        }
        override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
            super.endTracking(touch, with: event)
            trackingChanged?(false)
        }
        override func cancelTracking(with event: UIEvent?) {
            super.cancelTracking(with: event)
            trackingChanged?(false)
        }
    }
}
