import SwiftUI
import WebKit

private struct CraftGame: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let chinese: String
    let symbol: String
}

private let craftGames = [
    CraftGame(id: "survivor", title: "Lanternfall", subtitle: "Survive the lantern-lit old town", chinese: "穿梭古镇，守护最后的灯火", symbol: "sparkles"),
    CraftGame(id: "ruins", title: "The Last Signal", subtitle: "Explore ruins. Restore the signal.", chinese: "探索遗迹，恢复失落的信号", symbol: "mountain.2"),
    CraftGame(id: "arena", title: "Emberfront", subtitle: "Drive into the arena", chinese: "驾驶你的创作，进入装甲竞技场", symbol: "flame"),
    CraftGame(id: "race", title: "Coastline Rush", subtitle: "Race along the sunset coast", chinese: "沿日落海岸竞速", symbol: "flag.checkered"),
    CraftGame(id: "dragon", title: "Emerald Skies", subtitle: "Run, fly and breathe fire", chinese: "奔跑、飞翔，吐息守护山谷", symbol: "wind")
]

/// Choosing a world for your character. Big cover cards that lift toward the
/// finger, a selection that answers, and a launch capsule that stays reachable
/// at the bottom of the screen.
struct GameChooserView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let asset: CraftAsset
    @EnvironmentObject private var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var kind = "character"
    @State private var yaw = 0
    @State private var selected = "survivor"
    @State private var launch: GameLaunchDestination?
    @State private var error: String?
    @State private var launchCount = 0
    /// The CTA arms itself once a world has been deliberately chosen, so the
    /// capsule is quiet at rest and says "go" only after a decision.
    @State private var chose = false
    @State private var failureCount = 0
    @State private var scrollY: CGFloat = 0
    private var accent: Color { appearance.ink }
    private var compatible: [CraftGame] {
        let ids = kind == "vehicle" ? ["arena", "race"] : kind == "flying" ? ["dragon", "survivor", "ruins"] : ["survivor", "ruins"]
        return ids.compactMap { id in craftGames.first { $0.id == id } }
    }
    private var selectedTitle: String { compatible.first { $0.id == selected }?.title ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headline
                assetCard
                kindPicker

                ForEach(Array(compatible.enumerated()), id: \.element.id) { index, game in
                    gameCard(game, index: index)
                }

                facingDisclosure

                Text(store.t("Your model keeps its appearance and uses the game's movement. Automatic rigging is not applied. Local preview requires the studio server on this Mac.", "保留模型外观，使用游戏的移动方式，不会自动生成骨骼。本地预览需要这台 Mac 上的工作室服务保持运行。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .craftEntrance(8)

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel(error)
                        .transition(.opacity)
                }
            }
            .padding(24)
            .craftScrollProbe()
        }
        .onPreferenceChange(CraftScrollOffsetKey.self) { scrollY = $0 }
        .safeAreaInset(edge: .bottom) { launchBar }
        .background { StudioAtmosphere(intensity: 1.15, scrollProgress: min(1, Double(scrollY) / 600)) }
        .navigationTitle(store.t("Play in game", "带入游戏"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: kind)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: error)
        .craftFeedback(.cardSelect, trigger: selected)
        .craftFeedback(.primaryAction, trigger: launchCount)
        .craftFeedback(.jobFailed, trigger: failureCount)
        .craftAmbientHost()
        .onAppear {
            let name = asset.name.lowercased()
            kind = asset.kind == "vehicle" || ["car", "camper", "truck", "van", "汽车", "赛车"].contains(where: name.contains) ? "vehicle" : asset.kind == "flying" || ["dragon", "bird", "龙", "凤凰"].contains(where: name.contains) ? "flying" : "character"
            selected = compatible.first?.id ?? "survivor"
            GamePrewarmer.shared.prewarm(webBase: store.webBase)
        }
        .fullScreenCover(item: $launch) { destination in
            NativeGameScreen(url: destination.url, title: destination.title, chinese: store.isChinese)
        }
    }

    // MARK: - Sections

    private var headline: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.t("A whole world for your creation.", "让你的创作，走进真实游戏。"))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .craftEntrance(0)
                Text(store.t("Choose a world and play with this exact 3D asset.", "选择一个世界，使用当前的 3D 模型试玩。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .craftEntrance(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CraftAccentStar(size: 34, period: 5.2)
                .offset(x: 4, y: -10)
                .craftParallax(0.26, offset: scrollY)
                .craftEntrance(2, style: .popIn)
        }
    }

    private var assetCard: some View {
        HStack(spacing: 14) {
            if asset.isAnimated, let url = asset.animationURL {
                CraftAnimationLoop(url: url, id: asset.id, posterURL: asset.thumbURL, cornerRadius: 16)
                    .frame(width: 76, height: 84)
            } else {
                CraftThumbnailImage(url: asset.thumbURL, inset: 6)
                    .frame(width: 76, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(asset.name).font(.headline).lineLimit(2)
                Text(store.t(asset.isAnimated ? "Your animated character" : "Your selected 3D asset",
                             asset.isAnimated ? "你选择的动画角色" : "你当前选择的 3D 资产"))
                    .font(.caption).foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .craftDepth(.card)
        .craftEntrance(2)
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("MODEL TYPE", "模型类型"))
                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            CraftSegmented(options: [.init("character", store.t("Character", "角色")),
                                     .init("vehicle", store.t("Vehicle", "车辆")),
                                     .init("flying", store.t("Flying", "飞行"))],
                           selection: $kind)
                .onChange(of: kind) { _, _ in selected = compatible.first?.id ?? "survivor" }
        }
        .craftEntrance(3)
    }

    private func gameCard(_ game: CraftGame, index: Int) -> some View {
        let on = selected == game.id
        return Button {
            withAnimation(CraftMotion.gated(.snap, reduceMotion)) {
                selected = game.id
                chose = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    cover(game)
                        .frame(maxWidth: .infinity).frame(height: 168)
                        .clipped()
                    if on {
                        ZStack {
                            Circle().fill(appearance.fill).frame(width: 34, height: 34)
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(appearance.buttonInk)
                                .craftSymbolPop(selected, reduceMotion: reduceMotion)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        .padding(14)
                        .transition(reduceMotion
                                    ? AnyTransition.opacity
                                    : AnyTransition.scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityHidden(true)
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(game.title).font(.title3.weight(.semibold))
                        Text(store.isChinese ? game.chinese : game.subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: on ? "gamecontroller.fill" : "arrow.up.right")
                        .font(.title3)
                        .foregroundStyle(on ? accent : .secondary)
                        .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
                }
                .padding(18)
                .background(on ? appearance.wash : Color.white)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .craftSelectionRing(on, color: appearance.fill, cornerRadius: 26, lineWidth: 2)
            .craftDepth(.card)
        }
        .buttonStyle(CraftLiftStyle(scale: 1.015))
        .accessibilityAddTraits(on ? .isSelected : [])
        .studioScrollFocus(cornerRadius: 26)
        .craftEntrance(index + 4, style: .popIn)
    }

    @ViewBuilder private func cover(_ game: CraftGame) -> some View {
        if let url = Bundle.main.url(forResource: game.id, withExtension: "jpg"), let cover = UIImage(contentsOfFile: url.path) {
            Image(uiImage: cover).renderingMode(.original).resizable().scaledToFill()
        } else {
            ZStack {
                appearance.gradient.opacity(0.55)
                Image(systemName: game.symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(appearance.ink)
            }
        }
    }

    private var facingDisclosure: some View {
        DisclosureGroup(store.t("Model facing", "模型朝向")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(store.t("If your character faces backward, choose a quarter-turn correction.", "如果模型背对前进方向，可在这里调整朝向。"))
                    .font(.caption).foregroundStyle(.secondary)
                CraftSegmented(options: [0, 90, 180, 270].map { CraftSegmented<Int>.Option($0, "\($0)°") },
                               selection: $yaw, height: 44)
            }.padding(.top, 12)
        }
        .tint(accent)
        .padding(16)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CraftTheme.stroke)
        )
        .animation(CraftMotion.gated(.glide, reduceMotion), value: yaw)
        .craftEntrance(7)
    }

    private var launchBar: some View {
        Button(action: start) {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text(store.t("Play", "进入") + " " + selectedTitle)
                    .contentTransition(.opacity)
            }
        }
        .buttonStyle(CraftPrimary(armed: chose))
        .accessibilityIdentifier("game.launch")
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28,
                                   style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 18, y: -5)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(CraftMotion.gated(.glide, reduceMotion), value: selectedTitle)
    }

    private func start() {
        launchCount += 1
        do {
            guard let base = URL(string: store.webBase),
                  ["http", "https"].contains(base.scheme?.lowercased() ?? ""),
                  base.user == nil, base.password == nil else { throw GameLaunchError.invalidServer }
            let raw = (asset.id == "bundled-lantern" || asset.modelUrl == nil) ? "/models/lantern_cat.glb" : asset.modelUrl
            guard let raw, let model = URL(string: raw, relativeTo: base)?.absoluteURL,
                  !model.isFileURL,
                  ["http", "https"].contains(model.scheme?.lowercased() ?? "") else { throw GameLaunchError.invalidModel }
            var info: [String: Any] = ["id": asset.id, "name": asset.name, "url": model.absoluteString, "kind": kind, "yaw": yaw]
            if asset.isAnimated {
                info["isAnimated"] = true
                if let anim = asset.animationUrl { info["animationUrl"] = anim }
            }
            let preview = asset.id == "bundled-lantern" ? "/images/explore/lantern_cat.png" : (asset.thumbDisplayUrl ?? asset.thumbUrl)
            if let raw = preview, let thumb = URL(string: raw, relativeTo: base)?.absoluteURL,
               !thumb.isFileURL, ["http", "https"].contains(thumb.scheme?.lowercased() ?? "") {
                info["thumbUrl"] = thumb.absoluteString
            }
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "game": selected, "locale": store.isChinese ? "zh" : "en", "asset": info])
            var url = URLComponents(url: base, resolvingAgainstBaseURL: true)!
            url.path = "/ios-game"
            url.query = nil
            url.fragment = data.base64EncodedString()
            guard let final = url.url else { throw GameLaunchError.invalidServer }
            error = nil
            launch = GameLaunchDestination(url: final, title: compatible.first { $0.id == selected }?.title ?? "Game")
        } catch {
            self.error = store.t("Unable to launch game with this 3D model. Please ensure the model is ready and try again.", "无法带入此 3D 模型启动游戏。请确认模型已生成完毕后重试。")
            failureCount += 1
        }
    }
}

