import SwiftUI

/// A visual preference only, stored locally without demographic information.
enum CraftAppearance: String, CaseIterable, Identifiable {
    case lavender, emerald
    static let storageKey = "craftAppearance"
    var id: String { rawValue }

    /// The brand mid-tone. Every wash and rim derives from it.
    var fill: Color {
        self == .lavender
            ? Color(red: 216/255, green: 161/255, blue: 241/255)
            : Color(red: 156/255, green: 220/255, blue: 195/255)
    }
    /// The light end of the ramp — gradient tops, podium rims, shape highlights.
    var lift: Color {
        self == .lavender
            ? Color(red: 238/255, green: 219/255, blue: 250/255)   // #EEDBFA
            : Color(red: 214/255, green: 242/255, blue: 231/255)   // #D6F2E7
    }
    /// The deep end — CTA gradient bottoms, glow shadows, shape shading.
    var deep: Color {
        self == .lavender
            ? Color(red: 176/255, green: 116/255, blue: 222/255)    // #B074DE
            : Color(red: 104/255, green: 194/255, blue: 160/255)    // #68C2A0
    }
    /// Body text and glyphs on accent surfaces.
    var ink: Color {
        self == .lavender
            ? Color(red: 104/255, green: 67/255, blue: 123/255)
            : Color(red: 28/255, green: 101/255, blue: 77/255)
    }
    /// Label colour on a filled accent button. ~5.4:1 on `deep`, ~6.9:1 emerald.
    var buttonInk: Color {
        self == .lavender
            ? Color(red: 48/255, green: 34/255, blue: 56/255)
            : Color(red: 18/255, green: 52/255, blue: 40/255)
    }

    /// Thumbnail tiles and quiet accent plates.
    var washSoft: Color { fill.opacity(0.10) }
    /// Selected rows, selected cards, the tab chip, the preview card.
    var wash: Color { fill.opacity(0.14) }
    /// The selected segment chip and the strongest accent plate.
    var washStrong: Color { fill.opacity(0.24) }
    /// 1 pt strokes on accent surfaces.
    var hairline: Color { fill.opacity(0.32) }

    /// A real three-stop ramp with the light source top-leading, the way iOS
    /// lights its own controls. This is what every CTA in the mockups shows.
    var gradient: LinearGradient {
        LinearGradient(colors: [lift, fill, deep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// The floating decorative shapes.
    var accentGradient: LinearGradient {
        LinearGradient(colors: [lift, fill, deep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// The podium's top surface: white, faintly cooled toward the front edge.
    var podiumSurface: LinearGradient {
        LinearGradient(colors: [.white, Color(white: 0.963)],
                       startPoint: .top, endPoint: .bottom)
    }
    /// The podium's rim: brand light wrapping a white core.
    var podiumRim: LinearGradient {
        LinearGradient(colors: [deep.opacity(0.75), .white.opacity(0.95), fill.opacity(0.60)],
                       startPoint: .leading, endPoint: .trailing)
    }

    func title(chinese: Bool) -> String {
        switch self {
        case .lavender: return chinese ? "柔雾紫" : "Soft lavender"
        case .emerald: return chinese ? "翡翠绿" : "Emerald green"
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t("Appearance", "外观"))
                .font(.title3.bold())
                .craftEntrance(0)
            Text(store.t("Choose the colors that feel like you.", "选择你喜欢的色彩。"))
                .font(.subheadline).foregroundStyle(.secondary)
                .craftEntrance(1)

            VStack(spacing: 10) {
                ForEach(Array(CraftAppearance.allCases.enumerated()), id: \.element) { index, option in
                    AppearanceRow(option: option,
                                  index: index,
                                  selected: appearance == option,
                                  chinese: store.isChinese,
                                  selectedWord: store.t("Selected", "已选择"),
                                  unselectedWord: store.t("Not selected", "未选择")) {
                        // One tap cross-dissolves every tinted surface in the app.
                        withAnimation(CraftMotion.gated(.cinema, reduceMotion)) {
                            appearance = option
                        }
                    }
                }
            }
            .animation(CraftMotion.gated(.pop, reduceMotion), value: appearance)
            .craftFeedback(.themeChange, trigger: appearance)

            Text(store.t("Applied immediately. Saved on this device. Change it anytime.",
                         "立即生效并保存在此设备，随时可以更换。"))
                .font(.caption).foregroundStyle(.secondary)
                .craftEntrance(4)
        }
    }
}

private struct AppearanceRow: View {
    let option: CraftAppearance
    let index: Int
    let selected: Bool
    let chinese: Bool
    let selectedWord: String
    let unselectedWord: String
    let choose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: choose) { row }
            .buttonStyle(CraftPressStyle(scale: 0.985))
            .craftEntrance(2 + index)
            .accessibilityIdentifier("appearance." + option.rawValue)
            .accessibilityLabel(option.title(chinese: chinese))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(selected ? selectedWord : unselectedWord)
    }

    private var row: some View {
        HStack(spacing: 16) {
            swatch
            Text(option.title(chinese: chinese))
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            check
        }
        .padding(.horizontal, 18)
        .frame(height: 74)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
    }

    private var swatch: some View {
        Circle()
            .fill(option.gradient)
            .frame(width: 38, height: 38)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
            .shadow(color: option.deep.opacity(0.28), radius: 7, y: 3)
    }

    private var check: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 26))
            // Palette, not hierarchical: the mockup's selected state is a SOLID
            // ink disc with a white tick. Hierarchical tints the disc to a pale
            // wash and leaves the tick dark, which reads as disabled.
            .symbolRenderingMode(selected ? .palette : .monochrome)
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.secondary.opacity(0.45)),
                             AnyShapeStyle(option.ink))
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace.offUp))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(selected ? AnyShapeStyle(option.wash) : AnyShapeStyle(Color.black.opacity(0.028)))
    }
}
