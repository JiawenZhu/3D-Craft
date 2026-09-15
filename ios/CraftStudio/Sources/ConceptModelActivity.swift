import SwiftUI

/// A job belongs to its submitted source, never whichever card is selected now.
enum ConceptModelActivity {
    static func completedForPresentation(jobs: [CraftJob], watching: Set<String>, opened: Set<String>) -> CraftJob? {
        jobs.first { $0.kind == "model" && watching.contains($0.id) && !opened.contains($0.id)
            && $0.status == "done" && $0.assets.contains(where: { $0.modelURL != nil }) }
    }

    static func sourceImage(for asset: CraftAsset, jobs: [CraftJob], projects: [CraftProject]) -> URL? {
        guard let job = jobs.first(where: { $0.kind.lowercased() == "model" && $0.assets.contains(where: { $0.id == asset.id }) }) else { return nil }
        if let source = job.selectedImageUrl, !source.isEmpty { return URL(string: source) }
        guard let project = projects.first(where: { $0.id == job.projectId }),
              let concept = project.concepts.first(where: { $0.id == job.selectedConceptId }) else { return nil }
        return URL(string: concept.imageUrl)
    }

    static func latestJob(for concept: CraftConcept, jobs: [CraftJob]) -> CraftJob? {
        jobs.first { job in
            guard job.kind.lowercased() == "model", job.projectId == concept.projectId else { return false }
            if let sourceID = job.selectedConceptId, !sourceID.isEmpty { return sourceID == concept.id }
            // Older saved jobs may only have the exact reference URL.
            return job.selectedImageUrl == concept.imageUrl
        }
    }

    static func isWorking(on concept: CraftConcept, jobs: [CraftJob], submittingID: String?) -> Bool {
        submittingID == concept.id || latestJob(for: concept, jobs: jobs)?.isActive == true
    }
}

/// A reconstruction scan over the real source image. It signals activity, not
/// estimated progress; the number below is always the service-reported value.
struct ConceptReconstructionOverlay: View {
    let job: CraftJob?
    let chinese: Bool
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.craftAmbientMotion) private var ambient
    private var animates: Bool { !reduceMotion && ambient && contrast != .increased }
    private var title: String {
        if job == nil { return chinese ? "正在提交 3D 请求" : "Submitting your 3D request" }
        if job?.status == "queued" { return chinese ? "3D 已排队" : "3D generation queued" }
        return chinese ? "正在构建你的 3D" : "Building your 3D"
    }

    private var detail: String {
        let message = job?.message.lowercased() ?? ""
        if job == nil { return chinese ? "为你的角色准备舞台……" : "Setting the stage for your character…" }
        if job?.status == "queued" || message.contains("queued") || message.contains("queue position") {
            return chinese ? "即将开始，你的角色正在等待登场。" : "Waiting for a turn in the studio."
        }
        return chinese ? "从轮廓到细节，逐渐成为立体。" : "From a silhouette to something you can explore."
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { context in
                ReconstructionLightField(time: animates ? context.date.timeIntervalSinceReferenceDate : 0,
                                         color: appearance.fill, moving: animates)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cube.transparent.fill")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(appearance.ink)
                        .frame(width: 36, height: 36)
                        .background(appearance.wash, in: RoundedRectangle(cornerRadius: 12))
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if let job, job.progress.isFinite, job.progress > 0 {
                        Text("\(Int(min(100, max(0, job.progress))))%")
                            .font(.caption.monospacedDigit())
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let job, job.progress.isFinite, job.progress > 0 {
                    ProgressView(value: min(100, max(0, job.progress)), total: 100)
                        .tint(appearance.ink)
                        .animation(animates ? .easeInOut(duration: 0.8) : nil, value: job.progress)
                        .accessibilityHidden(true)
                }
            }
            .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.6)))
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("concept.reconstructing")
    }
}

/// A continuous, slow light study. These loops show activity, never invented progress.
struct ReconstructionLightField: View {
    let time: TimeInterval
    let color: Color
    let moving: Bool

    var body: some View {
        Canvas { context, size in
            let cycle = moving ? time.truncatingRemainder(dividingBy: 7) / 7 : 0.35
            let breathe = 0.5 - 0.5 * cos(cycle * .pi * 2)
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.47)
            let radius = size.width * (0.38 + 0.025 * breathe)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.03), color.opacity(0.13), .clear]),
                                               center: center, startRadius: radius * 0.3, endRadius: radius))
            guard moving else { return }
            // A sine sweep eases at both ends: no hard reset or abrupt reversal.
            let y = size.height * (0.22 + 0.43 * breathe)
            let band = CGRect(x: 12, y: y - 24, width: max(0, size.width - 24), height: 48)
            context.fill(Path(roundedRect: band, cornerRadius: 24),
                         with: .linearGradient(Gradient(colors: [.clear, color.opacity(0.14), .clear]),
                                               startPoint: CGPoint(x: 0, y: y - 24), endPoint: CGPoint(x: 0, y: y + 24)))
            // Sparse glints travel around the subject, leaving the face unobscured.
            for index in 0..<6 {
                let angle = (time.truncatingRemainder(dividingBy: 12) / 12 + Double(index) / 6) * .pi * 2
                let x = center.x + cos(angle) * size.width * 0.40
                let py = center.y + sin(angle) * size.height * 0.30
                let alpha = 0.22 + 0.38 * (0.5 + 0.5 * sin(angle))
                let dot = CGRect(x: x - 2, y: py - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -4, dy: -4)), with: .color(color.opacity(alpha * 0.15)))
                context.fill(Path(ellipseIn: dot), with: .color(color.opacity(alpha)))
            }
        }
    }
}
