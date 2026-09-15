import SwiftUI
import PhotosUI

// =====================================================================
// MARK: - 3D Craft — "Lit Studio" motion & surface vocabulary
// =====================================================================
//
// One direction, three rules.
//
// 1. LIGHT IS THE DECORATION. Separation comes from gradients, rim light
//    and two-layer shadows — never from borders, never from animated blur.
// 2. MASS MOVES DELIBERATELY. Springs are high damping and long response, so
//    motion reads as an object being carried. Exactly one bouncy token
//    (`pop`) exists and it is reserved for confirmations.
// 3. THE APP IS NEVER DEAD, AND NEVER BUSY. Every screen carries a slow,
//    low-amplitude ambient layer (drifting accent shapes, a breathing podium
//    rim) under a fast, precise interaction layer.
//
// Reduce Motion is a first-class design, not a fallback: the app still
// *responds* through cross-fades, colour, weight and haptics — it just does
// not travel. Every modifier in this file reads the accessibility
// environment itself, so callers get correct behaviour for free.
//
// =====================================================================

// MARK: - Tokens

/// Every animation in 3D Craft comes from this table. Screens never write
/// literal spring numbers; they name an intent.
enum CraftMotion {

    // ---- Interaction layer (fast, precise) ----------------------------

    /// Colour, tint, opacity and divider cross-fades. Never geometry.
    static let brush = Animation.easeOut(duration: 0.18)

    /// THE universal Reduce Motion substitute. A pure cross-fade.
    static let fade = Animation.easeInOut(duration: 0.22)

    /// Press down / release.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.86)

    /// Selection chips, segmented chip travel, focus rings, tool buttons,
    /// step badges. Fast, essentially no overshoot.
    static let snap = Animation.spring(response: 0.34, dampingFraction: 0.82)

    /// THE ONLY BOUNCY TOKEN. Confirmations only — a concept chosen, a step
    /// completed, a favourite added, a check badge landing, an accent shape
    /// arriving. Never for layout.
    static let pop = Animation.spring(response: 0.38, dampingFraction: 0.62)

    // ---- Structural layer (carried, not thrown) -----------------------

    /// Layout changes, disclosure expansion, tab indicator, grid re-flow,
    /// connector fills, bottom panels.
    static let glide = Animation.spring(response: 0.52, dampingFraction: 0.88)

    /// The one big move per screen. Hero stage arrival, model reveal, theme
    /// dissolve, full-screen. Reads as mass, never as spring.
    static let cinema = Animation.spring(response: 0.72, dampingFraction: 0.90)

    /// Staggered content arrivals. Deliberately a curve, not a spring — a
    /// list of eight cards must not wobble.
    static let arrive = Animation.timingCurve(0.22, 0.61, 0.36, 1.0, duration: 0.58)

    // ---- Data (curves only) -------------------------------------------

    /// Reported progress and numeric rolls. A spring would overshoot past the
    /// percentage the backend actually reported, which would be a lie.
    static let meter = Animation.easeOut(duration: 0.45)

    /// One-shot decorative reveals: podium rim, halo bloom, ring trims.
    static let reveal = Animation.easeOut(duration: 0.50)

    // ---- Ambient loops (always gated) ---------------------------------

    /// Specular band travel across an armed CTA.
    static let sweep = Animation.easeInOut(duration: 1.10)
    /// Loading shimmer, one pass.
    static let shimmer = Animation.linear(duration: 1.25)
    /// One revolution of an orbiting progress arc.
    static let orbit = Animation.linear(duration: 1.60)
    /// One pass of light travelling down a pipeline connector.
    static let travel = Animation.easeInOut(duration: 1.20)
    /// Decorative drift / breathe. Siblings must use different periods.
    static func drift(_ period: Double) -> Animation {
        .easeInOut(duration: period).repeatForever(autoreverses: true)
    }

    // ---- Stagger -------------------------------------------------------

    static let staggerStep: Double = 0.06
    static let staggerCap: Int = 9

    /// Entrance delay for item `index`, capped so a long list never keeps
    /// the user waiting. index 0…9 → 0…0.54 s.
    static func stagger(_ index: Int, step: Double = staggerStep) -> Double {
        Double(min(max(index, 0), staggerCap)) * step
    }

    /// The staggered arrival animation for item `index`.
    static func arrival(_ index: Int, step: Double = staggerStep) -> Animation {
        arrive.delay(stagger(index, step: step))
    }

    // ---- Named tokens -------------------------------------------------

    /// The names a screen file uses. Leading-dot syntax resolves against this
    /// type, which is what makes `CraftMotion.gated(.pop, reduceMotion)` legal
    /// and what stops anyone typing a raw spring into a view body.
    enum Token {
        case brush, fade, press, snap, pop, glide, cinema, arrive, meter, reveal

        var animation: Animation {
            switch self {
            case .brush:  return CraftMotion.brush
            case .fade:   return CraftMotion.fade
            case .press:  return CraftMotion.press
            case .snap:   return CraftMotion.snap
            case .pop:    return CraftMotion.pop
            case .glide:  return CraftMotion.glide
            case .cinema: return CraftMotion.cinema
            case .arrive: return CraftMotion.arrive
            case .meter:  return CraftMotion.meter
            case .reveal: return CraftMotion.reveal
            }
        }
    }

    // ---- The single Reduce Motion decision point ------------------------

    /// The ONLY sanctioned way to apply a token from a screen file.
    ///
    ///     withAnimation(CraftMotion.gated(.pop, reduceMotion)) { … }
    ///     .animation(CraftMotion.gated(.snap, reduceMotion), value: selection)
    ///
    /// Pass `reduced: nil` for "do not animate at all" under Reduce Motion.
    static func gated(_ token: Token,
                      _ reduceMotion: Bool,
                      reduced: Animation? = fade) -> Animation? {
        reduceMotion ? reduced : token.animation
    }

