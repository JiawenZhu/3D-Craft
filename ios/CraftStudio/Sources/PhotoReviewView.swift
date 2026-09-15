import SwiftUI
import UIKit

/// Review happens before the image becomes a generation reference.
/// Rendering creates upright pixels and strips source-file metadata.
struct PhotoReviewView: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let chinese: Bool
    let onUse: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var workingImage: UIImage
    @State private var squareCrop = false
    @State private var confirmsOneSubject = false
    /// Rendered once per rotation instead of on every body pass — the preview
    /// now cross-fades, and re-rasterising a full photo per frame would show.
    @State private var squareImage: UIImage?
    @State private var rotations = 0
    @State private var rotateCount = 0
    @State private var useCount = 0
    @State private var scrollY: CGFloat = 0

    init(image: UIImage, chinese: Bool, onUse: @escaping (UIImage) -> Void) {
        self.chinese = chinese
        self.onUse = onUse
        _workingImage = State(initialValue: Self.upright(image))
    }

    private let background = Color.white
    private var lilac: Color { appearance.ink }
    private func t(_ en: String, _ zh: String) -> String { chinese ? zh : en }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    preview
                    tools
                    guidance

                    Text(t("This step only prepares your image. No upload or generation starts until you confirm creation in the next step.", "此步骤仅准备图片；在下一步确认创作前，不会上传或开始生成。"))
                        .font(.caption).foregroundStyle(.secondary)
                        .craftEntrance(6)
                }
                .padding(22)
                .craftScrollProbe()
            }
            .onPreferenceChange(CraftScrollOffsetKey.self) { scrollY = $0 }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .background { StudioAtmosphere(intensity: 1.05, scrollProgress: min(1, Double(scrollY) / 600)) }
            .navigationTitle(t("Review reference", "检查参考图"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(t("Cancel", "取消")) { dismiss() }.foregroundStyle(.secondary)
                }
            }
        }
        .preferredColorScheme(.light)
        .craftFeedback(.viewReset, trigger: rotateCount)
        .craftFeedback(.optionSelect, trigger: squareCrop)
        .craftFeedback(.referenceAttached, trigger: useCount)
        .craftAmbientHost()
    }

    // MARK: - Sections

    private var headline: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("One subject.\nA clearer creation.", "一个主体，\n更清晰的创作。"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .craftEntrance(0)
                Text(t("Keep the whole character or object visible, including its feet, wheels, or wings.", "让角色或物体完整入镜，包括脚、车轮或翅膀。"))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .craftEntrance(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CraftAccentStar(size: 34, period: 5.2)
                .offset(x: 2, y: -6)
                .craftParallax(0.24, offset: scrollY)
                .craftEntrance(2, style: .popIn)
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            Group {
                if squareCrop, let squareImage {
                    Image(uiImage: squareImage)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(appearance.fill, lineWidth: 1.5)
                        )
                        .accessibilityLabel(t("Centered square crop preview", "居中方形裁剪预览"))
                        .transition(.opacity)
                } else {
                    Image(uiImage: workingImage)
                        .resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityLabel(t("Full reference photo preview", "完整参考照片预览"))
                        .id(rotations)
                        .transition(.opacity)
                }
            }

            Text(squareCrop
                 ? t("Centered square crop · Edges outside the square will be removed", "居中方形裁剪 · 方框以外的边缘将被移除")
                 : t("Full image · Original proportions preserved", "完整图片 · 保留原始比例"))
                .font(.caption).foregroundStyle(.secondary)
                .contentTransition(.opacity)
                .multilineTextAlignment(.center).padding(.horizontal, 12)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .craftDepth(.raised)
        .craftEntrance(3, style: .reveal)
    }

    private var tools: some View {
        HStack(spacing: 12) {
            Button(action: rotate) {
                toolLabel(t("Rotate 90°", "旋转 90°"), icon: "rotate.right", on: false, trigger: rotateCount)
            }
            .buttonStyle(CraftPressStyle())
            .accessibilityLabel(t("Rotate 90°", "旋转 90°"))
            .accessibilityIdentifier("photoReviewRotate")

            Button(action: toggleCrop) {
                toolLabel(t("Square crop", "方形裁剪"),
                          icon: squareCrop ? "crop.rotate" : "crop",
                          on: squareCrop,
                          trigger: squareCrop ? 1 : 0)
            }
            .buttonStyle(CraftPressStyle())
            .accessibilityLabel(t("Square crop", "方形裁剪"))
            .accessibilityAddTraits(squareCrop ? .isSelected : [])
            .accessibilityIdentifier("photoReviewSquareCrop")
        }
        .craftEntrance(4)
    }

    private func toolLabel(_ title: String, icon: String, on: Bool, trigger: Int) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? appearance.ink : Color.secondary)
                .craftSymbolPop(trigger, reduceMotion: reduceMotion)
                .frame(width: 38, height: 38)
                .background(on ? appearance.washStrong : appearance.washSoft, in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? appearance.ink : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(on ? appearance.wash : Color.white,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .craftSelectionRing(on, color: appearance.fill, cornerRadius: 22, lineWidth: 1.5, glow: false)
        .craftDepth(.card)
        .animation(CraftMotion.gated(.snap, reduceMotion), value: on)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                Image(systemName: "person.crop.rectangle.badge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(lilac)
                    .frame(width: 34, height: 34)
                    .background(appearance.washSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(t("Avoid merged characters", "避免角色融合"))
                    .font(.headline).foregroundStyle(lilac)
            }
            Text(t("Multiple people, animals, or cars in one photo can merge into a single incorrect 3D model. Choose a photo with one main subject. If cropping cuts off part of it, keep the full image or choose another photo.", "一张照片中出现多个人、动物或汽车，可能被融合成一个错误的 3D 模型。请选择只有一个主要主体的照片。如果裁剪切掉了主体的一部分，请保留完整图片或更换照片。"))
                .font(.subheadline).foregroundStyle(.secondary)
            Divider().opacity(0.4)
            Toggle(t("My reference has one clear main subject", "我的参考图只有一个清晰的主要主体"), isOn: $confirmsOneSubject)
                .font(.subheadline.weight(.medium)).tint(lilac)
                .accessibilityIdentifier("photoReviewOneSubject")
        }
        .padding(18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .craftSelectionRing(confirmsOneSubject, color: appearance.fill, cornerRadius: 24,
                            lineWidth: 1.5, glow: false)
        .craftDepth(.card)
        .animation(CraftMotion.gated(.snap, reduceMotion), value: confirmsOneSubject)
        .craftEntrance(5)
    }

    private var bottomBar: some View {
        Button {
            let prepared = squareCrop
                ? (squareImage ?? Self.centerSquare(workingImage))
                : Self.upright(workingImage)
            useCount += 1
            onUse(prepared)
            dismiss()
        } label: {
            Text(t("Use this photo", "使用这张照片"))
        }
        .buttonStyle(CraftPrimary(armed: confirmsOneSubject))
        .disabled(!confirmsOneSubject)
        .accessibilityIdentifier("photoReviewUse")
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: 28,
                                   style: .continuous)
                .fill(background)
                .shadow(color: .black.opacity(0.06), radius: 18, y: -5)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Actions

    private func rotate() {
        let rotated = Self.rotatedClockwise(workingImage)
        let square = squareCrop ? Self.centerSquare(rotated) : nil
        withAnimation(CraftMotion.gated(.glide, reduceMotion)) {
            workingImage = rotated
            squareImage = square
            rotations += 1
        }
        rotateCount += 1
    }

    private func toggleCrop() {
        if squareImage == nil { squareImage = Self.centerSquare(workingImage) }
        withAnimation(CraftMotion.gated(.glide, reduceMotion)) { squareCrop.toggle() }
    }

    private static func renderer(size: CGSize, scale: CGFloat) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func upright(_ image: UIImage) -> UIImage {
        renderer(size: image.size, scale: image.scale).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: image.size))
            // UIImage.draw applies EXIF orientation to the pixels. The new
            // renderer result has orientation .up and no EXIF/GPS payload.
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func rotatedClockwise(_ image: UIImage) -> UIImage {
        let size = CGSize(width: image.size.height, height: image.size.width)
        return renderer(size: size, scale: image.scale).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                  width: image.size.width, height: image.size.height))
        }
    }

    private static func centerSquare(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        return renderer(size: CGSize(width: side, height: side), scale: image.scale).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(at: CGPoint(x: (side - image.size.width) / 2, y: (side - image.size.height) / 2))
        }
    }
}
