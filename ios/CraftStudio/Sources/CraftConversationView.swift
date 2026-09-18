import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// One persistent conversation owns the brief, concept versions, and 3D results.
struct CraftConversationView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let projectID: String
    var isHome = false
    @State private var message = ""
    @AppStorage("craftConceptCount") private var count = 4
    @State private var pendingReferenceID: String?
    @State private var directRequest: (referenceID: String, text: String)?
    @State private var confirmImages = false
    @State private var confirmRefine = false
    @State private var settings = false
    @State private var modelSource: CraftConcept?
    @State private var inspected: CraftConcept?
    @State private var refineSource: CraftConcept?
    @State private var refinePrompt = ""
    @State private var photo: PhotosPickerItem?
    @State private var photos = false
    @State private var files = false
    @State private var camera = false
    @State private var captured: UIImage?
    @State private var reviewing: ReviewPhoto?
    @State private var uploading = false
    @FocusState private var focused: Bool
    private var project: CraftProject? { store.projects.first { $0.id == projectID } }
    private var jobs: [CraftJob] { store.jobs.filter { $0.projectId == projectID } }
    private var selected: CraftConcept? { project.flatMap { store.selectedConcept(in: $0) } }
    private var thinking: Bool { store.sendingChat.contains(projectID) || project?.turns.contains(where: \.isActive) == true }
    private var working: Bool { jobs.contains(where: \.isActive) }
    private var draftKey: String { "craftChatDraft:" + store.apiBase + ":" + projectID }
    private var referenceKey: String { "craftChatReference:" + store.apiBase + ":" + projectID }
    private var pendingReference: CraftConcept? { project?.concepts.first { $0.id == pendingReferenceID } }
    private var events: [ConversationEvent] {
        let turns = (project?.turns ?? []).map { ConversationEvent.turn($0) }
        return (turns + jobs.map { ConversationEvent.job($0) }).sorted { $0.date < $1.date }
    }
    private var changeKey: String {
        (project?.turns ?? []).map { $0.id + $0.status }.joined() + jobs.map { $0.id + $0.status + String($0.concepts?.count ?? 0) }.joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        introduction
                        if let project {
                            let linked = Set(jobs.flatMap { ($0.concepts ?? []).map(\.id) })
                            ForEach(project.concepts.filter { !linked.contains($0.id) }) { concept in conceptCard(concept) }
                        }
                        ForEach(events) { event in
                            switch event {
                            case .turn(let turn): turnView(turn)
                            case .job(let job): jobView(job)
                            }
                        }
                        if let id = store.submittingModelID, project?.concepts.contains(where: { $0.id == id }) == true {
                            Label(store.t("Starting your 3D creation…", "正在开始生成 3D……"), systemImage: "cube.transparent")
                                .font(.headline).foregroundStyle(appearance.ink).id("model.submitting")
                        }
                        if store.sendingChat.contains(projectID) { Label(store.t("Saving your message…", "正在保存消息……"), systemImage: "ellipsis.bubble").font(.subheadline).foregroundStyle(.secondary) }
                        Color.clear.frame(height: 1).id("conversation.bottom")
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
                    .frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
                .refreshable { await store.refresh() }
                .onChange(of: store.submittingModelID) { _, id in
                    if id != nil { withAnimation { proxy.scrollTo("model.submitting", anchor: .center) } }
                }
                .clipped()
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: changeKey) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        if let last = events.last, case .job = last { proxy.scrollTo(last.id, anchor: .top) }
                        else { proxy.scrollTo("conversation.bottom", anchor: .bottom) }
                    }
                }
                .onChange(of: focused) { _, active in if active { proxy.scrollTo("conversation.bottom", anchor: .bottom) } }
            }
        }
        .background { StudioAtmosphere(intensity: 0.75) }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: projectID) { message = UserDefaults.standard.string(forKey: draftKey) ?? ""; pendingReferenceID = UserDefaults.standard.string(forKey: referenceKey) }
        .onChange(of: pendingReferenceID) { _, value in UserDefaults.standard.set(value, forKey: referenceKey) }
        .onChange(of: message) { _, value in UserDefaults.standard.set(value, forKey: draftKey) }
        .sheet(isPresented: $confirmImages) {
            ConceptGenerationSheet(count: $count) { amount in
                let request = directRequest
                let brief = request?.text ?? project?.brief ?? ""
                let referenceID = request?.referenceID ?? selected?.id
                confirmImages = false
                Task {
                    if await store.addConcepts(to: projectID, count: amount, prompt: brief, referenceID: referenceID, preserveReference: request != nil), let request {
                        if message == request.text { message = "" }
                        if pendingReferenceID == request.referenceID { pendingReferenceID = nil }
                    }
                }
            }
        }
        .sheet(item: $modelSource) { source in
            let related = relatedViews(source)
            ModelGenerationSheet(concept: source, chinese: store.isChinese, relatedViews: related, offersMultiView: !related.isEmpty) { engine, quality, effort, ids, prompt in
                modelSource = nil
                Task { await store.generateModel(source, engine: engine, quality: quality, effort: effort, conceptIds: ids, modelPrompt: prompt) }
            }
        }
        .confirmationDialog(store.t("Create a refined concept for \(store.conceptTokenCost(count: 1)) Tokens?", "使用 \(store.conceptTokenCost(count: 1)) Tokens 生成修改后的概念图？"), isPresented: $confirmRefine, titleVisibility: .visible) {
            Button(store.t("Refine concept", "修改概念图")) {
                guard let source = refineSource else { return }
                let prompt = refinePrompt
                Task { await store.refine(source, prompt: prompt) }
            }
        }
        .fullScreenCover(item: $inspected) { concept in
            if let url = URL(string: concept.imageUrl) { ConceptImageInspector(imageURL: url, chinese: store.isChinese).craftAmbientHost() }
        }
        .sheet(isPresented: $settings) { settingsView }
        .photosPicker(isPresented: $photos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task {
                defer { photo = nil }
                if let data = try? await value.loadTransferable(type: Data.self), let image = UIImage(data: data) { reviewing = ReviewPhoto(image: image) }
                else { store.error = store.t("Could not open this photo. Please try another.", "无法打开照片，请重试。") }
            }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let image = UIImage(data: try Data(contentsOf: url)) else { throw CraftError(message: "Could not open this image") }
                reviewing = ReviewPhoto(image: image)
            } catch { store.error = error.localizedDescription }
        }
        .sheet(isPresented: $camera, onDismiss: { if let captured { reviewing = ReviewPhoto(image: captured); self.captured = nil } }) { CameraPicker { captured = $0 } }
        .sheet(item: $reviewing) { reference in
            PhotoReviewView(image: reference.image, chinese: store.isChinese) { image in
                uploading = true
                Task { if let reference = await store.attachChatReference(projectID: projectID, image: image) { pendingReferenceID = reference.id }; uploading = false }
            }.craftAmbientHost()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                focused = false
                if isHome { store.activeConversationID = nil } else { dismiss() }
            } label: { Image(systemName: "chevron.left").frame(width: 42, height: 44) }
                .accessibilityLabel(store.t("Back to gallery", "返回画廊")).accessibilityIdentifier("chat.gallery")
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Create together", "一起创作")).font(.headline)
                Text(store.t("Idea · Concept · 3D", "灵感 · 概念图 · 3D")).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            CreationCostButton(projectID: projectID, imageCount: count)
            Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                .accessibilityLabel(store.t("Creation settings", "创作设置")).accessibilityIdentifier("chat.settings")
        }
        .foregroundStyle(appearance.ink).padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("3D Craft", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(appearance.ink)
            Text(store.t("A little idea.\nSomething entirely yours.", "一点灵感，\n创造你的独一无二。"))
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text(store.t("Shape your idea here. Your images and 3D creations will stay in this conversation.", "在对话中完善灵感，图片和 3D 作品都会保存在这里。"))
                .font(.subheadline).foregroundStyle(.secondary)
            if project?.turns.isEmpty == true, let project {
                Text(project.prompt).padding(14).background(appearance.wash, in: RoundedRectangle(cornerRadius: 18))
                if project.imageUrl == nil && jobs.isEmpty { Button(store.t("Help me develop this idea", "帮我完善这个灵感")) { send(project.prompt.isEmpty ? store.t("Help me develop this reference.", "帮我完善这张参考图。") : project.prompt) }
                    .buttonStyle(CraftSecondary()).disabled(thinking) }
            }
        }.padding(.bottom, 6)
    }
    private func turnView(_ turn: CraftChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Spacer(minLength: 32); Text(turn.text).font(.body).padding(15)
                .background(appearance.washStrong, in: RoundedRectangle(cornerRadius: 22)).textSelection(.enabled) }
            if let reply = turn.reply {
                VStack(alignment: .leading, spacing: 8) {
                    Label("3D Craft", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(appearance.ink)
                    Text(reply).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let charged = turn.charged {
                        Text(store.t("\(charged) \(charged == 1 ? "Token" : "Tokens") used", "已使用 \(charged) Token"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("chat.reply." + turn.id)
                if project?.turns.last?.id == turn.id, !thinking { nextStep(turn) }
            } else if turn.isActive {
                HStack(spacing: 10) { CraftMascotLoop(phase: .thinking, size: 36); Text(store.t("Thinking about your idea…", "正在思考你的灵感……")).font(.subheadline).foregroundStyle(.secondary) }
            } else if let error = turn.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.t(error, "消息已保存，但暂时无法回复。请检查规划模型后重试。")).font(.caption).foregroundStyle(.secondary)
                    Button(store.t("Try again", "重试")) { send(turn.text) }.disabled(thinking)
                }
            }
        }
    }
    private func nextStep(_ turn: CraftChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !(turn.suggestions ?? []).isEmpty {
                ForEach(turn.suggestions ?? [], id: \.self) { suggestion in
                    Button { send(suggestion) } label: { HStack { Text(suggestion); Spacer(); Image(systemName: "arrow.up.left") }.font(.subheadline).padding(13).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)) }
                        .buttonStyle(CraftPressStyle()).foregroundStyle(appearance.ink)
                }
            }
            DisclosureGroup(store.t("Your creative brief", "你的创意简报")) {
                Text(turn.brief ?? "").font(.subheadline).textSelection(.enabled).padding(.top, 8)
            }.font(.subheadline.weight(.medium)).tint(appearance.ink)
            Button { focused = false; directRequest = nil; confirmImages = true } label: {
                Label(store.t(turn.ready == true ? "Bring this idea to life" : "Create concepts now", turn.ready == true ? "让灵感成为作品" : "现在生成概念图"), systemImage: "sparkles").frame(maxWidth: .infinity)
            }.buttonStyle(CraftPrimary()).disabled(store.busy || working).accessibilityIdentifier("chat.generateConcepts")
            if let selected {
                Button {
                    refineSource = selected; refinePrompt = turn.brief ?? turn.text; confirmRefine = true
                } label: { Label(store.t("Apply brief to selected image", "用简报修改所选图片"), systemImage: "wand.and.stars") }
                    .buttonStyle(CraftSecondary()).disabled(store.busy || working).accessibilityIdentifier("chat.refine")
            }
        }
    }
    private func conceptCard(_ concept: CraftConcept) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.selectConcept(concept) }
            } label: {
                CraftCachedImage(url: URL(string: concept.imageUrl))
                    .frame(maxWidth: .infinity).frame(height: 300)
                    .background(appearance.washSoft)
                    .overlay(alignment: .topTrailing) {
                        if selected?.id == concept.id { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(appearance.ink, .white).padding(14) }
                    }
                    .overlay {
                        if let job = ConceptModelActivity.latestJob(for: concept, jobs: jobs), job.isActive {
                            ConceptReconstructionOverlay(job: job, chinese: store.isChinese)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(selected?.id == concept.id ? appearance.fill : .clear, lineWidth: 2))
            }.buttonStyle(CraftPressStyle()).accessibilityLabel(store.t("Select ", "选择 ") + (concept.label ?? concept.name)).accessibilityIdentifier("chat.concept." + concept.id)
            HStack {
                Text(concept.label ?? concept.name).font(.subheadline.weight(.medium))
                Spacer()
                Button { inspected = concept } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }.accessibilityLabel(store.t("Explore image", "查看原图"))
            }
            if let model = concept.imageModel { Text(CraftImageModel.displayName(for: model)).font(.caption).foregroundStyle(.secondary) }
            if selected?.id == concept.id {
                Button { modelSource = concept } label: { Label(store.t("Make this 3D", "用这张图生成 3D"), systemImage: "cube").frame(maxWidth: .infinity) }
                    .buttonStyle(CraftPrimary()).disabled(store.busy || working).accessibilityIdentifier("chat.generate3D")
            }
        }
    }
    private func jobView(_ job: CraftJob) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let prompt = job.sourcePrompt, !prompt.isEmpty {
                HStack { Spacer(minLength: 32); Text(prompt).padding(15).background(appearance.washStrong, in: RoundedRectangle(cornerRadius: 22)) }
            }
            Label(store.t(job.kind == "model" ? "Your 3D creation" : "Your concepts", job.kind == "model" ? "你的 3D 作品" : "你的概念图"), systemImage: job.kind == "model" ? "cube" : "photo.on.rectangle").font(.headline)
            ForEach(job.concepts ?? []) { concept in conceptCard(concept) }
            if job.isActive || job.status == "failed" || job.status == "partial" {
                GenerationJourneyView(job: job, sourceURL: project?.imageUrl.flatMap(URL.init(string:)), selectedConceptURL: job.selectedImageUrl.flatMap(URL.init(string:)), chinese: store.isChinese, coreConcept: job.coreConcept, stage: job.stage)
            }
            ForEach(job.assets) { asset in ConversationModelCard(asset: asset) }
        }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            if pendingReference == nil { CraftChatPriceCaption() }
            if let selected = pendingReference ?? selected {
                HStack(spacing: 8) {
                    CraftCachedImage(url: URL(string: selected.imageUrl)).frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(pendingReference != nil ? store.t("Reference ready · Generate directly", "参考图已就绪 · 直接生成") : store.t("Discussing selected image", "正在讨论所选图片")).font(.caption).foregroundStyle(appearance.ink)
                    Spacer()
                    if pendingReference != nil { Button { pendingReferenceID = nil } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }.accessibilityLabel(store.t("Remove attached reference", "移除附加参考图")) }
                    Button { modelSource = selected } label: { Image(systemName: "cube").frame(width: 44, height: 36) }.disabled(store.busy || working).accessibilityLabel(store.t("Make selected image 3D", "生成所选图片的 3D"))
                }.padding(.horizontal, 12)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(store.t("Photos", "相册"), systemImage: "photo") { photos = true }
                    Button(store.t("Files", "文件"), systemImage: "folder") { files = true }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button(store.t("Camera", "拍照"), systemImage: "camera") { camera = true } }
                } label: { Image(systemName: "plus").font(.title3).frame(width: 42, height: 44) }.disabled(uploading || thinking).accessibilityLabel(store.t("Attach reference", "添加参考图"))
                TextField(store.t("Tell me what you imagine…", "说说你的想法……"), text: $message, axis: .vertical).lineLimit(1...5).focused($focused).padding(.vertical, 12).accessibilityIdentifier("chat.message")
                Button { send(message) } label: {
                    Group {
                        if thinking { CraftMascotLoop(phase: .thinking, size: 28) }
                        else if uploading { ProgressView() }
                        else { Image(systemName: "arrow.up").font(.title3.bold()) }
                    }
                        .frame(width: 44, height: 44).background(appearance.fill, in: Circle())
                }.disabled((message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingReference == nil) || thinking || uploading || store.busy || working || (pendingReference == nil && store.chatMaximumTokens == nil))
                    .accessibilityLabel(store.t("Send message", "发送消息")).accessibilityIdentifier("chat.send")
            }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.8)))
        }.foregroundStyle(appearance.ink).padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: 650).frame(maxWidth: .infinity).background(appearance.washSoft)
    }
    private var settingsView: some View {
        NavigationStack {
            Form {
                Section(store.t("Style", "风格")) { Picker(store.t("Style", "风格"), selection: $store.draftStyle) { ForEach(["Stylized", "Realistic", "Toy"], id: \.self) { Text($0).tag($0) } } }
                Section { PlannerModelPicker(); ImageModelPicker() }
                Section { PricingDetailsToggle(); CreationCostButton(projectID: projectID, imageCount: count, iconOnly: false) }
                Section { Button(store.t("Create concepts now", "现在生成概念图")) { settings = false; prepareImages() }.disabled(working || store.busy || thinking) }
            }.navigationTitle(store.t("Creation settings", "创作设置")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done", "完成")) { settings = false } } }
        }.tint(appearance.ink).craftAmbientHost()
    }
    private func relatedViews(_ source: CraftConcept) -> [CraftConcept] {
        guard let set = source.viewSetId, jobs.first(where: { $0.id == set })?.viewsUsable == true else { return [] }
        return project?.concepts.filter { $0.viewSetId == set && $0.id != source.id } ?? []
    }
    private func prepareImages() {
        directRequest = pendingReference.map { ($0.id, message) }
        confirmImages = true
    }
    private func send(_ text: String) {
        if let reference = pendingReference {
            guard !thinking, !uploading, !working, !store.busy else { return }
            focused = false; directRequest = (reference.id, text); confirmImages = true
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !thinking else { return }
        let sent = text; focused = false
        guard let maximum = store.chatMaximumTokens else {
            store.error = store.t("Refresh the chat price before sending.", "请先刷新对话价格再发送。")
            return
        }
        Task { if await store.sendChat(projectID: projectID, text: sent, conceptID: selected?.id, maxTokens: maximum), message == sent { message = "" } }
    }
}

private enum ConversationEvent: Identifiable {
    case turn(CraftChatTurn), job(CraftJob)
    var id: String { switch self { case .turn(let t): return t.id; case .job(let j): return j.id } }
    var date: Double { switch self { case .turn(let t): return t.createdAt; case .job(let j): return j.createdAt ?? 0 } }
}

private struct ConversationModelCard: View {
    @EnvironmentObject private var store: CraftStore
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let asset: CraftAsset
    @State private var studio = false
    @State private var reset = 0
    @State private var mode = "Material"
    @State private var interacting = false
    var body: some View {
        VStack(spacing: 12) {
            if let url = asset.modelURL {
                ModelViewport(modelURL: url, mode: mode, resetID: reset, chinese: store.isChinese, softStage: true, showsZoomControls: interacting)
                    .allowsHitTesting(interacting)
                    .frame(height: 350).clipShape(RoundedRectangle(cornerRadius: 26))
            }
            Button {
                interacting.toggle()
            } label: { Label(store.t(interacting ? "Done exploring" : "Explore 3D", interacting ? "结束查看" : "探索 3D"), systemImage: interacting ? "checkmark" : "hand.draw") }
                .accessibilityIdentifier("chat.explore3D")
            HStack { Text(asset.name).font(.headline); Spacer(); Button { reset += 1 } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }.accessibilityLabel(store.t("Reset view", "重置视角")) }
            Picker(store.t("Material", "材质"), selection: $mode) { ForEach(["Material", "Solid", "Wire"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
            Button { studio = true } label: { Label(store.t("Lighting, play & export", "灯光、试玩与导出"), systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }.buttonStyle(CraftSecondary())
        }.tint(appearance.ink)
            .sheet(isPresented: $studio) { NavigationStack { AssetDetailView(onClose: { studio = false }, onPlay: { studio = false; store.path.append(.games(asset)) }, asset: asset) }.craftAmbientHost() }
    }
}


struct CraftChatPriceCaption: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        HStack(spacing: 8) {
            if let maximum = store.chatMaximumTokens {
                Text(store.t("AI chat · up to \(maximum) Tokens per reply. Unused Tokens returned.", "AI 对话 · 每次回复最多 \(maximum) Token，未使用部分会退回。"))
            } else {
                Text(store.chatPriceError ?? store.t("Loading chat price…", "正在加载对话价格……"))
            }
            Spacer(minLength: 0)
            Button { Task { await store.refreshChatPrice() } } label: {
                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
            }.accessibilityLabel(store.t("Refresh chat price", "刷新对话价格"))
        }
        .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 10)
        .task(id: store.plannerModelID + (CraftAccount.shared.uid ?? "")) { await store.refreshChatPrice() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshChatPrice() } }
        }
    }
}