private enum GameLaunchError: Error { case invalidServer, invalidModel }
private struct GameLaunchDestination: Identifiable { let id = UUID(); let url: URL; let title: String }

private struct NativeGameScreen: View {
    let url: URL
    let title: String
    let chinese: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var error: String?
    @State private var retry = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Label(chinese ? "返回模型" : "Back to model", systemImage: "chevron.left")
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.white, in: Capsule(style: .continuous))
                }
                .buttonStyle(CraftPressStyle())
                Spacer()
                Text(title).font(.subheadline.weight(.semibold))
            }.font(.subheadline).padding(16)
            if let error {
                VStack(spacing: 22) {
                    Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        .craftSymbolPop(retry, reduceMotion: reduceMotion)
                    Text(chinese ? "游戏连接中断" : "Game connection interrupted").font(.title3.weight(.semibold))
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(chinese ? "重试" : "Try again") { self.error = nil; retry += 1 }.buttonStyle(.borderedProminent)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                .craftEntrance(0, style: .popIn)
                .craftFeedback(.jobFailed, trigger: error)
            } else {
                CraftGameWebView(url: url, onClose: { dismiss() }, onError: { _ in
                    error = chinese ? "请确认工作室在这台 Mac 上运行，然后重试。" : "Make sure the studio server is running on this Mac, then try again."
                }).id(retry)
            }
        }.background(Color(red: 0.97, green: 0.96, blue: 0.99)).preferredColorScheme(.light)
    }
}

