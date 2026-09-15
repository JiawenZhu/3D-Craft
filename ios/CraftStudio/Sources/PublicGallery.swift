import Foundation

/// Discovery is shipped with the app, independent of sign-in and the private studio.
enum PublicGallery {
    static let base = "https://3d-craft.web.app"
    static var bundled: [CraftAsset] {
        guard let url = Bundle.main.url(forResource: "public-gallery", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let records = try? JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { return [.lantern] }
        return records.map { record in
            var asset = CraftAsset(record, base: base, example: true)
            if let name = URL(string: record["thumbUrl"] as? String ?? "")?.deletingPathExtension().lastPathComponent,
               let local = Bundle.main.url(forResource: name, withExtension: "jpg") {
                asset.sourceImageUrl = local.absoluteString
                asset.thumbUrl = local.absoluteString
                asset.thumbDisplayUrl = local.absoluteString
            }
            return asset
        }
    }
}

import SwiftUI

/// Signed-out users can explore examples; creation and the private library still require an account.
struct PublicDiscoveryView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .emerald
    @EnvironmentObject var store: CraftStore
    @State private var category: GalleryHomeCategory = .characters
    @State private var signIn = false
    @State private var community = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("3D Craft", systemImage: "cube.fill").font(.title2.bold()).foregroundStyle(appearance.ink)
                        Spacer()
                        Button(store.t("Sign in", "登录")) { signIn = true }
                            .font(.subheadline.bold()).padding(.horizontal, 18).frame(minHeight: 44)
                            .foregroundStyle(appearance.ink).background(CraftTheme.card, in: Capsule())
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.t("A LITTLE IDEA. A WHOLE NEW WORLD.", "小小想法，全新世界。"))
                                .font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(appearance.ink)
                            Text(store.t("What will you create?", "今天想创造什么？"))
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text(store.t("Discover a character. Imagine an adventure.", "发现一个角色，开启一场冒险。"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Image("PaywallExplorer").resizable().scaledToFit().frame(width: 110, height: 150).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
                    }.padding(20).background(appearance.wash, in: RoundedRectangle(cornerRadius: 28))
                    Button { community = true } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.t("Find your next adventure", "发现下一场冒险")).font(.headline)
                                Text(store.t("Explore the games", "探索游戏世界")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right")
                        }.padding(18).background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(CraftPressStyle()).foregroundStyle(appearance.ink)
                    HStack {
                        ForEach(GalleryHomeCategory.allCases) { item in
                            Button(item.title(chinese: store.isChinese)) {
                                if item == .userCreated { signIn = true } else { category = item }
                            }.buttonStyle(.bordered).tint(category == item ? appearance.ink : appearance.ink.opacity(0.65))
                        }
                    }
                    GalleryHomeGrid(assets: category.assets(owned: [], examples: store.examples), chinese: store.isChinese) { asset in
                        store.path = [.asset(asset)]
                    }
                    Button("Sign in to create your own") { signIn = true }.buttonStyle(.borderedProminent)
                }.padding()
            }
            .navigationDestination(isPresented: Binding(get: { !store.path.isEmpty }, set: { if !$0 { store.path = [] } })) {
                if case .asset(let asset) = store.path.last { AssetDetailView(asset: asset) }
            }
            .background { StudioAtmosphere() }
        }.craftAmbientHost()
         .tint(appearance.ink)
         .sheet(isPresented: $signIn) { CraftSignInView() }
         .sheet(isPresented: $community) {
             VStack(spacing: 0) {
                 HStack { Spacer(); Button(store.t("Done", "完成")) { community=false }.padding() }
                 CommunityGamesView()
             }.tint(appearance.ink)
         }
    }
}