    /// The same gate for a token you have already decorated (`.delay`,
    /// `.speed`) or for one of the ambient curves.
    static func gated(_ animation: Animation,
                      _ reduceMotion: Bool,
                      reduced: Animation? = fade) -> Animation? {
        reduceMotion ? reduced : animation
    }
}

// MARK: - The ambient gate

private struct CraftAmbientMotionKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// An *additional* suppression switch for continuous ambient loops
    /// (backgrounded scene, Low Power Mode). It defaults to `true` and every
    /// modifier in this file ANDs it with its own Reduce Motion / Increase
    /// Contrast checks — so behaviour is already correct if nobody installs it.
    var craftAmbientMotion: Bool {
        get { self[CraftAmbientMotionKey.self] }
        set { self[CraftAmbientMotionKey.self] = newValue }
    }
}

/// Optional. Attach once to a screen root (or `CraftRoot`) to stop every
/// ambient loop in the tree while the app is backgrounded or in Low Power Mode.
private struct CraftAmbientHost: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    func body(content: Content) -> some View {
        content
            .environment(\.craftAmbientMotion, scenePhase == .active && !lowPower)
            .onReceive(NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange)) { _ in
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
    }
}

extension View {
    /// Suspends every `craftFloat` / `craftBreathe` / `craftShimmer` /
    /// `craftSpecularSweep` loop below this view while the scene is inactive
    /// or Low Power Mode is on.
    func craftAmbientHost() -> some View { modifier(CraftAmbientHost()) }
}

// MARK: - Palette bridge

/// Neutral surfaces. Colour comes from `CraftAppearance`.
enum CraftTheme {
    /// Page ground.
    static let background = Color.white
    /// The quiet neutral panel behind inputs, thumbnails and chips.
    static let panel = StudioAtmosphere.surface
    /// A raised card that must separate from the wash.
    static let card = Color.white
    /// Hairline on white.
    static let hairline = Color.black.opacity(0.06)
    /// The ink used by hairline strokes on cards.
    static let stroke = Color.black.opacity(0.055)
}

// MARK: - Depth

enum CraftDepth {
    /// Thumbnails, chips, small tiles.
    case card
    /// Circular stage tools, prompt field, appearance rows.
    case raised
    /// Bottom action panels, the tab bar, the segmented control.
    case floating
    /// The primary CTA and the hero stage — an accent-tinted bloom.
    case hero
}

private struct CraftDepthModifier: ViewModifier {
    let level: CraftDepth
    let tint: Color

    func body(content: Content) -> some View {
        switch level {
        case .card:
            content
                .shadow(color: .black.opacity(0.030), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.050), radius: 10, y: 4)
        case .raised:
            content
                .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                .shadow(color: .black.opacity(0.065), radius: 16, y: 7)
        case .floating:
            content
                .shadow(color: .black.opacity(0.040), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.085), radius: 24, y: 12)
        case .hero:
            content
                .shadow(color: .black.opacity(0.040), radius: 4, y: 2)
                .shadow(color: tint.opacity(0.38), radius: 22, y: 11)
        }
    }
}

extension View {
    /// Two-layer shadows the way iOS does them: one tight contact shadow, one
    /// wide ambient shadow. **Radius is constant and never animated.**
    func craftDepth(_ level: CraftDepth, tint: Color = .black) -> some View {
        modifier(CraftDepthModifier(level: level, tint: tint))
    }
}

// MARK: - Surfaces

enum CraftSurface {
    /// Inputs, prompt chips, quiet tiles — panel fill, no shadow.
    case sunken
    /// Cards and rows — white with a card shadow.
    case raised
    /// Bottom panels and bars — white with a floating shadow.
    case floating
    /// Selected rows and chips — accent wash, no shadow.
    case washed
}

private struct CraftSurfaceModifier: ViewModifier {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let level: CraftSurface
    let cornerRadius: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        switch level {
        case .sunken:
            content.background(CraftTheme.panel, in: shape)
        case .raised:
            content.background(CraftTheme.card, in: shape)
                .overlay(shape.strokeBorder(CraftTheme.stroke))
                .craftDepth(.card)
        case .floating:
            content.background(CraftTheme.card, in: shape)
                .overlay(shape.strokeBorder(CraftTheme.stroke))
                .craftDepth(.floating)
        case .washed:
            content.background(appearance.wash, in: shape)
        }
    }
}

extension View {
    /// The four surface levels the whole app is built from.
    func craftSurface(_ level: CraftSurface, cornerRadius: CGFloat = 24) -> some View {
        modifier(CraftSurfaceModifier(level: level, cornerRadius: cornerRadius))
    }

    /// The standard content panel. Existing zero-argument call sites keep working.
    /// It deliberately skips `craftSurface`'s hairline: `studioScrollFocus`
    /// already draws the illuminated edge, and two stacked strokes read muddy.
    func craftPanel(_ cornerRadius: CGFloat = 24) -> some View {
        padding(18)
            .background(CraftTheme.card,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .craftDepth(.card)
            .studioScrollFocus(cornerRadius: cornerRadius)
    }
}

// MARK: - Entrance & stagger

enum CraftEntranceStyle {
    /// Rises from below. The default for stacked sections.
    case rise
    /// Scales up from 0.90 with the one bouncy token. Hero cards, badges.
    case popIn
    /// Slides in from the leading edge.
    case slideLeading
    /// Slides in from the trailing edge. Right-hand tool stacks.
    case slideTrailing
    /// Scales down from 1.05 with `cinema`. Hero stages, full-screen content.
    case reveal
    /// Cross-fade only, still staggered.
    case fade
}

private struct CraftEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    let style: CraftEntranceStyle
    let distance: CGFloat
    let step: Double
    @State private var shown = false

