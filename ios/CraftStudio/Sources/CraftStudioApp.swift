import SwiftUI
import AuthenticationServices
import PhotosUI
import UniformTypeIdentifiers
#if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
import StoreKitTest
#endif

@main struct CraftStudioApp: App {
    @StateObject private var store = CraftStore()
    @StateObject private var billing = BillingManager()
    @ObservedObject private var account = CraftAccount.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG && targetEnvironment(simulator) && canImport(StoreKitTest)
    private let testSession: SKTestSession? = {
        // StoreKitTest soft-links XCTest. Normal simctl launches do not supply
        // Xcode's developer framework search paths; never invoke its aborting
        // initializer unless XCTest can first be loaded safely.
        guard dlopen("/System/Library/Frameworks/XCTest.framework/XCTest", RTLD_NOW | RTLD_GLOBAL) != nil else {
            print("[StoreKit review] XCTest unavailable. Run the Xcode scheme or the simulator review launcher to enable test purchases.")
            return nil
        }
        do {
            let session = try SKTestSession(configurationFileNamed: "Products")
            session.disableDialogs = true
            print("[StoreKit review] Local test session active. No real charges.")
            return session
        } catch {
            print("[StoreKit review] Could not activate local purchases: \(error)")
            return nil
        }
    }()
    #endif
    @AppStorage("hasSeenIntroductionV2") private var hasSeenIntroduction: Bool = false
    @State private var showIntroduction = false

    init() {
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        for key in Array(domain.keys) {
            if key == "craftConceptCount" || key.contains("craftActiveConversation") {
                if let val = domain.removeValue(forKey: key) {
                    if let intVal = Int("\(val)") {
                        UserDefaults.standard.set(intVal, forKey: key)
                    } else {
                        UserDefaults.standard.set(val, forKey: key)
                    }
                }
            }
        }
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    var body: some Scene { WindowGroup {
        Group {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--preview-intro") { CraftIntroductionView(onFinish: {}) }
            else if ProcessInfo.processInfo.arguments.contains("--preview-paywall") { PaywallView() }
            else if ProcessInfo.processInfo.arguments.contains("--preview-community") { NavigationStack { CommunityGamesView() }.craftAmbientHost() }
            else if ProcessInfo.processInfo.arguments.contains("--preview-model-prompt") {
                ModelGenerationSheet(concept: CraftConcept(["id":"preview","projectId":"preview","name":"Lantern Explorer",
                    "imageUrl":Bundle.main.url(forResource:"lantern_cat",withExtension:"jpg")?.absoluteString ?? ""],base:""), chinese:store.isChinese) { _,_,_,_,_ in }
            }
            else if account.uid == nil && !ProcessInfo.processInfo.arguments.contains(where: { $0.contains("craftActiveConversation") }) { PublicDiscoveryView() }
            else { CraftRoot().id(account.uid ?? "review") }
            #else
            if account.uid == nil { PublicDiscoveryView() }
            else { CraftRoot().id(account.uid) }
            #endif
        }.environmentObject(store).environmentObject(billing).preferredColorScheme(.light)
         .fullScreenCover(isPresented: $showIntroduction) {
             CraftIntroductionView {
                 hasSeenIntroduction = true
                 showIntroduction = false
             }
             .environmentObject(store)
             .environmentObject(billing)
         }
         .task {
             let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                 || ProcessInfo.processInfo.arguments.contains("-hasSeenIntroductionV2")
                 || ProcessInfo.processInfo.arguments.contains(where: { $0.contains("craftActiveConversation") })
             if !hasSeenIntroduction && !isTesting {
                 try? await Task.sleep(nanoseconds: 300_000_000)
                 showIntroduction = true
             }
         }
         .alert(store.t("Account deletion requested", "账户删除请求已受理"), isPresented: $account.deletionRequested) {
             Button(store.t("OK", "好"), role: .cancel) {}
         } message: {
             Text(store.t("You are signed out. Your account and cloud content are being permanently removed. Deletion continues even if you close the app.", "你已退出登录。账户和云端内容正在永久删除，即使关闭应用也会继续处理。"))
         }
         .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
             Task { await account.verifyAppleAuthorization() }
         }
         .onChange(of: scenePhase) { _, phase in
             if phase == .active { Task { await account.verifyAppleAuthorization(); await store.refreshOutsideChanges() } }
         }
         .onOpenURL { url in
             // Tapping the Live Activity opens the project it is reporting on.
             guard url.scheme == "studio.craft.ios", url.host == "project" else { return }
             let projectID = url.lastPathComponent
             guard !projectID.isEmpty, projectID != "/" else { return }
             store.path = [.project(projectID)]
             Task { await store.refreshOutsideChanges() }
         }
         .onChange(of: account.uid) { _, newUid in
             Task {
                 await store.accountChanged()
                 if let newUid, !newUid.isEmpty {
                     await billing.logInRevenueCat(userId: newUid)
                 } else {
                     await billing.logOutRevenueCat()
                 }
             }
         }
         .task {
             if let uid = account.uid, !uid.isEmpty {
                 await billing.logInRevenueCat(userId: uid)
             }
         }
    } }
}

