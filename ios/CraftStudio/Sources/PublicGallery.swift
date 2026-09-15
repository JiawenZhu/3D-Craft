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
                        Label("3D Craft", systemImage: "cube.fill").font(.title2.bold())
                        Spacer()
                        Button("Sign in") { signIn = true }
                    }
                    Text("What will you create?").font(.largeTitle.bold())
                    Button { community = true } label: { Label(store.t("Community games", "社区游戏"), systemImage: "trophy") }
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
         .sheet(isPresented: $signIn) { CraftSignInView() }
         .sheet(isPresented: $community) {
             VStack(spacing: 0) {
                 HStack { Spacer(); Button(store.t("Done", "完成")) { community=false }.padding() }
                 CommunityGamesView()
             }
         }
    }
}