    private var animation: Animation {
        switch style {
        case .popIn: return CraftMotion.pop
        case .reveal: return CraftMotion.cinema
        default: return CraftMotion.arrive
        }
    }
    private var rest: Bool { shown || reduceMotion }
    private var offsetY: CGFloat {
        guard !rest, style == .rise else { return 0 }
        return distance
    }
    private var offsetX: CGFloat {
        guard !rest else { return 0 }
        switch style {
        case .slideLeading: return -distance
        case .slideTrailing: return distance
        default: return 0
        }
    }
    private var scale: CGFloat {
        guard !rest else { return 1 }
        switch style {
        case .popIn: return 0.90
        case .reveal: return 1.05
        default: return 1
        }
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(scale, anchor: .center)
            .offset(x: offsetX, y: offsetY)
            .onAppear {
                guard !shown else { return }
                let delay = CraftMotion.stagger(index, step: step)
                if reduceMotion {
                    // A sequenced fade is not vestibular motion; the reading
                    // order is worth keeping. The stagger is compressed.
                    withAnimation(CraftMotion.fade.delay(min(delay, 0.18))) { shown = true }
                } else {
                    withAnimation(animation.delay(delay)) { shown = true }
                }
            }
    }
}

extension View {
    /// Staggered arrival. `index` is the item's position in its section;
    /// the delay is `min(index, 9) × 60 ms`.
    ///
    /// Reduce Motion: opacity only, no offset, no scale, stagger capped at 0.18 s.
    ///
    /// **Never** apply to an ancestor of a focusable `TextField` — the offset
    /// causes caret jitter. Wrap a sibling instead.
    func craftEntrance(_ index: Int = 0,
                       style: CraftEntranceStyle = .rise,
                       distance: CGFloat = 18,
                       step: Double = CraftMotion.staggerStep) -> some View {
        modifier(CraftEntrance(index: index, style: style, distance: distance, step: step))
    }
}

// MARK: - Press feedback

/// The default press style. Buttons shrink slightly and dim.
struct CraftPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.965
    var dim: Double = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(CraftMotion.gated(.press, reduceMotion, reduced: CraftMotion.brush),
                       value: configuration.isPressed)
    }
}

/// Cards that lift toward the finger instead of shrinking away from it —
/// thumbnails, concept cards, asset tiles, game covers.
struct CraftLiftStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 1.035
    var dim: Double = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? dim : 1)
            .animation(CraftMotion.gated(.press, reduceMotion, reduced: CraftMotion.brush),
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CraftPressStyle {
    static var craftPress: CraftPressStyle { .init() }
}
extension ButtonStyle where Self == CraftLiftStyle {
    static var craftLift: CraftLiftStyle { .init() }
}

extension View {
    /// Press feedback for surfaces that are not `Button`s (rows driven by a
    /// gesture, a card that owns its own tap handling).
    func craftPressFeedback(_ isPressed: Bool, scale: CGFloat = 0.965) -> some View {
        modifier(CraftPressFeedback(isPressed: isPressed, scale: scale))
    }
}

private struct CraftPressFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isPressed: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1)
            .opacity(isPressed ? 0.92 : 1)
            .animation(CraftMotion.gated(.press, reduceMotion, reduced: CraftMotion.brush),
                       value: isPressed)
    }
}

// MARK: - The primary CTA

/// The app's one primary action: a full-width capsule carrying a real
/// three-stop accent gradient, an inner top highlight and an accent-tinted
/// bloom. Matches every CTA in the mockups.
struct CraftPrimary: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var isEnabled
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    /// `true` once the button can meaningfully be pressed (a prompt exists, a
    /// concept is chosen). Runs the one-shot specular sweep that says "go".
    var armed: Bool = false
    /// `true` while the action is in flight. Suppresses the sweep.
    var busy: Bool = false
    var verticalPadding: CGFloat = 19
    var cornerRadius: CGFloat = 1000

    private var sweeps: Bool {
        armed && !busy && isEnabled && !reduceMotion && ambient && contrast != .increased
    }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(appearance.buttonInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(appearance.gradient, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.58), .white.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .craftSpecularSweep(active: sweeps, cornerRadius: 40)
            .craftDepth(.hero, tint: appearance.deep)
            .scaleEffect(pressed && !reduceMotion ? 0.972 : 1)
            .opacity(pressed ? 0.90 : (isEnabled ? 1 : 0.55))
            .animation(CraftMotion.gated(.press, reduceMotion, reduced: CraftMotion.brush),
                       value: pressed)
    }
}

/// The quieter accent action — "Refine this concept", "Start a character".
struct CraftSecondary: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(appearance.ink)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .background(appearance.wash, in: Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(CraftMotion.gated(.press, reduceMotion, reduced: CraftMotion.brush),
                       value: configuration.isPressed)
    }
}

// MARK: - Light: glow, sweep, shimmer

private struct CraftGlow: ViewModifier {
    let color: Color
    let active: Bool
    let radius: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                RadialGradient(
                    colors: [color.opacity(active ? opacity : 0),
                             color.opacity(active ? opacity * 0.34 : 0),
                             .clear],
                    center: .center, startRadius: 0, endRadius: radius)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(CraftMotion.gated(.glide, reduceMotion), value: active)
    }
}

extension View {
    /// A soft accent halo built from a radial gradient, **not** `.blur()`, so
    /// it is free to composite next to the live SceneKit stage. Animates only
    /// when `active` flips — never continuously.
    func craftGlow(_ color: Color,
                   active: Bool = true,
                   radius: CGFloat = 70,
                   opacity: Double = 0.28) -> some View {
        modifier(CraftGlow(color: color, active: active, radius: radius, opacity: opacity))
    }
}