struct CraftRoot: View {
    @State private var reconnectSignIn = false
    @EnvironmentObject private var billing: BillingManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $store.path) {
            screen
                .navigationDestination(for: CraftRoute.self) { route in
                    Group {
                        switch route {
                        case .project(let id): CraftConversationView(projectID: id)
                        case .asset(let asset):
                            // An animated character has no mesh to inspect; it plays instead.
                            if asset.isAnimated { AnimatedCharacterDetailView(asset: asset) }
                            else if asset.isConcept, let url = asset.sourceImageURL ?? asset.thumbURL {
                                ConceptImageInspector(imageURL: url, chinese: store.isChinese)
                            }
                            else { AssetDetailView(asset: asset) }
                        case .games(let asset): GameChooserView(asset: asset)
                        case .wallet: WalletView()
                        case .settings: ProfileView()
                        }
                    }
                    .background { StudioAtmosphere() }
                }
                .safeAreaInset(edge: .bottom) {
                    if store.path.isEmpty {
                        CraftTabBar(items: [
                            .init(icon: "cube", selectedIcon: "cube.fill", label: store.t("Create", "创作")),
                            .init(icon: "folder", selectedIcon: "folder.fill", label: store.t("Library", "资产库")),
                            .init(icon: "person", selectedIcon: "person.fill", label: store.t("Profile", "我的")),
                            .init(icon: "trophy", selectedIcon: "trophy.fill", label: store.t("Games", "游戏"))
                        ], selection: $store.selectedTab)
                    }
                }
        }
        .craftAmbientHost()
        .tint(appearance.ink)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                CreationReadyCard()
                connectionNotice
            }
        }
        .animation(CraftMotion.gated(.glide, reduceMotion), value: store.completedModelCards.first?.id)
        .animation(CraftMotion.gated(.glide, reduceMotion), value: store.connectionNotice)
        .sheet(isPresented: $store.showShortfallModal) {
            if let shortfall = store.shortfall {
                TokenShortfallModalView(needed: shortfall.needed, available: shortfall.available) {
                    store.showPaywall = true
                }
                .craftAmbientHost()
            }
        }
        .sheet(isPresented: $store.showPaywall, onDismiss: {
            store.shortfall = nil
            store.presentPurchasedWallet()
        }) { PaywallView(startOnTopups: store.shortfall != nil).craftAmbientHost() }
        .onChange(of: store.purchaseToPresent?.id) { _, id in
            guard id != nil else { return }
            if store.showPaywall {
                // Navigation happens in onDismiss, after the payment sheet is gone.
                store.showPaywall = false
            } else { store.presentPurchasedWallet() }
        }
        .alert(store.t("Notice", "提示"),
               isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("Sign out") { CraftAccount.shared.signOut() } } }
        .task { await store.connect() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await billing.reconcileWallet(store: store)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        .onChange(of: store.connected) { _, connected in
            if connected { Task { try? await billing.reconcileWallet(store: store, force: true) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.connect() } }
        }
        .sheet(isPresented: $reconnectSignIn) { CraftSignInView() }
    }

    /// The three tabs. A cross-fade with a short lift — never a horizontal
    /// slide, which would fight the `NavigationStack` push.
    private var screen: some View {
        Group {
            switch store.selectedTab {
            case 1: LibraryView()
            case 2: ProfileView()
            case 3: CommunityGamesView()
            default:
                if let id = store.activeConversationID { CraftConversationView(projectID: id, isHome: true) }
                else { CreateView() }
            }
        }
        .clipped()
        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        .id(store.selectedTab)
        .background { StudioAtmosphere() }
        .animation(CraftMotion.gated(.glide, reduceMotion), value: store.selectedTab)
        // One envelope for the whole language swap, so every localized string
        // in the tree cross-fades instead of snapping.
        .animation(CraftMotion.gated(.glide, reduceMotion), value: store.isChinese)
    }

    @ViewBuilder private var connectionNotice: some View {
        if let notice = store.connectionNotice {
            HStack(spacing: 10) {
                if store.connecting { ProgressView().controlSize(.small) }
                else { Image(systemName: store.connected ? "info.circle" : "wifi.exclamationmark") }
                Text(notice).font(.caption)
                Spacer(minLength: 8)
                Button(store.connectionNeedsSignIn ? store.t("Sign in", "登录") : store.connectionNeedsSetup ? store.t("Settings", "设置") : store.t("Retry", "重试")) {
                    if store.connectionNeedsSignIn { reconnectSignIn = true }
                    else if store.connectionNeedsSetup { store.path.append(.settings) }
                    else { Task { await store.connect() } }
                }.disabled(store.connecting)
                    .font(.caption.bold())
                    .buttonStyle(CraftPressStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(CraftTheme.card)
            .overlay(alignment: .bottom) {
                Rectangle().fill(CraftTheme.hairline).frame(height: 1)
            }
            .craftDepth(.card)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

@MainActor struct CreateView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @EnvironmentObject var store: CraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var promptFocused: Bool

    @State private var photo: PhotosPickerItem?
    @State private var photos = false
    @State private var photoReview: ReviewPhoto?
    @State private var files = false
    @State private var camera = false
    @State private var capturedPhoto: UIImage?
    @AppStorage("craftConceptCount") private var count = 4
    @State private var confirm = false
    @State private var settings = false
    @State private var category: GalleryHomeCategory = .characters
    @State private var order = "featured"
    @State private var tapCount = 0
    @State private var submitCount = 0
    @State private var attachCount = 0
    @State private var removeCount = 0
    @State private var tileCount = 0
    @State private var categoryCount = 0

    private var hasReference: Bool { store.draftImage != nil }
    private var armed: Bool {
        !store.draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasReference
    }
    private var galleryAssets: [CraftAsset] {
        let unique = category.assets(owned: store.assets, examples: store.examples)
        if order == "name" { return unique.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        return unique
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(store.t("What will you create?", "今天想创造什么？"))
                .font(.title2.weight(.bold))
                .foregroundStyle(appearance.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .accessibilityAddTraits(.isHeader)
            filters
            ScrollView {
                if galleryAssets.isEmpty {
                    ContentUnavailableView(category == .userCreated ? store.t("Your creations start here", "你的创作从这里开始") : store.t("A little room for imagination", "给想象留一点空间"),
                        systemImage: "sparkles",
                        description: Text(category == .userCreated ? store.t("Describe an idea below. Your finished models will appear here.", "在下方描述灵感，完成的模型会保存在这里。") : store.t("Try another category, or describe your own idea below.", "试试其他分类，或在下方描述你的灵感。")))
                        .padding(.top, 50)
                } else {
                    GalleryHomeGrid(
                        assets: galleryAssets,
                        chinese: store.isChinese,
                        isFavorite: { store.isFavorite($0.id) },
                        onModify: { asset in
                            promptFocused = false
                            store.modifyAsset(asset)
                        },
                        onFavorite: { asset in
                            store.addFavorite(asset.id)
                        },
                        onUnfavorite: { asset in
                            store.removeFavorite(asset.id)
                        },
                        onArchive: { asset in
                            Task {
                                await store.archiveAsset(asset)
                            }
                        },
                        onSelect: { asset in
                            promptFocused = false
                            tileCount += 1
                            store.path.append(.asset(asset))
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .id(category)
            .refreshable { await store.refresh() }
        }
        .padding(.top, 8)
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
        .background { StudioAtmosphere(intensity: 0.8) }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar(.hidden, for: .navigationBar)
        .craftFeedback(.primaryAction, trigger: tapCount)
        .craftFeedback(.jobSucceeded, trigger: submitCount)
        .craftFeedback(.referenceAttached, trigger: attachCount)
        .craftFeedback(.referenceRemoved, trigger: removeCount)
        .craftFeedback(.lightTap, trigger: tileCount)
        .craftFeedback(.optionSelect, trigger: categoryCount)
        .sheet(isPresented: $confirm) {
            ConceptGenerationSheet(count: $count, initialPrompt: store.draftPrompt) { selectedCount, editedPrompt in
                confirm = false
                if !editedPrompt.isEmpty { store.draftPrompt = editedPrompt }
                Task { if let id = await store.createConcepts(count: selectedCount) { submitCount += 1; store.draftPrompt = ""; store.saveDraftImage(nil); store.activeConversationID = id } }
            }
        }
        .photosPicker(isPresented: $photos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, value in
            guard let value else { return }
            Task { defer { photo = nil }; do {
                guard let data = try await value.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw CraftError(message: store.t("This photo could not be downloaded or opened. Try another photo, or use Files.", "无法下载或打开这张照片，请重试、选择其他照片或使用文件导入。")) }
                photoReview = ReviewPhoto(image: image)
            } catch { store.error = store.t("Could not load the selected photo. Check your connection and try again.", "无法加载所选照片，请检查网络后重试。") } }
        }
        .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; guard let image = UIImage(data: try Data(contentsOf: url)) else { throw CraftError(message: "This image could not be opened.") }; photoReview = ReviewPhoto(image: image) } catch { store.error = error.localizedDescription } }
        .sheet(isPresented: $camera, onDismiss: { if let image = capturedPhoto { photoReview = ReviewPhoto(image: image); capturedPhoto = nil } }) { CameraPicker { capturedPhoto = $0 } }
        .sheet(item: $photoReview) { reference in
            PhotoReviewView(image: reference.image, chinese: store.isChinese) { image in
                store.saveDraftImage(image)
                attachCount += 1
            }
            .craftAmbientHost()
        }
        .sheet(isPresented: $settings) { creationSettings }
        .onChange(of: store.focusComposerTrigger) { _, _ in
            promptFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("3D Craft", systemImage: "cube.fill")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .symbolRenderingMode(.palette)
                .foregroundStyle(appearance.ink, appearance.fill)
            Spacer()
            CreationCostButton(imageCount: count)
            Button { store.selectedTab = 2 } label: { CraftAvatar() }
                .buttonStyle(CraftPressStyle(scale: 0.92))
                .accessibilityLabel(store.t("Profile", "我的"))
        }
        .padding(.horizontal, 20)
    }

    private var filters: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(GalleryHomeCategory.allCases) { item in
                        Button {
                            categoryCount += 1
                            withAnimation(CraftMotion.gated(.fade, reduceMotion)) { category = item }
                        } label: {
                            Text(item.title(chinese: store.isChinese))
                                .font(.system(size: 13, weight: category == item ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .foregroundStyle(category == item ? appearance.buttonInk : appearance.ink)
                                .background {
                                    Capsule().fill(category == item ? appearance.fill : appearance.washSoft)
                                }
                        }
                        .buttonStyle(CraftPressStyle())
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                        .accessibilityIdentifier("creation.category." + item.rawValue)
                        .accessibilityValue(category == item ? store.t("Selected", "已选择") : store.t("Not selected", "未选择"))
                    }
                }
            }
            Menu {
                Picker(store.t("Sort gallery", "画廊排序"), selection: $order) {
                    Text(category == .userCreated ? store.t("Newest", "最新") : store.t("Featured", "精选")).tag("featured")
                    Text(store.t("Name", "名称")).tag("name")
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .frame(width: 40, height: 40)
                    .background(appearance.washSoft, in: Circle())
            }
            .accessibilityLabel(store.t("Sort gallery", "画廊排序"))
            .accessibilityIdentifier("creation.sort")
        }
        .padding(.horizontal, 20)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if store.draftImage == nil { CraftChatPriceCaption() }
            if let image = store.draftImage {
                HStack(spacing: 10) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("creationReference")
                    Text(store.t("Your reference is ready", "参考图已就绪"))
                        .font(.caption).foregroundStyle(appearance.ink)
                    Spacer()
                    Button {
                        store.saveDraftImage(nil)
                        removeCount += 1
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .buttonStyle(CraftPressStyle())
                    .accessibilityLabel(store.t("Remove reference", "移除参考图"))
                }
                .padding(.leading, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(alignment: .bottom, spacing: 9) {
                HStack(alignment: .center, spacing: 5) {
                    attachmentMenu
                    ZStack(alignment: .leading) {
                        if store.draftPrompt.isEmpty {
                            CraftPromptTypewriterView(chinese: store.isChinese) { selectedPrompt in
                                store.draftPrompt = selectedPrompt
                                promptFocused = true
                            }
                            .padding(.leading, 2)
                        }
                        TextField("", text: $store.draftPrompt, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...4)
                            .focused($promptFocused)
                            .accessibilityIdentifier("creation.prompt")
                    }
                    .padding(.vertical, 10)
                    Button {
                        promptFocused = false
                        tapCount += 1
                        if store.draftImage != nil { confirm = true }
                        else if let maximum = store.chatMaximumTokens { Task { await store.startConversation(maxTokens: maximum) } }
                    } label: {
                        ZStack {
                            Circle().fill(armed ? appearance.fill.gradient : appearance.washStrong.gradient)
                            if store.busy { ProgressView().tint(appearance.ink) }
                            else { Image(systemName: "arrow.up").font(.title3.weight(.semibold)) }
                        }
                        .foregroundStyle(armed ? appearance.buttonInk : appearance.ink)
                        .frame(width: 42, height: 42)
                    }
                    .buttonStyle(CraftPressStyle())
                    .disabled(!armed || store.busy || (store.draftImage == nil && store.chatMaximumTokens == nil))
                    .accessibilityLabel(store.t("Start creating together", "开始对话创作"))
                    .accessibilityIdentifier("creation.generateConcepts")
                }
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.white.opacity(0.8)))
                .craftDepth(.card)
                Button {
                    promptFocused = false
                    settings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 50, height: 50)
                        .background(.regularMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.8)))
                        .craftDepth(.card)
                }
                .buttonStyle(CraftPressStyle())
                .accessibilityLabel(store.t("Creation settings", "创作设置"))
                .accessibilityIdentifier("creation.settings")
                .padding(.bottom, 2)
            }
        }
        .tint(appearance.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 650)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [appearance.washSoft.opacity(0), appearance.washSoft.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button { photos = true } label: { Label(store.t("Photos", "相册"), systemImage: "photo") }
            Button { files = true } label: { Label(store.t("Files", "文件"), systemImage: "folder") }
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
                else { store.error = store.t("Camera is available on an iPhone. Use Photos or Files in the simulator.", "请在真机上使用相机；模拟器可使用相册或文件。") }
            } label: { Label(store.t("Camera", "拍照"), systemImage: "camera") }
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.medium))
                .frame(width: 42, height: 42)
                .background(appearance.washSoft, in: Circle())
        }
        .accessibilityLabel(store.t("Attach a reference", "添加参考图"))
        .accessibilityIdentifier("creation.attach")
    }

    private var creationSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.t("Make it your own", "创作你的风格")).font(.headline)
                        CraftSegmented<String>(options: [
                            .init("Stylized", store.t("Stylized", "风格化")),
                            .init("Realistic", store.t("Realistic", "写实")),
                            .init("Toy", store.t("Toy", "玩具"))
                        ], selection: $store.draftStyle, height: 44)
                        Stepper(store.t("\(count) concepts", "\(count) 张概念图"), value: $count, in: 1...4)
                    }
                    PlannerModelPicker()
                    ImageModelPicker()
                    PricingDetailsToggle()
                    if store.showPriceDetails {
                        Text(store.conceptPriceSummary(count: count))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("pricing.concepts.total")
                    }
                    if hasReference {
                        Button(store.t("Use original directly for 3D", "直接使用原图生成 3D")) {
                            Task {
                                if let id = await store.createConcepts(count: count, originalOnly: true) {
                                    submitCount += 1
                                    settings = false
                                    store.path.append(.project(id))
                                }
                            }
                        }
                        .buttonStyle(CraftSecondary())
                        .disabled(store.busy)
                        .accessibilityIdentifier("creation.useOriginal")
                    }
                    Text(store.t("Choose a concept first. The selected 3D model’s Token cost is shown before confirmation.", "先选择概念图，确认生成前会显示所选 3D 模型的 Token 费用。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(22)
            }
            .background { StudioAtmosphere(intensity: 0.8) }
            .navigationTitle(store.t("Creation settings", "创作设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Done", "完成")) { settings = false }
                        .accessibilityIdentifier("creation.settings.done")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .tint(appearance.ink)
        .craftAmbientHost()
    }
}

/// A creation tile: a tinted plate, not a grey one. Matches the mockup rail.
private struct CreationTile: View {
    let asset: CraftAsset
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CraftThumbnailImage(url: asset.thumbURL, inset: 10)
            .frame(width: 134, height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(appearance.washSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(appearance.fill.opacity(0.16)))
            .craftDepth(.card)

            Text(asset.name).font(.caption).lineLimit(1).foregroundStyle(.primary)
        }
        .frame(width: 134)
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var selected: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate { let parent: CameraPicker; init(_ parent: CameraPicker) { self.parent = parent }; func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage { parent.selected(image) }; parent.dismiss() }; func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() } }
}

struct ReviewPhoto: Identifiable { let id = UUID(); let image: UIImage }
