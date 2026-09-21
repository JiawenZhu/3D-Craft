import SwiftUI
import AVFoundation

/// The interactive animated showcase introducing and previewing Desktop Gadgets.
///
/// Designed to match the MonAi luxury OLED aesthetic from `CraftIntroductionView` (Image 4):
/// - Deep OLED backdrop with ambient radial aura
/// - Multi-style live widget previews corresponding to the user's circled icons (Image 3)
/// - Simulated iOS Home Screen context preview (Image 1)
/// - Haptic-rich selection and "Set as Active Gadget" action
public struct CraftGadgetShowcaseView: View {
    let asset: CraftAsset
    let localVideoURL: URL?
    var onDismiss: () -> Void

    @AppStorage("craftChinese") private var isChinese: Bool = (Locale.current.language.languageCode?.identifier == "zh")
    @State private var selectedStyle: CraftGadgetStyle = .small
    @State private var isSaved: Bool = false
    @State private var showSavedToast: Bool = false
    @State private var currentStep: Int = 0

    private var warmGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.56, blue: 0.42), Color(red: 1.0, green: 0.46, blue: 0.54)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cyanGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.22, green: 0.82, blue: 0.98), Color(red: 0.35, green: 0.55, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var body: some View {
        ZStack {
            // Deep OLED black background
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()

            // Ambient soft lighting aura
            Circle()
                .fill(selectedStyle == .large ? Color.purple.opacity(0.18) : Color(red: 1.0, green: 0.4, blue: 0.2).opacity(0.18))
                .blur(radius: 80)
                .frame(width: 320, height: 320)
                .offset(y: -40)
                .animation(.easeInOut(duration: 0.6), value: selectedStyle)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top Bar
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                // Header
                headerSection
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                // Style Selector Tabs
                styleSelector
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                // Simulated Widget Preview Stage
                widgetPreviewStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 16)

                Spacer(minLength: 8)

                // Home Screen Guide Hint
                setupHint
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                // Bottom Action CTA
                bottomActionButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            triggerHaptic()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(warmGradient)
                Text(isChinese ? "3D Craft 桌面组件" : "3D Craft Gadgets")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())

            Spacer()

            Button {
                triggerHaptic()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(CraftPressStyle(scale: 0.94))
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(isChinese ? "把角色带上 " : "Bring your character to ")
                Text(isChinese ? "桌面小组件" : "Desktop Gadgets")
                    .foregroundStyle(warmGradient)
            }
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

            Text(isChinese ? "选择你喜欢的组件规格，4 秒无缝物理动画在手机桌面常驻播放。"
                           : "Choose your gadget size. Watch your character come alive on your Home Screen.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Style Selector

    private var styleSelector: some View {
        HStack(spacing: 8) {
            ForEach(CraftGadgetStyle.allCases) { style in
                let isSelected = selectedStyle == style
                Button {
                    triggerHaptic()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        selectedStyle = style
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: style.systemImage)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        Text(styleTitle(style))
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    }
                    .foregroundStyle(isSelected ? .black : Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.10))
                    )
                    .overlay(
                        Capsule().strokeBorder(isSelected ? warmGradient : LinearGradient(colors: [Color.white.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: isSelected ? 1.5 : 0.8)
                    )
                }
                .buttonStyle(CraftPressStyle(scale: 0.95))
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.04), in: Capsule())
    }

    private func styleTitle(_ style: CraftGadgetStyle) -> String {
        switch style {
        case .small: return isChinese ? "小组件 2x2" : "Small 2x2"
        case .medium: return isChinese ? "宽组件 4x2" : "Wide 4x2"
        case .large: return isChinese ? "大展台 4x4" : "Large 4x4"
        }
    }

    // MARK: - Widget Preview Stage

    private var widgetPreviewStage: some View {
        ZStack {
            // Simulated Home Screen Blurred Wallpaper Stage
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.14).opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 24, y: 12)

            // Inner ambient grid dots mimicking home screen icons
            VStack {
                HStack {
                    simulatedAppIcon(name: "Photos", color: .purple)
                    Spacer()
                    simulatedAppIcon(name: "Camera", color: .gray)
                }
                Spacer()
                HStack {
                    simulatedAppIcon(name: "Music", color: .red)
                    Spacer()
                    simulatedAppIcon(name: "Files", color: .blue)
                }
            }
            .padding(18)
            .opacity(0.35)

            // The Simulated Widget
            Group {
                switch selectedStyle {
                case .small:
                    smallWidgetView
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                case .medium:
                    mediumWidgetView
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                case .large:
                    largeWidgetView
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedStyle)
        }
    }

    private func simulatedAppIcon(name: String, color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.4))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    // MARK: - Small Widget (Circled Icon 2)

    private var smallWidgetView: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.11)
            // Video / Image stage
            widgetMediaLayer
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: 158, height: 158)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 18, y: 8)
    }

    // MARK: - Medium Widget (Circled Icon 5)

    private var mediumWidgetView: some View {
        HStack(spacing: 0) {
            // Left: Square animation stage
            ZStack(alignment: .bottomLeading) {
                widgetMediaLayer
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("Loop")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(8)
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(9)

            // Right: Studio metadata & quick action info
            VStack(alignment: .leading, spacing: 6) {
                Text(asset.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Label("MiniMax / Seedance", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(warmGradient)

                Text(isChinese ? "首尾帧无缝闭环物理动作" : "Seamless 4s physics loop")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 9))
                    Text(isChinese ? "轻点打开 3D 查看" : "Tap to open in 3D")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            Spacer()
        }
        .frame(width: 320, height: 158)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 18, y: 8)
    }

    // MARK: - Large Widget (Circled Icon 4)

    private var largeWidgetView: some View {
        VStack(spacing: 8) {
            // Grand Character Stage
            ZStack(alignment: .topTrailing) {
                widgetMediaLayer
                    .frame(height: 175)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("4s Physics Loop")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // Info & Quick Action Grid
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(asset.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("3D Craft Studio")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(warmGradient)
                }

                HStack(spacing: 6) {
                    largeSpecTag(icon: "cube.fill", text: "PBR 3D")
                    largeSpecTag(icon: "repeat", text: isChinese ? "首尾闭环" : "Looping")
                    largeSpecTag(icon: "gamecontroller.fill", text: isChinese ? "游戏试玩" : "Playable")
                }

                Spacer(minLength: 2)

                HStack {
                    Label(isChinese ? "轻点在 app 中 360° 旋转把玩" : "Tap to inspect 360° in app", systemImage: "hand.draw")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 290, height: 290)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 20, y: 10)
    }

    private func largeSpecTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(warmGradient)
            Text(text)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Media Layer

    @ViewBuilder
    private var widgetMediaLayer: some View {
        if let localVideoURL {
            CraftLoopingVideo(url: localVideoURL, playing: true)
        } else if let thumb = asset.thumbURL {
            CraftThumbnailImage(url: thumb)
                .scaledToFill()
        } else {
            Color.gray.opacity(0.3)
        }
    }

    // MARK: - Setup Hint (Step Guide)

    private var setupHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(warmGradient)
            Text(isChinese
                 ? "长按桌面空白处或应用图标，点击小组件即可随时添加 3D Craft。"
                 : "Long-press Home Screen or app icon, tap widgets to add 3D Craft.")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.65))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bottom CTA Button

    private var bottomActionButton: some View {
        Button {
            saveAsActiveGadget()
        } label: {
            HStack(spacing: 8) {
                if isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text(isChinese ? "已成功设为主屏幕组件 (即将推出)" : "Added to Desktop Gadgets (Coming Soon)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Image(systemName: "plus.app.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(isChinese ? "设为主屏幕组件 (即将推出)" : "Set as Active Gadget (Coming Soon)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                isSaved ? LinearGradient(colors: [Color.green.opacity(0.8), Color.teal.opacity(0.8)], startPoint: .leading, endPoint: .trailing) : warmGradient
            )
            .clipShape(Capsule())
            .shadow(color: Color(red: 1.0, green: 0.46, blue: 0.54).opacity(isSaved ? 0.2 : 0.35), radius: 14, y: 6)
        }
        .buttonStyle(CraftPressStyle(scale: 0.96))
    }

    // MARK: - Save Action

    private func saveAsActiveGadget() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        Task {
            var heroImage: UIImage? = nil
            if let localVideoURL {
                heroImage = await CraftGadgetCenter.shared.extractHeroKeyframe(from: localVideoURL)
            }
            if heroImage == nil, let thumbURL = asset.thumbURL {
                if let data = await CraftImageCache.shared.data(for: thumbURL) {
                    heroImage = UIImage(data: data)
                }
                if heroImage == nil {
                    heroImage = await CraftGadgetCenter.shared.downloadImage(from: thumbURL)
                }
            }

            let data = CraftGadgetData(
                id: asset.id,
                name: asset.name,
                modelName: "MiniMax / Seedance",
                prompt: asset.name,
                loopDuration: "4s Loop",
                style: selectedStyle,
                imageFileName: nil,
                updatedAt: .now
            )
            CraftGadgetCenter.shared.setActiveGadget(data, image: heroImage)

            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    isSaved = true
                }
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                onDismiss()
            }
        }
    }

    private func triggerHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