private struct CraftSpecularSweep: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    let active: Bool
    let cornerRadius: CGFloat
    let hold: Double
    let tintOpacity: Double
    @State private var x: CGFloat = -1.4

    private var runs: Bool { active && !reduceMotion && ambient }

    func body(content: Content) -> some View {
        content.overlay {
            // The repeating animation is structurally unreachable when the
            // gate is closed: the overlay is never inserted.
            if runs {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(tintOpacity), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(1, geo.size.width * 0.45))
                        .rotationEffect(.degrees(14))
                        .offset(x: x * geo.size.width)
                        .blendMode(.plusLighter)
                }
                .clipShape(Capsule(style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    x = -1.4
                    withAnimation(CraftMotion.sweep
                        .delay(0.25)
                        .repeatForever(autoreverses: false)
                        .speed(1.10 / (1.10 + hold))) { x = 1.4 }
                }
            }
        }
    }
}

extension View {
    /// A 22 %-white band that sweeps diagonally across an armed capsule, then
    /// holds. It is the button saying "you can go now" without a word of copy.
    /// Reduce Motion, Increase Contrast or a backgrounded scene: absent.
    func craftSpecularSweep(active: Bool,
                            cornerRadius: CGFloat = 40,
                            hold: Double = 3.4,
                            tintOpacity: Double = 0.22) -> some View {
        modifier(CraftSpecularSweep(active: active, cornerRadius: cornerRadius,
                                    hold: hold, tintOpacity: tintOpacity))
    }
}

private struct CraftShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    let active: Bool
    let cornerRadius: CGFloat
    let base: Color
    @State private var x: CGFloat = -0.8

    private var runs: Bool { active && !reduceMotion && ambient }

    func body(content: Content) -> some View {
        content
            .background {
                if active {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(base)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if runs {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(1, geo.size.width * 0.42))
                            .offset(x: x * geo.size.width)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .onAppear {
                        x = -0.8
                        withAnimation(CraftMotion.shimmer.repeatForever(autoreverses: false)) {
                            x = 1.3
                        }
                    }
                }
            }
    }
}

extension View {
    /// Loading placeholders only — never over the SceneKit stage, and never on
    /// more than one visible surface at a time.
    /// Reduce Motion: a flat `base` plate with no travelling band.
    func craftShimmer(active: Bool,
                      cornerRadius: CGFloat = 20,
                      base: Color = CraftTheme.panel) -> some View {
        modifier(CraftShimmer(active: active, cornerRadius: cornerRadius, base: base))
    }
}

// MARK: - Ambient: breathe & float

private struct CraftBreathe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    @Environment(\.colorSchemeContrast) private var contrast
    let active: Bool
    let from: Double
    let to: Double
    let period: Double
    @State private var lit = false

    private var runs: Bool {
        active && !reduceMotion && ambient && contrast != .increased
    }

    func body(content: Content) -> some View {
        content
            .opacity(active ? (runs && lit ? to : (runs ? from : to)) : 0)
            .onAppear { start() }
            .onChange(of: runs) { _, _ in start() }
    }

    private func start() {
        if runs {
            lit = false
            withAnimation(CraftMotion.drift(period)) { lit = true }
        } else {
            withAnimation(nil) { lit = false }
        }
    }
}

extension View {
    /// Opacity-only breathing. **Never** touches radius, blur or scale, so it
    /// is safe directly behind the live SceneKit stage. Podium rim light, halo
    /// ring, an active status dot.
    /// Reduce Motion / Increase Contrast / background: held at `to`.
    func craftBreathe(active: Bool = true,
                      from: Double = 0.55,
                      to: Double = 0.85,
                      period: Double = 4.2) -> some View {
        modifier(CraftBreathe(active: active, from: from, to: to, period: period))
    }
}

private struct CraftFloat: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient
    let active: Bool
    let amplitude: CGFloat
    let tilt: Double
    let period: Double
    let delay: Double
    @State private var lifted = false

    private var runs: Bool { active && !reduceMotion && ambient }

    func body(content: Content) -> some View {
        content
            .offset(y: runs ? (lifted ? -amplitude : amplitude) : 0)
            .rotationEffect(.degrees(runs ? (lifted ? tilt : -tilt) : 0))
            .onAppear { start() }
            .onChange(of: runs) { _, _ in start() }
    }

    private func start() {
        if runs {
            lifted = false
            withAnimation(CraftMotion.drift(period).delay(delay)) { lifted = true }
        } else {
            withAnimation(nil) { lifted = false }
        }
    }
}

extension View {
    /// Slow decorative drift for the accent shapes and the hero stage.
    /// Siblings on one screen MUST use different periods (5.2 / 6.7) or they
    /// sync into a metronome.
    /// Reduce Motion / background: static at identity, no loop installed.
    func craftFloat(active: Bool = true,
                    amplitude: CGFloat = 8,
                    tilt: Double = 3,
                    period: Double = 5.4,
                    delay: Double = 0) -> some View {
        modifier(CraftFloat(active: active, amplitude: amplitude, tilt: tilt,
                            period: period, delay: delay))
    }
}

// MARK: - Selection, symbols, numerals

private struct CraftSelectionRing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool
    let color: Color
    let cornerRadius: CGFloat
    let lineWidth: CGFloat
    let glow: Bool

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? color : .clear, lineWidth: isSelected ? lineWidth : 0)
                    .accessibilityHidden(true)
            )
            .shadow(color: (glow && isSelected && !reduceMotion) ? color.opacity(0.40) : .clear,
                    radius: 20, y: 9)
            .animation(CraftMotion.gated(.snap, reduceMotion), value: isSelected)
    }
}

