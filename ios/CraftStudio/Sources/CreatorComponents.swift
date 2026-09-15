import SwiftUI

struct CraftBrand: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var body: some View {
        Label {
            Text("3D Craft").font(.system(size: 24, weight: .bold, design: .rounded))
        } icon: {
            Image(systemName: "cube.fill").symbolRenderingMode(.palette)
                .foregroundStyle(appearance.ink, appearance.fill).font(.system(size: 29))
        }.foregroundStyle(.primary)
    }
}

struct CraftHeadline: View {
    let title: String
    let accent: String
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
            Text(accent)
                .foregroundStyle(
                    LinearGradient(colors: [appearance.ink, appearance.deep],
                                   startPoint: .leading, endPoint: .trailing))
        }
        .font(.system(size: 35, weight: .bold, design: .rounded))
        .fixedSize(horizontal: false, vertical: true)
        .animation(CraftMotion.gated(.cinema, reduceMotion), value: appearance)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// The original single-item arrival, now the first slot of the shared
    /// staggered entrance ladder. Existing call sites keep working.
    func craftArrival() -> some View { craftEntrance(0, style: .reveal) }
}

/// The mockups' step rail: a filled accent badge with a soft halo, joined to
/// its neighbours by connectors that fill forward as the act advances.
struct CraftSteps: View {
    let selected: Int
    let chinese: Bool
    /// Defaults to Idea / Concept / 3D. Pass three strings to relabel; they
    /// must already be localized by the caller.
    var titles: [String]? = nil
    var onConcept: (() -> Void)? = nil
    var conceptIndex: Int = 1

    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var labels: [String] {
        if let titles, titles.count == 3 { return titles }
        return chinese ? ["灵感", "概念", "3D"] : ["Idea", "Concept", "3D"]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { connector(index).padding(.top, 14) }
                if index == conceptIndex, let onConcept {
                    Button(action: onConcept) { stepLabel(index).frame(minHeight: 44) }
                        .buttonStyle(CraftPressStyle())
                        .accessibilityIdentifier("studio.openConcept")
                        .accessibilityHint(chinese ? "查看生成此模型时使用的概念图" : "View the concept image used to create this model")
                } else {
                    stepLabel(index)
                }
            }
        }
        .animation(CraftMotion.gated(.glide, reduceMotion), value: selected)
        .craftFeedback(.stepAdvance, trigger: selected)
        .accessibilityElement(children: onConcept == nil ? .ignore : .contain)
        .accessibilityLabel(
            chinese
                ? "第 \(selected + 1) 步，共 3 步：\(labels[min(selected, 2)])"
                : "Step \(selected + 1) of 3: \(labels[min(selected, 2)])")
    }

    private func stepLabel(_ index: Int) -> some View {
        VStack(spacing: 3) {
            badge(index)
            Text(labels[index])
                .font(.caption.weight(index == selected ? .semibold : .regular))
                .foregroundStyle(index == selected || (index == conceptIndex && onConcept != nil) ? appearance.ink : Color.secondary)
                .fixedSize()
        }
    }

    @ViewBuilder private func badge(_ index: Int) -> some View {
        ZStack {
            if index == selected {
                Circle()
                    .fill(appearance.fill.opacity(0.24))
                    .frame(width: 30, height: 30)
            }
            if index < selected {
                Circle().fill(appearance.fill).frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white)
                            .craftSymbolPop(selected, reduceMotion: reduceMotion)
                    )
            } else if index == selected {
                Circle().fill(appearance.gradient).frame(width: 16, height: 16)
                    .shadow(color: appearance.deep.opacity(0.42), radius: 6, y: 2)
            } else {
                Circle().fill(Color.secondary.opacity(0.20)).frame(width: 14, height: 14)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private func connector(_ index: Int) -> some View {
        Capsule().fill(Color.secondary.opacity(0.18))
            .frame(height: 2)
            .frame(minWidth: 18)
            .overlay(alignment: .leading) {
                Capsule().fill(appearance.fill)
                    .frame(height: 2)
                    .scaleEffect(x: index <= selected ? 1 : 0, anchor: .leading)
            }
            .accessibilityHidden(true)
    }
}

/// The Profile mockup's preview card: the sample character with the two
/// drifting accent shapes bleeding in behind it.
struct CraftPreview: View {
    let chinese: Bool
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var profile = CraftProfile.shared

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                Label(chinese ? "你的下一个作品" : "Your next creation", systemImage: "cube")
                    .font(.headline)
                Label(chinese ? "生成概念图" : "Create a concept", systemImage: "sparkles")
                    .font(.caption.bold()).padding(.horizontal, 16).padding(.vertical, 12)
                    .foregroundStyle(appearance.buttonInk)
                    .background(appearance.gradient, in: Capsule())
                    .shadow(color: appearance.deep.opacity(0.30), radius: 10, y: 5)
            }
            Spacer(minLength: 0)
            ZStack {
                CraftAccentStar(size: 30, period: 4.9).offset(x: -52, y: -34)
                CraftAccentCube(size: 32, period: 6.3, delay: 0.4).offset(x: 42, y: 30)
                if let image = profile.avatar {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 112, height: 145)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else if let url = CraftAsset.lantern.modelURL {
                    ModelViewport(modelURL: url, chinese: chinese, softStage: true)
                        .frame(width: 112, height: 145).allowsHitTesting(false)
                }
            }
            .frame(width: 132, height: 145)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(appearance.wash, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(CraftMotion.gated(.cinema, reduceMotion), value: appearance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.avatar != nil
                            ? (chinese ? "外观预览，使用你的头像" : "Appearance preview using your avatar")
                            : (chinese ? "外观预览，使用示例角色" : "Appearance preview using a sample character"))
    }
}

// Bundled display images are not asset-catalog names. Resolve the file explicitly.
enum CraftPortrait {
    static let image: UIImage = CraftAsset.lantern.thumbURL.flatMap { UIImage(contentsOfFile: $0.path) } ?? UIImage(systemName: "person.crop.circle")!
}

struct CraftAvatar: View {
    var size: CGFloat = 44
    /// The white ring plus contact shadow the mockups give every avatar.
    var ringed: Bool = true
    var previewImage: UIImage? = nil
    var usesProfile = true
    @ObservedObject private var profile = CraftProfile.shared
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var body: some View {
        Group {
            if let custom = usesProfile ? profile.avatar : previewImage {
                Image(uiImage: custom).resizable().scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(uiImage: CraftPortrait.image).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .scaleEffect(3, anchor: .top).offset(y: -size * 0.13)
            }
        }
            .frame(width: size, height: size)
            .background(appearance.washSoft, in: Circle()).clipShape(Circle())
            .contentShape(Circle())
            .overlay {
                if ringed {
                    Circle().strokeBorder(.white, lineWidth: size > 56 ? 3 : 2)
                }
            }
            .shadow(color: .black.opacity(ringed ? 0.10 : 0), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}
