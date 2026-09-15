import SwiftUI
import UIKit

/// Full-resolution inspection of the selected concept, independent of its grid thumbnail.
struct ConceptImageInspector: View {
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    let imageURL: URL
    let chinese: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var error: String?
    @State private var retry = 0
    @State private var resetID = 0
    @State private var zoomCount = 0
    @State private var closeCount = 0
    @State private var hintVisible = false

    private var pixelReading: String {
        guard let image else { return "" }
        return "\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) px"
    }

    var body: some View {
        ZStack {
            StudioAtmosphere(intensity: 0.8)

            // A faint accent bloom keeps the source preview in the selected theme.
            RadialGradient(colors: [appearance.fill.opacity(0.16), .clear],
                           center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .craftBreathe(active: image != nil, from: 0.55, to: 0.95, period: 6.4)

            if let image {
                ZoomableConceptImage(image: image, resetID: resetID) { zoomCount += 1 }
                    .padding(.top, 76).padding(.bottom, 52)
                    .accessibilityLabel(chinese ? "概念原图。双指缩放，拖动查看细节。" : "Original concept. Pinch to zoom and drag to inspect details.")
                    .craftEntrance(0, style: .reveal)
            } else if let error {
                VStack(spacing: 18) {
                    Image(systemName: "photo.badge.exclamationmark").font(.system(size: 36)).foregroundStyle(.secondary)
                        .craftSymbolPop(retry, reduceMotion: reduceMotion)
                    Text(chinese ? "无法载入原图" : "Couldn’t load the original").font(.headline)
                    Text(error).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(chinese ? "重试" : "Try again") { retry += 1 }
                        .buttonStyle(.borderedProminent).tint(appearance.fill)
                }.padding(30)
                .craftEntrance(0, style: .popIn)
            } else {
                VStack(spacing: 15) {
                    ProgressView().tint(appearance.ink)
                    Text(chinese ? "正在载入高清原图…" : "Loading the full-resolution image…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .craftEntrance(0, style: .fade)
            }

            VStack {
                HStack(spacing: 16) {
                    Button {
                        closeCount += 1
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                            .frame(width: 46, height: 46)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(appearance.hairline))
                    }
                    .buttonStyle(CraftPressStyle(scale: 0.90))
                    .accessibilityLabel(chinese ? "关闭原图" : "Close image").accessibilityIdentifier("concept.inspector.close")

                    Spacer()
                    VStack(spacing: 4) {
                        Text(chinese ? "概念原图" : "Original concept").font(.headline)
                        if image != nil {
                            Text(pixelReading)
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .craftNumeric(pixelReading, reduceMotion: reduceMotion)
                        }
                    }
                    Spacer()
                    Button {
                        resetID += 1
                    } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 17, weight: .semibold))
                            .craftSymbolPop(resetID, reduceMotion: reduceMotion)
                            .frame(width: 46, height: 46)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(appearance.hairline))
                    }
                    .buttonStyle(CraftPressStyle(scale: 0.90))
                    .disabled(image == nil).accessibilityLabel(chinese ? "重置缩放" : "Reset zoom")
                        .accessibilityIdentifier("concept.inspector.reset")
                }
                .padding(.horizontal, 20).padding(.top, 12)
                .craftEntrance(0, style: .fade)

                Spacer()
                if image != nil {
                    Text(chinese ? "双指缩放 · 拖动查看 · 双击放大" : "Pinch to zoom · Drag to explore · Double-tap for detail")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(.regularMaterial, in: Capsule(style: .continuous))
                        .padding(.bottom, 16)
                        .opacity(hintVisible ? 1 : 0)
                }
            }
        }
        .foregroundStyle(appearance.ink)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
        .craftFeedback(.viewReset, trigger: resetID)
        .craftFeedback(.lightTap, trigger: zoomCount)
        .craftAmbientHost()
        .onChange(of: image == nil) { _, empty in
            // The hint arrives once the picture has settled, then retires for
            // good the first time the reader actually zooms.
            withAnimation(CraftMotion.gated(CraftMotion.reveal.delay(0.5), reduceMotion)) {
                hintVisible = !empty
            }
        }
        .onChange(of: zoomCount) { _, _ in
            withAnimation(CraftMotion.gated(.fade, reduceMotion)) { hintVisible = false }
        }
        .task(id: "\(imageURL.absoluteString)-\(retry)") { await loadImage() }
    }

    @MainActor private func loadImage() async {
        image = nil
        error = nil
        do {
            let data: Data
            if imageURL.isFileURL {
                data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: imageURL) }.value
            } else {
                let response: URLResponse
                (data, response) = try await CraftCloudMedia.data(imageURL)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
            }
            try Task.checkCancellation()
            guard let decoded = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            withAnimation(CraftMotion.gated(.cinema, reduceMotion)) { image = decoded }
        } catch is CancellationError {
            // Closing or switching the selected concept cancels its old request.
        } catch {
            guard !Task.isCancelled else { return }
            self.error = chinese ? "请检查连接，然后重试。你的概念图仍保存在资产库中。" : "Check your connection and try again. Your concept is still saved in the library."
        }
    }
}

private struct ZoomableConceptImage: UIViewRepresentable {
    let image: UIImage
    let resetID: Int
    /// Fires on a double-tap zoom so SwiftUI can answer with a haptic and
    /// retire the on-screen hint. Called from a gesture, never from layout.
    var onZoom: () -> Void = {}
    func makeUIView(context: Context) -> ConceptZoomScrollView {
        let view = ConceptZoomScrollView()
        view.setImage(image)
        view.onZoom = onZoom
        return view
    }
    func updateUIView(_ view: ConceptZoomScrollView, context: Context) {
        view.onZoom = onZoom
        if view.imageView.image !== image { view.setImage(image) }
        if view.lastReset != resetID { view.lastReset = resetID; view.fitImage(animated: true) }
    }
}

private final class ConceptZoomScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var lastReset = 0
    var onZoom: () -> Void = {}
    private var previousSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomToDetail(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setImage(_ image: UIImage) {
        setZoomScale(1, animated: false)
        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        previousSize = .zero
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, imageView.image != nil else { return }
        if bounds.size != previousSize {
            previousSize = bounds.size
            fitImage(animated: false)
        }
        centerImage()
    }
    func fitImage(animated: Bool) {
        guard let image = imageView.image, bounds.width > 0, bounds.height > 0 else { return }
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        minimumZoomScale = fit
        // At least 8× fitted scale, and enough zoom to inspect source pixels.
        maximumZoomScale = max(fit * 8, image.scale)
        setZoomScale(fit, animated: animated)
        centerImage()
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }
    @objc private func zoomToDetail(_ recognizer: UITapGestureRecognizer) {
        onZoom()
        if zoomScale > minimumZoomScale * 1.1 { fitImage(animated: true); return }
        let targetScale = min(maximumZoomScale, minimumZoomScale * 3)
        let point = recognizer.location(in: imageView)
        let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
    }
}