extension View {
    /// The accent border (plus optional bloom) that identifies a chosen card.
    /// It is the ONE cue that survives Reduce Motion, so it must never be the
    /// only difference removed there.
    func craftSelectionRing(_ isSelected: Bool,
                            color: Color,
                            cornerRadius: CGFloat,
                            lineWidth: CGFloat = 2,
                            glow: Bool = true) -> some View {
        modifier(CraftSelectionRing(isSelected: isSelected, color: color,
                                    cornerRadius: cornerRadius,
                                    lineWidth: lineWidth, glow: glow))
    }

    /// Bounces an SF Symbol when `trigger` changes. Under Reduce Motion the
    /// trigger is frozen, so the effect never fires — no `if` branch, and
    /// therefore no view-identity churn mid-scroll.
    func craftSymbolPop<T: Hashable>(_ trigger: T, reduceMotion: Bool) -> some View {
        symbolEffect(.bounce.up,
                     options: .speed(1.3),
                     value: reduceMotion ? AnyHashable(0) : AnyHashable(trigger))
    }

    /// A rolling numeral. Reduce Motion degrades to a plain cross-fade.
    /// Always driven by `meter` (a curve) so a reported figure can never
    /// overshoot into a number the backend did not send.
    func craftNumeric<V: Equatable>(_ value: V, reduceMotion: Bool) -> some View {
        monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(CraftMotion.gated(.meter, reduceMotion), value: value)
    }
}

// MARK: - Scroll: reveal, carousel, parallax

private struct CraftScrollReveal: ViewModifier {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let cornerRadius: CGFloat
    let dim: Double
    let scale: CGFloat
    let lift: CGFloat

    private var enhanced: Bool { contrast == .increased }

    func body(content: Content) -> some View {
        let quiet = reduceMotion || enhanced
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: enhanced
                                ? [.black.opacity(0.42), .black.opacity(0.28)]
                                : [appearance.fill.opacity(0.22), .black.opacity(0.06),
                                   appearance.fill.opacity(0.26)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .scrollTransition(.interactive, axis: .vertical) { effect, phase in
                let k = min(1, abs(phase.value))
                return effect
                    .opacity(quiet ? 1 - 0.20 * k : 1 - dim * k)
                    .scaleEffect(quiet ? 1 : 1 - scale * k)
                    .offset(y: quiet ? 0 : phase.value * lift)
            }
    }
}

extension View {
    /// Vertical depth for cards inside a `ScrollView`: an illuminated 1 pt
    /// edge, plus opacity / scale / lift as the card crosses the viewport
    /// boundary. Reduce Motion or Increase Contrast: opacity only.
    func craftScrollReveal(cornerRadius: CGFloat = 24,
                           dim: Double = 0.32,
                           scale: CGFloat = 0.04,
                           lift: CGFloat = 10) -> some View {
        modifier(CraftScrollReveal(cornerRadius: cornerRadius, dim: dim,
                                   scale: scale, lift: lift))
    }
}

private struct CraftCarouselItem: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let scale: CGFloat
    let dim: Double
    let yaw: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        let quiet = reduceMotion || contrast == .increased
        content.scrollTransition(.interactive, axis: .horizontal) { effect, phase in
            let k = min(1, abs(phase.value))
            return effect
                .scaleEffect(quiet ? 1 : 1 - scale * k)
                .opacity(quiet ? 1 - 0.22 * k : 1 - dim * k)
                .blur(radius: quiet ? 0 : blur * k)
                .rotation3DEffect(.degrees(quiet ? 0 : Double(phase.value) * -yaw),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
    }
}

extension View {
    /// Cinematic horizontal carousel: neighbours sit back, tilt away and
    /// soften; the centred card is full size and sharp.
    ///
    /// The `blur` argument is a **scroll-phase-derived static value per frame**,
    /// not an animated radius — but it still costs an offscreen pass, so pass
    /// `blur: 0` on any screen that also hosts a live `ModelViewport`.
    /// Reduce Motion / Increase Contrast: opacity only; the accent ring alone
    /// then carries the selection.
    func craftCarouselItem(scale: CGFloat = 0.12,
                           dim: Double = 0.36,
                           yaw: Double = 8,
                           blur: CGFloat = 0) -> some View {
        modifier(CraftCarouselItem(scale: scale, dim: dim, yaw: yaw, blur: blur))
    }
}

/// Publishes downward scroll distance in whole points, 0 at rest.
struct CraftScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

extension View {
    /// Attach to the content root **inside** a `ScrollView`, then read it with
    /// `.onPreferenceChange(CraftScrollOffsetKey.self) { scrollY = $0 }`.
    func craftScrollProbe() -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CraftScrollOffsetKey.self,
                    value: (-geo.frame(in: .scrollView(axis: .vertical)).minY).rounded())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
    }

    /// A depth plane. Positive `strength` lags the page; negative leads it.
    /// Four planes from three cheap transforms is the whole illusion.
    /// Reduce Motion: identity.
    func craftParallax(_ strength: CGFloat,
                       offset: CGFloat,
                       limit: CGFloat = 72) -> some View {
        modifier(CraftParallax(strength: strength, offset: offset, limit: limit))
    }
}

private struct CraftParallax: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let strength: CGFloat
    let offset: CGFloat
    let limit: CGFloat

    func body(content: Content) -> some View {
        let shift = reduceMotion ? 0 : max(-limit, min(limit, offset * strength))
        return content
            .offset(y: shift)
            // Scroll-driven values must never inherit an ambient animation, or
            // the plane rubber-bands behind the finger.
            .animation(nil, value: offset)
    }
}

// MARK: - Haptics

