import SwiftUI
import UIKit

enum GameBuilder: String, CaseIterable, Identifiable {
    case chatGPT = "ChatGPT", codex = "Codex", claudeCode = "Claude Code", other = "Other"
    var id: String { rawValue }
    var url: URL? {
        switch self {
        case .chatGPT: return URL(string: "https://chatgpt.com/")
        case .codex: return URL(string: "https://chatgpt.com/codex")
        case .claudeCode: return URL(string: "https://claude.ai/code")
        case .other: return nil
        }
    }
}

/// Portable original models and a short, user-directed brief. No studio credentials.
struct GameHandoffFiles: Identifiable {
    let id = UUID()
    let models: [URL]
    let brief: URL
    var model: URL { models[0] }

    static func filename(name: String, index: Int) -> String {
        let stem = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-").prefix(48)
        return String(format: "%02d", index + 1) + "-" + (stem.isEmpty ? "object" : String(stem)) + ".glb"
    }
    static func prompt(names: [String], idea: String, chinese: Bool) -> String {
        let objects = names.enumerated().map { "- \($0.element) (\(filename(name: $0.element, index: $0.offset)))" }.joined(separator: "\n")
        let request = chinese ? "请使用这些 3D 对象制作一个在浏览器里玩的游戏。" : "Create a game that runs in a browser using these 3D objects."
        let thought = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        return request + "\n\n" + objects + (thought.isEmpty ? "" : "\n\n" + thought)
    }
    static func prepare(sources: [URL], names: [String], idea: String, chinese: Bool = false,
                        root: URL = FileManager.default.temporaryDirectory) throws -> Self {
        guard !sources.isEmpty, sources.count == names.count else { throw CraftError(message: "Select at least one 3D object.") }
        let directory = root.appendingPathComponent("3D-Craft-Game-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            var models: [URL] = []
            for (index, source) in sources.enumerated() {
                let model = directory.appendingPathComponent(filename(name: names[index], index: index))
                try FileManager.default.copyItem(at: source, to: model)
                let file = try FileHandle(forReadingFrom: model)
                let header = try file.read(upToCount: 4)
                try file.close()
                guard header == Data([0x67, 0x6c, 0x54, 0x46]) else {
                    throw CraftError(message: "\(names[index]): the downloaded file is not a GLB model. Please export it again.")
                }
                models.append(model)
            }
            let brief = directory.appendingPathComponent("GAME_BRIEF.md")
            try prompt(names: names, idea: idea, chinese: chinese).write(to: brief, atomically: true, encoding: .utf8)
            return Self(models: models, brief: brief)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

struct GameHandoffView: View {
    let asset: CraftAsset
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @State private var builder: GameBuilder = .chatGPT
    @State private var idea = ""
    @State private var selectedIDs: Set<String> = []
    @State private var initialized = false
    @State private var preparing = false
    @State private var completed = 0
    @State private var files: GameHandoffFiles?
    @State private var error: String?
    @State private var copied = false
    @State private var choosingObjects = false

    private var available: [CraftAsset] {
        var seen = Set<String>()
        return ([asset] + store.assets + store.examples).filter { $0.modelURL != nil && seen.insert($0.id).inserted }
    }
    private var selected: [CraftAsset] { available.filter { selectedIDs.contains($0.id) } }
    private var prompt: String { GameHandoffFiles.prompt(names: selected.map(\.name), idea: idea, chinese: store.isChinese) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Label(store.t("Your objects. Your idea.", "你的对象，你的创意。"), systemImage: "cube.transparent")
                        .font(.title2.bold()).foregroundStyle(appearance.ink)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(store.t("3D objects", "3D 对象")).font(.headline)
                            Spacer()
                            Button(store.t("Choose objects", "选择对象")) { choosingObjects = true }
                                .disabled(preparing)
                                .accessibilityIdentifier("handoff.chooseObjects")
                        }
                        ForEach(selected) { object in
                            HStack(spacing: 12) {
                                objectThumbnail(object, size: 48)
                                Text(object.name).font(.subheadline).lineLimit(2)
                                Spacer(minLength: 0)
                            }
                        }
                        Text(store.t("\(selected.count) selected", "已选择 \(selected.count) 个"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.craftPanel()
                    Picker(store.t("Your agent", "你的 Agent"), selection: $builder) {
                        ForEach(GameBuilder.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).disabled(preparing).accessibilityIdentifier("handoff.builder")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Your idea (optional)", "你的想法（可选）")).font(.headline)
                        Text(store.t("You decide what to make with your agent.", "你来决定和 Agent 一起做什么。"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextEditor(text: $idea).frame(height: 100)
                            .disabled(preparing)
                            .scrollContentBackground(.hidden).padding(10)
                            .background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(appearance.hairline))
                            .accessibilityLabel(store.t("Your game idea", "你的游戏创意"))
                            .accessibilityIdentifier("handoff.prompt")
                        Text(store.t("Prompt preview", "提示词预览")).font(.caption.bold())
                        Text(prompt).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("handoff.preview")
                    }
                    if let error { Text(error).font(.callout).foregroundStyle(.red).accessibilityIdentifier("handoff.error") }
                    Button { share() } label: {
                        HStack {
                            if preparing { ProgressView() } else { Image(systemName: "square.and.arrow.up") }
                            Text(preparing ? store.t("Preparing \(completed)/\(selected.count)…", "正在准备 \(completed)/\(selected.count)…") : store.t("Share objects & prompt", "分享对象和提示词"))
                        }
                    }.buttonStyle(CraftPrimary()).disabled(preparing || selected.isEmpty)
                        .accessibilityIdentifier("handoff.share")
                    Text(store.t("Share the files with your agent, or save them to Files. Opening an agent does not attach files automatically.", "把文件分享给你的 Agent，或先存到“文件”。打开 Agent 不会自动附加文件。"))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button { UIPasteboard.general.string = prompt; copied = true } label: {
                            Label(copied ? store.t("Copied", "已复制") : store.t("Copy prompt", "复制提示词"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        }.disabled(selected.isEmpty).accessibilityIdentifier("handoff.copy")
                        Spacer()
                        if let url = builder.url {
                            Button { openURL(url) } label: { Label(store.t("Open", "打开") + " " + builder.rawValue, systemImage: "arrow.up.right") }
                                .accessibilityIdentifier("handoff.open")
                        }
                    }.font(.subheadline.weight(.semibold)).tint(appearance.ink)
                }.padding(24).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(StudioAtmosphere())
            .navigationTitle(store.t("Create a game", "创建游戏")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done", "完成")) { dismiss() }.disabled(preparing) } }
            .onAppear { if !initialized { initialized = true; selectedIDs = [asset.id] } }
            .onChange(of: prompt) { _, _ in copied = false }
            .sheet(item: $files) { GameHandoffShareSheet(files: $0) }
            .sheet(isPresented: $choosingObjects) {
                NavigationStack {
                    List(available) { object in
                        Button {
                            if selectedIDs.contains(object.id) { selectedIDs.remove(object.id) } else { selectedIDs.insert(object.id) }
                        } label: {
                            HStack(spacing: 12) {
                                objectThumbnail(object, size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(object.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                    Text(object.isExample ? store.t("3D Craft collection", "3D Craft 合集") : store.t("Made by you", "你的作品"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: selectedIDs.contains(object.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).accessibilityHidden(true)
                            }.foregroundStyle(appearance.ink).padding(.vertical, 6)
                        }.accessibilityIdentifier("handoff.object." + object.id)
                         .accessibilityValue(selectedIDs.contains(object.id) ? "Selected" : "Not selected")
                    }.navigationTitle(store.t("Choose objects", "选择对象"))
                     .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done", "完成")) { choosingObjects = false } } }
                }
            }
            .interactiveDismissDisabled(preparing)
        }
    }
    private func objectThumbnail(_ object: CraftAsset, size: CGFloat) -> some View {
        CraftThumbnailImage(url: object.thumbURL, inset: 2)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
    private func share() {
        preparing = true; completed = 0; error = nil
        let objects = selected, thought = idea, chinese = store.isChinese
        Task { @MainActor in
            defer { preparing = false }
            do {
                var sources: [URL] = []
                for object in objects { sources.append(try await store.export(object)); completed += 1 }
                files = try await Task.detached(priority: .userInitiated) {
                    try GameHandoffFiles.prepare(sources: sources, names: objects.map(\.name), idea: thought, chinese: chinese)
                }.value
            } catch { self.error = error.localizedDescription }
        }
    }
}
private struct GameHandoffShareSheet: UIViewControllerRepresentable {
    let files: GameHandoffFiles
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: files.models + [files.brief], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
