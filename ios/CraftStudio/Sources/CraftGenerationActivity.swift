import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// The Live Activity shown while a real creation job runs.
///
/// Live Activities render snapshots, so the mascot cannot play as video here.
/// `frame` steps through the stills exported by
/// `scripts/mascot/encode_mascot_loops.sh`, advancing only when the job itself
/// reports new state. The clip in the app is unchanged; this is a still that
/// keeps the same character company on the Lock Screen and Dynamic Island.
public enum CraftActivityMascot: String, Codable, Hashable, Sendable {
    case dragon, panda

    /// Matches `CraftMascotLoop`: lavender shows the cloud dragon, emerald the panda chef.
    public static func forTheme(emerald: Bool) -> CraftActivityMascot { emerald ? .panda : .dragon }
}

public enum CraftActivityPhase: String, Codable, Hashable, Sendable {
    case thinking, concept, model

    /// The same rule the in-app journey uses: a queued job only waits.
    public static func of(status: String, kind: String) -> CraftActivityPhase {
        if status == "queued" { return .thinking }
        return kind == "model" ? .model : .concept
    }
}

public struct CraftGenerationAttributes: Codable, Hashable, Sendable {
    public var jobId: String
    public var kind: String          // "model" or "concepts"
    public var projectId: String
    public var projectName: String
    public var mascot: CraftActivityMascot
    public var chinese: Bool

    public init(jobId: String, kind: String, projectId: String, projectName: String,
                mascot: CraftActivityMascot, chinese: Bool) {
        self.jobId = jobId; self.kind = kind; self.projectId = projectId
        self.projectName = projectName; self.mascot = mascot; self.chinese = chinese
    }

    public struct State: Codable, Hashable, Sendable {
        public var phase: CraftActivityPhase
        public var progress: Double      // 0...1
        public var frame: Int            // 1...6, the mascot still to show
        public var finished: Bool
        public var failed: Bool

        public init(phase: CraftActivityPhase, progress: Double, frame: Int,
                    finished: Bool = false, failed: Bool = false) {
            self.phase = phase; self.progress = min(max(progress, 0), 1)
            self.frame = frame; self.finished = finished; self.failed = failed
        }
    }
}

#if canImport(ActivityKit)
extension CraftGenerationAttributes: ActivityAttributes {
    public typealias ContentState = State
}
#endif

/// Wording shared by the app and the widget so both surfaces say the same thing.
public enum CraftActivityText {
    public static func headline(_ state: CraftGenerationAttributes.State, kind: String, chinese: Bool) -> String {
        if state.failed { return chinese ? "这次创作没有完成" : "This creation didn’t finish" }
        if state.finished { return kind == "model" ? (chinese ? "你的 3D 作品已就绪" : "Your 3D creation is ready")
                                                   : (chinese ? "你的概念图已就绪" : "Your concepts are ready") }
        switch state.phase {
        case .thinking: return chinese ? "灵感已进入队列，我们会持续更新进度。" : "Your idea is in line. We’ll keep you updated."
        case .model:    return chinese ? "正在让灵感成为三维……" : "Finding shape in your idea…"
        case .concept:  return chinese ? "一点点想象，正在成为作品……" : "A little imagination, coming to life…"
        }
    }

    public static func title(kind: String, chinese: Bool) -> String {
        kind == "model" ? (chinese ? "从你的图片到 3D" : "From your image to 3D")
                        : (chinese ? "让灵感逐渐成形" : "An idea taking shape")
    }

    public static func frameName(_ mascot: CraftActivityMascot, _ phase: CraftActivityPhase, _ frame: Int) -> String {
        "mascot-\(mascot.rawValue)-\(phase.rawValue)-\(min(max(frame, 1), 6))"
    }
}