/// Every haptic in the app comes from this table; no screen writes a literal.
///
/// **Haptics are NOT gated on Reduce Motion.** Reduce Motion is a motion
/// setting, not a haptic setting, and haptics are the channel that carries
/// confirmation once travel is removed. The system's own haptics preference is
/// respected by `sensoryFeedback` automatically.
enum CraftFeedback {
    case tabChange, optionSelect, cardSelect, primaryAction, lightTap
    case referenceAttached, referenceRemoved, favoriteOn, favoriteOff
    case stepAdvance, jobStarted, jobSucceeded, jobFailed, jobWarning
    case viewReset, stageToggle, themeChange, modelReady, purchaseSucceeded

    var sensory: SensoryFeedback {
        switch self {
        case .tabChange, .optionSelect, .favoriteOff: return .selection
        case .cardSelect: return .impact(flexibility: .soft, intensity: 0.70)
        case .primaryAction: return .impact(weight: .medium, intensity: 0.80)
        case .lightTap: return .impact(weight: .light, intensity: 0.50)
        case .stageToggle: return .impact(weight: .light, intensity: 0.65)
        case .referenceAttached: return .impact(flexibility: .solid, intensity: 0.70)
        case .referenceRemoved: return .impact(flexibility: .soft, intensity: 0.40)
        case .favoriteOn: return .impact(flexibility: .soft, intensity: 0.80)
        case .stepAdvance: return .impact(flexibility: .rigid, intensity: 0.45)
        case .viewReset: return .impact(flexibility: .rigid, intensity: 0.55)
        case .themeChange: return .impact(flexibility: .soft, intensity: 0.60)
        case .modelReady: return .impact(flexibility: .soft, intensity: 0.45)
        case .jobStarted: return .start
        case .jobWarning: return .warning
        case .jobFailed: return .error
        case .jobSucceeded, .purchaseSucceeded: return .success
        }
    }
}

extension View {
    /// Fires on *value change*. For imperative actions bind a `@State` counter
    /// incremented inside the action closure — never bind to `store.busy`,
    /// which flickers.
    func craftFeedback<T: Equatable>(_ event: CraftFeedback, trigger: T) -> some View {
        sensoryFeedback(event.sensory, trigger: trigger)
    }
}

// MARK: - Decorative shapes

/// The soft four-point star from the mockups: puffy tips, deeply concave sides.
struct CraftSparkShape: Shape {
    /// 0 = square, 1 = needle. The mockups read ≈ 0.30.
    var pinch: CGFloat = 0.30

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let cx = rx * pinch
        let cy = ry * pinch
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - ry))
        p.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y),
                       control: CGPoint(x: c.x + cx, y: c.y - cy))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry),
                       control: CGPoint(x: c.x + cx, y: c.y + cy))
        p.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y),
                       control: CGPoint(x: c.x - cx, y: c.y + cy))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry),
                       control: CGPoint(x: c.x - cx, y: c.y - cy))
        p.closeSubpath()
        return p
    }
}

