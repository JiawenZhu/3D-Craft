import SwiftUI
import PhotosUI

struct ProfileEditorView: View {
    @EnvironmentObject private var store: CraftStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @ObservedObject private var profile = CraftProfile.shared
    @State private var name = ""
    @State private var avatar: UIImage?
    @State private var assetID: String?
    @State private var photo: PhotosPickerItem?
    @State private var loading = false
    @State private var message: String?
    @State private var initialized = false

    private var validName: Bool {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 32 && !text.contains(where: \.isNewline)
    }

    var body: some View {
        let choosePhotoTitle = store.t("Choose photo", "选择照片")
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 12) {
                        CraftAvatar(size: 104, previewImage: avatar, usesProfile: false)
                        Text(store.t("Make this space yours.", "让这里成为你的空间。"))
                            .font(.title3.bold())
                        Text(store.t("Saved on this device.", "保存在此设备。"))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Display name", "显示名称")).font(.headline)
                        TextField(store.t("Your name", "你的名称"), text: $name)
                            .textContentType(.nickname).submitLabel(.done)
                            .padding(16).background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            .accessibilityIdentifier("profile.name")
                        Text(store.t("1–32 characters", "1–32 个字符")).font(.caption).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label(choosePhotoTitle, systemImage: "photo")
                        }.buttonStyle(CraftSecondary()).accessibilityIdentifier("profile.choosePhoto")
                        Button {
                            avatar = nil; assetID = nil; photo = nil; message = nil
                        } label: { Label(store.t("Default cat", "默认小猫"), systemImage: "arrow.counterclockwise") }
                            .buttonStyle(CraftSecondary()).accessibilityIdentifier("profile.defaultAvatar")
                    }.disabled(loading)

                    if loading { ProgressView(store.t("Preparing your avatar…", "正在准备头像……")) }
                    if let message { Text(message).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("profile.error") }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.t("Choose from your library", "从资产库选择")).font(.headline)
                        Text(store.t("Use a creation’s preview as your avatar. Its 3D model stays unchanged.",
                                     "将作品预览设为头像，原有 3D 模型保持不变。"))
                            .font(.caption).foregroundStyle(.secondary)
                        if store.assets.isEmpty {
                            Text(store.t("Your generated creations will appear here.", "生成的作品会显示在这里。"))
                                .foregroundStyle(.secondary).padding(.vertical, 14)
                        }
                        ForEach(store.assets) { asset in
                            Button { Task { await choose(asset) } } label: {
                                HStack(spacing: 14) {
                                    CraftThumbnailImage(url: asset.thumbURL, inset: 2)
                                        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(asset.name).font(.subheadline.weight(.medium)).lineLimit(2)
                                        if asset.thumbURL == nil {
                                            Text(store.t("No preview available", "暂无预览图")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: assetID == asset.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(appearance.ink)
                                }.padding(12).background(CraftTheme.card, in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(CraftPressStyle()).disabled(loading || asset.thumbURL == nil)
                                .accessibilityIdentifier("profile.avatar." + asset.id)
                                .accessibilityAddTraits(assetID == asset.id ? .isSelected : [])
                        }
                    }
                }.padding(22).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background { StudioAtmosphere(intensity: 0.65) }
            .navigationTitle(store.t("Edit profile", "编辑个人资料")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Cancel", "取消")) { dismiss() }.accessibilityIdentifier("profile.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Save", "保存")) { save() }.fontWeight(.semibold)
                        .disabled(!validName || loading).accessibilityIdentifier("profile.save")
                }
            }
            .tint(appearance.ink)
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            name = profile.displayName(chinese: store.isChinese)
            avatar = profile.avatar
            assetID = profile.record.avatarAssetID
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                loading = true; message = nil
                defer { loading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          data.count <= 20 * 1024 * 1024, let image = UIImage(data: data) else {
                        throw CraftProfile.ProfileError.invalidImage
                    }
                    avatar = image; assetID = nil
                } catch {
                    message = store.t("Could not open this photo. Try another image under 20 MB.",
                                      "无法打开这张照片，请选择另一张小于 20 MB 的图片。")
                }
            }
        }
    }

    @MainActor private func choose(_ asset: CraftAsset) async {
        guard let url = asset.thumbURL else { return }
        loading = true; message = nil
        defer { loading = false }
        do {
            guard let data = await CraftThumbnailCache.shared.imageData(for: url),
                  data.count <= 20 * 1024 * 1024, let image = UIImage(data: data) else {
                throw CraftProfile.ProfileError.invalidImage
            }
            avatar = image; assetID = asset.id; photo = nil
        } catch {
            message = store.t("Could not load this preview. Check your connection and try again.",
                              "无法加载此预览，请检查网络连接后重试。")
        }
    }

    private func save() {
        do {
            try profile.save(name: name, avatar: avatar, assetID: assetID)
            dismiss()
        } catch {
            message = store.t("Your profile could not be saved. Please try again.", "无法保存个人资料，请重试。")
        }
    }
}
