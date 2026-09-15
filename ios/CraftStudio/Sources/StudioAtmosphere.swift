import SwiftUI

/// A lit white studio. Light is the decorative material here: a top wash, two
/// key lights, a diagonal sheen and a settled floor, all theme-tinted and all
/// cheap enough to sit under a live SceneKit view.
///
/// Nothing here is time-driven. The only movement is the optional
/// `scrollProgress` drift, which is driven by the user's own finger and is
/// pinned to zero under Reduce Motion.
struct StudioAtmosphere: View {
    /// 1.0 for content screens. Push to 1.3 behind a hero stage, drop to 0.85
    /// behind a dense settings list.
    var intensity: Double = 1.0
    /// 0…1, from the screen's `craftScrollProbe`. Slides the two key lights a
    /// few percent so the background has its own depth plane.
    var scrollProgress: Double = 0

    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let charcoal = Color.white
    static let surface = Color(red: 248/255, green: 247/255, blue: 250/255)

    private var drift: Double {
        reduceMotion ? 0 : min(1, max(0, scrollProgress)) * 0.06
    }

    var body: some View {
        GeometryReader { geometry in
            let span = max(geometry.size.width, geometry.size.height)
            let i = intensity
            ZStack {
                Self.charcoal
                if contrast != .increased {
                    // 1 — the top wash both mockups open with.
                    LinearGradient(
                        colors: [appearance.fill.opacity(0.22 * i),
                                 appearance.fill.opacity(0.085 * i), .clear],
                        startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62)
                    )
                    // 2 — left key light.
                    RadialGradient(
                        colors: [appearance.fill.opacity(0.20 * i),
                                 appearance.fill.opacity(0.060 * i), .clear],
                        center: UnitPoint(x: 0.02, y: 0.10 + drift),
                        startRadius: 0, endRadius: span * 0.66
                    )
                    // 3 — right key light.
                    RadialGradient(
                        colors: [appearance.fill.opacity(0.16 * i),
                                 appearance.fill.opacity(0.048 * i), .clear],
                        center: UnitPoint(x: 1.05, y: 0.42 - drift * 0.7),
                        startRadius: 0, endRadius: span * 0.60
                    )
                    // 4 — the diagonal sheen across the upper right, visible in
                    //     both Profile mockups.
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55 * i), .clear],
                        startPoint: UnitPoint(x: 0.52, y: -0.02),
                        endPoint: UnitPoint(x: 1.06, y: 0.38)
                    )
                    .blendMode(.softLight)
                    // 5 — the settled white ground curve at the bottom of every
                    //     screen, which is what makes the character look placed.
                    RadialGradient(
                        colors: [Self.surface.opacity(0.95), .clear],
                        center: UnitPoint(x: 0.50, y: 0.94),
                        startRadius: 0, endRadius: span * 0.50
                    )
                }
            }
            // Switching theme cross-dissolves every stop above, app-wide.
            .animation(CraftMotion.gated(.cinema, reduceMotion), value: appearance)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Vertical depth for cards inside a `ScrollView`. Retained under its
    /// original name so existing call sites keep compiling; the body is now
    /// `craftScrollReveal`, which adds scale and lift on top of the
    /// illuminated edge and the opacity falloff.
    ///
    /// Reduce Motion and Increase Contrast both flatten it to opacity only.
    func studioScrollFocus(cornerRadius: CGFloat = 24) -> some View {
        craftScrollReveal(cornerRadius: cornerRadius)
    }
}
