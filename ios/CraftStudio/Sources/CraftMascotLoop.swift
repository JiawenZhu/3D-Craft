import AVFoundation
import SwiftUI
import UIKit

/// The three waiting moments the mascot performs. Each maps to a real job
/// state at the call site; none of them implies how far along the work is.
enum CraftMascotPhase: String {
    /// A short wait for a reply or a queue slot: blink, head tilt, a floating orb.
    case thinking
    /// Concept image generation: drawing glowing strokes in the air.
    case concept
    /// 3D generation: shaping a turning cube of light.
    case model
}

/// The theme's mascot: soft lavender is the blue Cloud Dragon, emerald green the
/// Panda Chef. Both are the app's own original concept art, animated with
/// Seedance 2.5 (see docs/design/mascot-animations).
extension CraftAppearance {
    var mascot: String { self == .lavender ? "dragon" : "panda" }
}

/// A looping, muted mascot clip used only as a waiting indicator.
///
/// Playback is gated like every other ambient loop in the app. It needs a live
/// job (`active`) and no Reduce Motion or Increase Contrast. It also needs the
/// ambient gate, which closes when the scene is backgrounded or the phone is in
/// Low Power Mode. When any condition fails, the clip pauses and the still
/// original artwork is shown instead, so nothing moves and nothing decodes.
/// Clips carry no audio track and the player is muted.
struct CraftMascotLoop: View {
    let phase: CraftMascotPhase
    var size: CGFloat
    /// Whether the job this indicator represents is actually still running.
    var active: Bool = true
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.craftAmbientMotion) private var ambient

    /// Below this size the head-and-shoulders thinking crop reads better than
    /// the full figure.
    private var compact: Bool { size < 80 }
    private var playing: Bool { active && !reduceMotion && ambient && contrast != .increased }
    /// Only the thinking clip has a head crop; other phases scale the full figure.
    private var cropped: Bool { compact && phase == .thinking }
    private var clip: String { "mascot-\(appearance.mascot)-\(phase.rawValue)" + (cropped ? "-small" : "") }
    private var poster: String { "mascot-\(appearance.mascot)-poster" + (cropped ? "-small" : "") }

    var body: some View {
        ZStack {
            Circle().fill(.white)
            // The still is the clip's first frame (the original art), and each
            // loop blends back into it, so still and motion hand off cleanly.
            if let image = Self.image(poster) {
                Image(uiImage: image).resizable().scaledToFill()
            }
            if playing, let url = Bundle.main.url(forResource: clip, withExtension: "mp4") {
                CraftLoopingVideo(url: url, playing: playing).id(clip)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(appearance.fill.opacity(contrast == .increased ? 0.9 : 0.45),
                                       lineWidth: compact ? 1 : 1.5))
        .accessibilityHidden(true)
        .accessibilityIdentifier("mascot.\(phase.rawValue)")
    }

    private static let posters = NSCache<NSString, UIImage>()
    private static func image(_ name: String) -> UIImage? {
        if let cached = posters.object(forKey: name as NSString) { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        posters.setObject(image, forKey: name as NSString)
        return image
    }
}

/// A gapless muted loop on a single `AVPlayerLayer`.
private struct CraftLoopingVideo: UIViewRepresentable {
    let url: URL
    let playing: Bool

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        // Hidden until a frame is ready so the poster underneath shows first.
        view.playerLayer.opacity = 0
        view.readyObservation = view.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { layer, _ in
            DispatchQueue.main.async { layer.opacity = layer.isReadyForDisplay ? 1 : 0 }
        }
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        guard let player = view.playerLayer.player else { return }
        if playing { player.play() } else { player.pause() }
    }

    static func dismantleUIView(_ view: PlayerView, coordinator: ()) {
        view.playerLayer.player?.pause()
        view.looper?.disableLooping()
        view.readyObservation = nil
        view.playerLayer.player = nil
        view.looper = nil
    }

    final class PlayerView: UIView {
        var looper: AVPlayerLooper?
        var readyObservation: NSKeyValueObservation?
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

#Preview("Mascot waiting indicators") {
    VStack(spacing: 24) {
        HStack(spacing: 10) {
            CraftMascotLoop(phase: .thinking, size: 36)
            Text("Thinking about your idea…").foregroundStyle(.secondary)
        }
        HStack(spacing: 20) {
            CraftMascotLoop(phase: .concept, size: 164)
            CraftMascotLoop(phase: .model, size: 164)
        }
        CraftMascotLoop(phase: .model, size: 164, active: false)
    }
    .padding()
}
