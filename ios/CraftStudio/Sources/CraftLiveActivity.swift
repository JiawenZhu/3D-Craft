import Foundation
import OSLog
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Keeps one Live Activity per running creation job.
///
/// The activity mirrors the job the app already polls: it starts when a job is
/// submitted, follows the same status and progress the journey card shows, and
/// ends when the job reaches a terminal state. The mascot still advances one
/// frame per update, which is honest about how often real news arrives.
///
/// While the app is open these updates come from the local poll. The push token
/// is handed to the server so the same activity keeps moving after the app is
/// backgrounded; if push is unavailable, the activity simply holds its last
/// state and ends on the next launch.
@MainActor
final class CraftLiveActivityCenter: ObservableObject {
    static let shared = CraftLiveActivityCenter()

    /// Terminal jobs whose activity has been ended, so it is not restarted.
    private var finished = Set<String>()
    private var frames: [String: Int] = [:]
    private var tokenTasks: [String: Task<Void, Never>] = [:]
    /// Called with (jobId, hex push token) so the store can register it.
    var registerToken: ((String, String) async -> Void)?
    /// Why the Lock Screen is empty, when it is. Read by the app to explain.
    @Published private(set) var unavailableReason: String?
    private let log = Logger(subsystem: "studio.craft.ios", category: "LiveActivity")

    private init() {}

    var available: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
            unavailableReason = enabled ? nil : "off-in-settings"
            return enabled
        }
        #endif
        unavailableReason = "unsupported"
        return false
    }

    func sync(jobs: [CraftJob], projectName: @escaping (String) -> String, emerald: Bool, chinese: Bool) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), available else { return }
        for job in jobs where job.kind == "model" || job.kind == "concepts" || job.kind == "animation" {
            if job.isActive {
                start(job, projectName: projectName(job.projectId), emerald: emerald, chinese: chinese)
                update(job)
            } else {
                end(job)
            }
        }
        #endif
    }

    /// Ends every activity, for sign-out and account switches.
    func endAll() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for task in tokenTasks.values { task.cancel() }
        tokenTasks.removeAll(); frames.removeAll(); finished.removeAll()
        for activity in Activity<CraftGenerationAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private func activity(for jobId: String) -> Activity<CraftGenerationAttributes>? {
        Activity<CraftGenerationAttributes>.activities.first { $0.attributes.jobId == jobId }
    }

    @available(iOS 16.2, *)
    private func start(_ job: CraftJob, projectName: String, emerald: Bool, chinese: Bool) {
        guard activity(for: job.id) == nil, !finished.contains(job.id) else { return }
        let attributes = CraftGenerationAttributes(
            jobId: job.id, kind: job.kind, projectId: job.projectId, projectName: projectName,
            mascot: .forTheme(emerald: emerald), chinese: chinese,
            startedAt: job.createdAt.map { Date(timeIntervalSince1970: $0) } ?? .now)
        let content = ActivityContent(state: state(for: job), staleDate: staleDate())
        do {
            let started = try Activity.request(attributes: attributes, content: content, pushType: .token)
            unavailableReason = nil
            log.info("Live Activity started for \(job.id, privacy: .public) (\(job.kind, privacy: .public))")
            observeToken(started)
        } catch {
            // Push may be refused while the rest still works, so try again
            // without it rather than leaving the Lock Screen empty.
            log.error("Live Activity with push refused: \(error.localizedDescription, privacy: .public)")
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                unavailableReason = nil
                log.info("Live Activity started without push for \(job.id, privacy: .public)")
            } catch {
                unavailableReason = "refused"
                log.error("Live Activity refused: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @available(iOS 16.2, *)
    private func update(_ job: CraftJob) {
        guard let activity = activity(for: job.id) else { return }
        frames[job.id] = (frames[job.id] ?? 1) % 6 + 1
        Task { await activity.update(.init(state: state(for: job), staleDate: staleDate())) }
    }

    @available(iOS 16.2, *)
    private func end(_ job: CraftJob) {
        guard let activity = activity(for: job.id) else { return }
        finished.insert(job.id)
        tokenTasks.removeValue(forKey: job.id)?.cancel()
        let final = state(for: job)
        // A finished creation is worth a moment on the Lock Screen; a failure
        // leaves sooner because there is nothing to go back to.
        let policy: ActivityUIDismissalPolicy = final.failed ? .after(.now + 30) : .after(.now + 120)
        Task { await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: policy) }
    }

    @available(iOS 16.2, *)
    private func observeToken(_ activity: Activity<CraftGenerationAttributes>) {
        let jobId = activity.attributes.jobId
        tokenTasks[jobId]?.cancel()
        tokenTasks[jobId] = Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                let token = data.map { String(format: "%02x", $0) }.joined()
                await self?.registerToken?(jobId, token)
            }
        }
    }

    private func staleDate() -> Date { .now + 300 }
    #endif

    private func state(for job: CraftJob) -> CraftGenerationAttributes.State {
        let failed = !job.isActive && job.status != "done" && job.status != "partial"
        let done = !job.isActive && !failed
        return .init(phase: CraftActivityPhase.of(status: job.status, kind: job.kind),
                     progress: done ? 1 : job.progress / 100,
                     frame: frames[job.id] ?? 1,
                     finished: done, failed: failed, stage: job.stage)
    }
}