@MainActor
final class GamePrewarmer: NSObject, WKNavigationDelegate {
    static let shared = GamePrewarmer()
    private var webView: WKWebView?
    private var isPrewarming = false
    private var prewarmedBase: String?

    func prewarm(webBase: String) {
        guard !isPrewarming, prewarmedBase != webBase else { return }
        guard var components = URLComponents(string: webBase) else { return }
        components.path = "/games/forma/index.html"
        components.query = "prewarm=1"
        guard let url = components.url else { return }

        isPrewarming = true
        prewarmedBase = webBase

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        view.navigationDelegate = self
        view.isHidden = true
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
        view.load(request)
        self.webView = view
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPrewarming = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isPrewarming = false
    }
}

private struct CraftGameWebView: UIViewRepresentable {
    let url: URL
    let onClose: () -> Void
    let onError: (Error) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "craftGame")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        #if DEBUG
        view.isInspectable = true
        #endif
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.97, green: 0.96, blue: 0.99, alpha: 1)
        view.scrollView.isScrollEnabled = false
        let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45)
        view.load(request)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "craftGame")
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: CraftGameWebView
        init(_ parent: CraftGameWebView) { self.parent = parent }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.host == parent.url.host,
                  let body = message.body as? [String: String], body["action"] == "close" else { return }
            parent.onClose()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let requested = navigationAction.request.url else { decisionHandler(.cancel); return }
            if requested.scheme == "about" || requested.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            if requested.host == parent.url.host {
                if requested.path == "/ios-game" || requested.path.hasPrefix("/games/") || requested.path == "/" {
                    decisionHandler(.allow)
                    return
                }
            }
            if ["http", "https"].contains(requested.scheme?.lowercased() ?? "") {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { parent.onError(error) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { parent.onError(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.onError(NSError(domain: "CraftGame", code: 1, userInfo: [NSLocalizedDescriptionKey: "The game preview stopped. Try again."]))
        }
    }
}