/// The floating soft star. Decorative, hidden from accessibility, never
/// positioned over the centre of a `ModelViewport`.
struct CraftAccentStar: View {
    var size: CGFloat = 54
    var floats: Bool = true
    var period: Double = 5.2
    var delay: Double = 0
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        CraftSparkShape()
            .fill(appearance.accentGradient)
            .overlay {
                CraftSparkShape().fill(
                    RadialGradient(colors: [.white.opacity(0.72), .clear],
                                   center: UnitPoint(x: 0.34, y: 0.26),
                                   startRadius: 0, endRadius: size * 0.40))
            }
            .frame(width: size, height: size)
            // Constant radius. Never animated.
            .shadow(color: appearance.deep.opacity(0.28), radius: size * 0.22, y: size * 0.16)
            .craftFloat(active: floats, amplitude: size * 0.17, tilt: 4,
                        period: period, delay: delay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The rounded pastel cube from the mockups — a rounded square given volume by
/// two perspective rotations and a top-face highlight. No blur, no 3D geometry.
struct CraftAccentCube: View {
    var size: CGFloat = 58
    var floats: Bool = true
    var period: Double = 6.7
    var delay: Double = 0.4
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [appearance.lift, appearance.fill, appearance.deep],
                                 startPoint: .top, endPoint: .bottomTrailing))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.78), .white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: size * 0.46)
                    .padding(.horizontal, size * 0.07)
                    .padding(.top, size * 0.06)
            }
            .overlay(shape.strokeBorder(.white.opacity(0.34), lineWidth: 1))
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(-20), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(22), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .shadow(color: appearance.deep.opacity(0.30), radius: size * 0.24, y: size * 0.17)
            .craftFloat(active: floats, amplitude: size * 0.13, tilt: 3,
                        period: period, delay: delay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - The podium and the halo

/// The mockups' solid, softly lit podium: a contact pool, a side wall, a white
/// top disc and a breathing accent rim. Drawn in SwiftUI **behind** the
/// transparent `ModelViewport`, so it needs no SceneKit change and costs one
/// static gradient stack plus one opacity loop.
struct CraftPodium: View {
    /// The full width of the podium's major axis.
    var width: CGFloat
    /// 0 = the flat ground pool the Create mockup shows.
    /// 14 = the two-tier plinth the Studio mockup shows.
    var thickness: CGFloat = 0
    /// Drives the rim reveal and the breathing. Flip it true when the model
    /// reports it is on screen.
    var lit: Bool = true
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var minor: CGFloat { width * 0.26 }

    var body: some View {
        ZStack {
            // 1 — contact pool. A radial gradient, never a blur.
            Ellipse()
                .fill(RadialGradient(
                    colors: [appearance.deep.opacity(0.22), appearance.fill.opacity(0.08), .clear],
                    center: .center, startRadius: 0, endRadius: width * 0.55))
                .frame(width: width * 1.30, height: minor * 1.45)
                .offset(y: thickness + 8)

            if thickness > 0 {
                // 2 — side wall.
                Ellipse()
                    .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.93)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: minor)
                    .offset(y: thickness)
            }

            // 3 — top disc.
            Ellipse()
                .fill(appearance.podiumSurface)
                .frame(width: width * (thickness > 0 ? 0.94 : 1.0), height: minor)

            // 4 — the accent rim. Opacity-only breathing.
            Ellipse()
                .strokeBorder(appearance.podiumRim, lineWidth: 3)
                .frame(width: width * (thickness > 0 ? 0.94 : 1.0), height: minor)
                .craftBreathe(active: lit, from: 0.55, to: 0.85, period: 4.2)

            // 5 — rim bloom. Static blur: rasterised once, never animated.
            Ellipse()
                .strokeBorder(appearance.fill.opacity(0.50), lineWidth: 8)
                .frame(width: width * (thickness > 0 ? 0.94 : 1.0), height: minor)
                .blur(radius: 9)
                .craftBreathe(active: lit, from: 0.30, to: 0.60, period: 4.2)
        }
        .animation(CraftMotion.gated(.reveal, reduceMotion), value: lit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The hairline arc that blooms behind the character in the Studio mockup.
/// One ring, one bloom, one shot — then it holds a barely-there breathe.
struct CraftHalo: View {
    var diameter: CGFloat
    var lit: Bool = true
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RadialGradient(colors: [.clear, appearance.fill.opacity(0.20), .clear],
                           center: .center,
                           startRadius: diameter * 0.30, endRadius: diameter * 0.56)
                .frame(width: diameter * 1.18, height: diameter * 1.18)

            Circle()
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95),
                                            appearance.fill.opacity(0.45), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
        }
        .scaleEffect(lit || reduceMotion ? 1 : 0.94)
        .opacity(lit ? 1 : 0)
        .craftBreathe(active: lit, from: 0.62, to: 0.92, period: 5.0)
        .animation(CraftMotion.gated(.reveal, reduceMotion), value: lit)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - The hero stage

/// Decorative atmosphere around a fully framed native 3D scene.
/// Camera fitting owns the composition; no second podium or clipping overscan.
struct CraftHeroStage<Content: View>: View {
    /// Visible height of the stage.
    var height: CGFloat = 330
    /// The studio adds a halo; the physical platform lives in ModelViewport.
    var style: Style = .ground
    /// The two drifting accent shapes, in the margins only.
    var showsAccents: Bool = true
    /// Flip true once the model is on screen: rim, halo and bloom resolve.
    var lit: Bool = true
    /// Feed the screen's `scrollY` to give the stage its own depth plane.
    var scrollOffset: CGFloat = 0
    @ViewBuilder var content: () -> Content

    enum Style { case ground, podium, bare }

    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                if style == .podium {
                    CraftHalo(diameter: w * 1.02, lit: lit)
                        .offset(y: -height * 0.10)
                }

                // Decorative toys sit BEHIND the character, in the margins.
                if showsAccents {
                    CraftAccentStar(size: min(56, w * 0.15), period: 5.2)
                        .offset(x: -w * 0.34, y: -height * 0.04)
                        .craftParallax(0.30, offset: scrollOffset)
                    CraftAccentCube(size: min(60, w * 0.16), period: 6.7, delay: 0.4)
                        .offset(x: w * 0.33, y: height * 0.09)
                        .craftParallax(-0.10, offset: scrollOffset)
                }

                // ModelViewport owns the physical plinth and contact shadow.
                // A second screen-space podium separates from it during orbit.
                content()
                    .frame(width: w, height: height)
                    .frame(width: w, height: height)
                    .clipped()
            }
            .frame(width: w, height: height)
            .craftParallax(0.16, offset: scrollOffset)
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The one sparkle

/// The single confetti moment in the app, reserved for a job actually being
/// accepted. Ten particles, 0.72 s, one shot. Increment `trigger` to fire.
struct CraftSparkleBurst: View {
    let trigger: Int
    var tint: Color
    var count: Int = 10
    var radius: CGFloat = 62
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Rest state is the *spent* state: spread, scaled down and transparent.
    // Starting at false parks ten opaque particles on the button label until
    // the first tap.
    @State private var out = true

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let a = Double(i) / Double(count) * 2 * .pi
                Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "circle.fill")
                    .font(.system(size: i.isMultiple(of: 2) ? 13 : 5, weight: .bold))
                    .foregroundStyle(tint)
                    .offset(x: out ? CGFloat(cos(a)) * radius : 0,
                            y: out ? CGFloat(sin(a)) * radius : 0)
                    .scaleEffect(out ? 0.25 : 0.7)
                    .opacity(out ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .opacity(reduceMotion ? 0 : 1)
        .onChange(of: trigger) { _, _ in
            guard !reduceMotion else { return }
            out = false
            withAnimation(.easeOut(duration: 0.72)) { out = true }
        }
    }
}

// MARK: - The segmented control

/// Replaces the stock grey `UISegmentedControl`. A white capsule with an
/// accent chip that glides between segments via `matchedGeometryEffect`.
///
/// ACCESSIBILITY CONTRACT — do not break:
/// each option is a plain `Button` whose label is **only** `Text(title)`, so in
/// English the derived labels are exactly the titles passed in. The chip is a
/// sibling background applied to the `Button`, not part of its label. Never add
/// `.accessibilityElement(children: .combine)` to the container, never add an
/// icon to an option, never append "selected" to a label.
struct CraftSegmented<Tag: Hashable>: View {
    struct Option: Identifiable {
        let tag: Tag
        let title: String
        var id: Tag { tag }
        init(_ tag: Tag, _ title: String) { self.tag = tag; self.title = title }
    }

    let options: [Option]
    @Binding var selection: Tag
    var height: CGFloat = 48

    @Namespace private var chipSpace
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.tag) { index, option in
                let on = option.tag == selection
                Button {
                    selection = option.tag
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? appearance.ink : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if on {
                        Capsule(style: .continuous)
                            .fill(appearance.washStrong)
                            .matchedGeometryEffect(id: "craftSegmentChip", in: chipSpace)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .leading) {
                    if index > 0, !on, options[index - 1].tag != selection {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 1, height: 18)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white)
                .overlay(Capsule(style: .continuous).strokeBorder(CraftTheme.stroke))
                .craftDepth(.card)
        }
        .animation(CraftMotion.gated(.snap, reduceMotion), value: selection)
        .craftFeedback(.optionSelect, trigger: selection)
    }
}

// MARK: - The tab bar

/// The floating white bar from the mockups, with an accent capsule that glides
/// under the selected item.
///
/// ACCESSIBILITY CONTRACT — `tab.0` / `tab.1` / `tab.2` stay on the `Button`s
/// and each item keeps its visible `Text`, so the label predicates that match
/// "Library" / "Profile" / "资产库" keep matching. Never combine an item into a
/// single accessibility element.
struct CraftTabBar: View {
    struct Item {
        let icon: String
        let selectedIcon: String
        let label: String
        init(icon: String, selectedIcon: String? = nil, label: String) {
            self.icon = icon
            self.selectedIcon = selectedIcon ?? icon
            self.label = label
        }
    }

    let items: [Item]
    @Binding var selection: Int

    @Namespace private var chipSpace
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let on = selection == index
                Button {
                    selection = index
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Image(systemName: on ? item.selectedIcon : item.icon)
                                .font(.system(size: 20, weight: on ? .semibold : .regular))
                                .contentTransition(reduceMotion ? .opacity
                                                                : .symbolEffect(.replace.downUp))
                        }
                        .frame(height: 34)
                        Text(item.label)
                            .font(.caption.weight(on ? .semibold : .regular))
                    }
                    .foregroundStyle(on ? appearance.ink : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab." + String(index))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 3)
        .background(
            Color.white.opacity(0.94)
        )
        .overlay(alignment: .top) { Rectangle().fill(appearance.hairline).frame(height: 0.5) }
        .animation(CraftMotion.gated(.glide, reduceMotion), value: selection)
        .craftFeedback(.tabChange, trigger: selection)
    }
}

// MARK: - Circular stage tools

/// The crisp white circles the Studio mockup shows — not `.regularMaterial`.
/// Attach the caller's existing `.accessibilityIdentifier` at the call site.
struct CraftCircleTool: View {
    let icon: String
    let title: String
    var diameter: CGFloat = 46
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: diameter, height: diameter)
                .background(Color.white, in: Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.04)))
                .craftDepth(.raised)
        }
        .buttonStyle(CraftPressStyle(scale: 0.90))
        .accessibilityLabel(title)
    }
}

// MARK: - The prompt field

/// One rounded input field with a leading image icon, replacing the three
/// outlined boxes. The mockup's Create field.
///
/// ACCESSIBILITY CONTRACT — the leading control **is** the `PhotosPicker` and
/// carries a label containing "Photos" / "相册". `ReviewFlowTests` finds it on
/// the launch screen with no prior tap, so it must never move behind a `Menu`
/// or a `confirmationDialog`. Camera and Files stay top-level buttons too.
struct CraftPromptField: View {
    @Binding var text: String
    @Binding var photo: PhotosPickerItem?
    var placeholder: String
    var photosLabel: String
    var cameraLabel: String
    var filesLabel: String
    /// Non-nil once a reference image is attached; replaces the leading glyph
    /// with a thumbnail plus a clear button.
    var reference: UIImage? = nil
    var onCamera: () -> Void
    var onFiles: () -> Void
    var onClearReference: (() -> Void)? = nil

    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photo, matching: .images) {
                Group {
                    if let reference {
                        Image(uiImage: reference).resizable().scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20))
                            .foregroundStyle(focused ? appearance.ink : Color.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(photosLabel)

            TextField(placeholder, text: $text, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($focused)
                .accessibilityIdentifier("creationPrompt")

            if reference != nil, let onClearReference {
                Button(action: onClearReference) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CraftPressStyle(scale: 0.88))
            }

            Button(action: onCamera) {
                Image(systemName: "camera")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CraftPressStyle(scale: 0.88))
            .accessibilityLabel(cameraLabel)

            Button(action: onFiles) {
                Image(systemName: "folder")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CraftPressStyle(scale: 0.88))
            .accessibilityLabel(filesLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 60)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(focused ? appearance.fill : Color.black.opacity(0.07),
                              lineWidth: focused ? 1.5 : 1)
        )
        .craftGlow(appearance.fill, active: focused, radius: 60, opacity: 0.16)
        .craftDepth(.card)
        .animation(CraftMotion.gated(.snap, reduceMotion), value: focused)
    }
}

// MARK: - Empty state

/// The mockup-flavoured empty state: two drifting accent shapes over a title,
/// a message and an optional accent action.
struct CraftEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                CraftAccentStar(size: 40, period: 4.9).offset(x: -30, y: -6)
                CraftAccentCube(size: 34, period: 6.3, delay: 0.5).offset(x: 30, y: 10)
            }
            .frame(height: 92)
            .craftEntrance(0, style: .popIn)

            Text(title)
                .font(.title3.bold())
                .craftEntrance(1)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .craftEntrance(2)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(CraftSecondary())
                    .craftEntrance(3, style: .popIn)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

// MARK: - Section header

/// "Your creations  ·  View all ›" — the mockup's section rhythm.
struct CraftSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(appearance.ink)
                }
                .buttonStyle(CraftPressStyle())
            }
        }
    }
}
