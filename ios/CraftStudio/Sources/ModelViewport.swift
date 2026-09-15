import SwiftUI
import SceneKit
import GLTFKit2
import MetalKit

enum CraftLightingPreset: String, CaseIterable, Identifiable {
    case studio, rim, sunset, night, flat
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .studio: return chinese ? "工作室" : "Studio"
        case .rim: return chinese ? "轮廓光" : "Rim"
        case .sunset: return chinese ? "日落" : "Sunset"
        case .night: return chinese ? "夜景" : "Night"
        case .flat: return chinese ? "均匀光" : "Flat"
        }
    }
}

private struct CraftLightRig {
    let key: CGFloat, rim: CGFloat, ambient: CGFloat, environment: CGFloat, exposure: CGFloat
    let keyColor: UIColor, rimColor: UIColor, background: UIColor, softbox: UIColor, floor: UIColor
    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static func preset(_ preset: CraftLightingPreset) -> CraftLightRig {
        // Website hue/background relationships, calibrated for SceneKit's light units.
        switch preset {
        case .studio: return .init(key: 650, rim: 350, ambient: 400, environment: 1.5, exposure: 0.0, keyColor: .white, rimColor: color(0xdce4ff), background: color(0x1e1f25), softbox: .white, floor: color(0xb6bcc7))
        case .rim: return .init(key: 440, rim: 900, ambient: 145, environment: 0.85, exposure: -0.3, keyColor: color(0xffd9bd), rimColor: color(0x8fd8ff), background: color(0x121319), softbox: color(0xe8f0ff), floor: color(0x6b7381))
        case .sunset: return .init(key: 720, rim: 470, ambient: 190, environment: 1.0, exposure: -0.3, keyColor: color(0xffb877), rimColor: color(0xa887ff), background: color(0x201815), softbox: color(0xffd2a1), floor: color(0x9c7d68))
        case .night: return .init(key: 420, rim: 760, ambient: 155, environment: 0.85, exposure: -0.4, keyColor: color(0x9fb4ff), rimColor: color(0xd8a1f1), background: color(0x0f1017), softbox: color(0xb9c7ff), floor: color(0x6a7086))
        case .flat: return .init(key: 230, rim: 170, ambient: 280, environment: 1.45, exposure: -0.25, keyColor: .white, rimColor: .white, background: color(0x212228), softbox: .white, floor: color(0xd4d8de))
        }
    }
}

/// Native, touch-interactive glTF preview. Downloads remote assets before the GLTFKit2 importer runs.
///
/// The stage follows the shared motion contract in `CraftMotion.swift`: nothing
/// here loops unless it has been allowed to by Reduce Motion *and* the ambient
/// gate, and the render loop is only alive while something is actually moving.
struct ModelViewport: UIViewRepresentable {
    let modelURL: URL
    var mode: String = "Material"
    var resetID: Int = 0
    var autoRotate: Bool = false
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    var chinese: Bool = false
    var lighting: CraftLightingPreset = .studio
    var directional: Double = 1
    var environment: Double = 1
    var exposure: Double = 1
    var softStage: Bool = false
    /// The expanded viewer exposes explicit optical zoom alongside SceneKit's
    /// existing pinch/orbit gestures. UIKit owns the current camera state.
    var showsZoomControls: Bool = false
    /// The barely-there idle sway that keeps a settled character alive. It stops
    /// the instant a finger lands so it can never fight the orbit gesture, and it
    /// is never installed under Reduce Motion, in Low Power Mode, or while the
    /// scene is inactive. Pass `false` for a viewport that must hold perfectly still.
    var idleMotion: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.craftAmbientMotion) private var ambient

    /// The one gate every looping motion on this stage passes through.
    private var ambientAlive: Bool { !reduceMotion && ambient }

    func makeUIView(context: Context) -> ModelSceneView {
        let view = ModelSceneView()
        view.setReduceMotion(reduceMotion)
        view.setStageAppearance(softStage ? appearance : nil)
        view.setLanguage(chinese: chinese)
        view.setZoomControlsVisible(showsZoomControls)
        view.setLighting(lighting, directional: directional, environment: environment, exposure: exposure)
        view.load(modelURL)
        view.setMode(mode)
        view.setIdle(turntable: autoRotate && ambientAlive,
                     sway: idleMotion && !autoRotate && ambientAlive)
        return view
    }

    func updateUIView(_ view: ModelSceneView, context: Context) {
        view.setReduceMotion(reduceMotion)
        view.setStageAppearance(softStage ? appearance : nil)
        view.setLanguage(chinese: chinese)
        view.setZoomControlsVisible(showsZoomControls)
        view.setLighting(lighting, directional: directional, environment: environment, exposure: exposure)
        if view.sourceURL != modelURL { view.load(modelURL) }
        view.setMode(mode)
        view.setIdle(turntable: autoRotate && ambientAlive,
                     sway: idleMotion && !autoRotate && ambientAlive)
        if view.lastReset != resetID {
            view.lastReset = resetID
            view.resetCamera(animated: true)
        }
    }

    static func dismantleUIView(_ view: ModelSceneView, coordinator: ()) { view.cancel() }
}

final class ModelSceneView: UIView, UIGestureRecognizerDelegate {
    private let viewport = SCNView()
    private let zoomDock = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let zoomOutButton = UIButton(type: .system)
    private let zoomResetButton = UIButton(type: .system)
    private let zoomInButton = UIButton(type: .system)
    private var zoomControlsVisible = false
    // The loading state, as one group so it can cross-dissolve as a unit.
    private let loadingHost = UIView()
    private let arcHost = UIView()
    private let arcTrack = CAShapeLayer()
    private let arcStroke = CAShapeLayer()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let status = UILabel()
    private var model = SCNNode()
    private var camera = SCNNode()
    private var keyLight = SCNNode()
    private var rimLight = SCNNode()
    private var fillLight = SCNNode()
    private var ambientLight = SCNNode()
    private var backLight = SCNNode()
    private var bounceLight = SCNNode()
    private var stageRimMaterial: SCNMaterial?
    private var stageMaterial: SCNMaterial?
    private var modelSize = SIMD3<Float>(1, 2, 1)
    private var framedSize = CGSize.zero
    private var stageAppearance: CraftAppearance?
    private var lightingPreset: CraftLightingPreset = .studio
    private var directionalTrim: Double = 1
    private var environmentTrim: Double = 1
    private var exposureTrim: Double = 1
    private var appliedEnvironmentPreset: CraftLightingPreset?
    private var appliedStageKey: String?
    private static var environmentCache: [CraftLightingPreset: [UIImage]] = [:]
    private var originalMaterials: [(SCNGeometry, [SCNMaterial])] = []
    private var download: URLSessionDownloadTask?
    private var loadID = UUID()
    private var selectedMode = "material"
    private var turntables = false
    private var sways = false
    private var chinese = false
    private var reduceMotion = false
    /// A finger has landed on this stage, so the idle life is over until reset.
    private var handled = false
    private var interacting = false
    private var pendingArrival = false
    private var renderBoost = 0
    private var baseYaw: Float = 0
    private var statusMessage: String? { didSet { updateStatus() } }
    private var retainedAsset: GLTFAsset?
    private var cachedFile: URL?
    fileprivate var sourceURL: URL?
    fileprivate var lastReset = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        viewport.backgroundColor = .clear
        viewport.isOpaque = false
        viewport.antialiasingMode = .multisampling4X
        viewport.preferredFramesPerSecond = 60
        viewport.autoenablesDefaultLighting = false
        viewport.allowsCameraControl = true
        viewport.defaultCameraController.interactionMode = .orbitTurntable
        viewport.defaultCameraController.inertiaEnabled = true
        // A display stand is explored from above its floor, like a real tabletop.
        viewport.defaultCameraController.minimumVerticalAngle = 0
        viewport.defaultCameraController.maximumVerticalAngle = 75
        viewport.accessibilityIdentifier = "model"
        viewport.accessibilityLabel = "Interactive 3D model. Drag to rotate. Pinch to zoom."
        // The stage cross-dissolves in behind the loading state, so it starts clear.
        viewport.alpha = 0
        addSubview(viewport)

        // A passive observer alongside SceneKit's own camera gestures: it never
        // swallows a touch, it only tells us a finger has arrived so the idle
        // motion can get out of the way before it fights the orbit.
        let probe = UILongPressGestureRecognizer(target: self, action: #selector(handleTouchProbe(_:)))
        probe.minimumPressDuration = 0
        probe.cancelsTouchesInView = false
        probe.delaysTouchesBegan = false
        probe.delaysTouchesEnded = false
        probe.delegate = self
        viewport.addGestureRecognizer(probe)

        configureZoomControls()

        loadingHost.isUserInteractionEnabled = false
        addSubview(loadingHost)
        for layer in [arcTrack, arcStroke] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineWidth = 3.5
            arcHost.layer.addSublayer(layer)
        }
        arcStroke.strokeEnd = 0.3
        loadingHost.addSubview(arcHost)
        spinner.isHidden = true
        loadingHost.addSubview(spinner)
        let base = UIFont.systemFont(ofSize: 13.5, weight: .medium)
        status.font = UIFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 13.5)
        status.textColor = UIColor(white: 0.78, alpha: 1)
        status.textAlignment = .center
        status.numberOfLines = 0
        status.isUserInteractionEnabled = false
        loadingHost.addSubview(status)
        applyIndicatorTint()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        viewport.frame = bounds
        let dockWidth = min(220, max(0, bounds.width - 32))
        zoomDock.frame = CGRect(x: (bounds.width - dockWidth) / 2,
            y: max(0, bounds.height - safeAreaInsets.bottom - 72), width: dockWidth, height: 56)
        loadingHost.frame = bounds
        let diameter: CGFloat = 46
        arcHost.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        arcHost.center = CGPoint(x: bounds.midX, y: bounds.midY - 22)
        let inset = arcStroke.lineWidth / 2
        let path = UIBezierPath(ovalIn: CGRect(x: inset, y: inset, width: diameter - inset * 2, height: diameter - inset * 2)).cgPath
        for layer in [arcTrack, arcStroke] {
            layer.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.path = path
        }
        spinner.center = arcHost.center
        status.frame = CGRect(x: 24, y: bounds.midY + 14, width: max(0, bounds.width - 48), height: 62)
        if viewport.scene != nil, bounds.width > 0, bounds.height > 0, framedSize != bounds.size {
            resetCamera()
        }
        if pendingArrival, bounds.width > 0, bounds.height > 0 {
            pendingArrival = false
            arrive()
        }
    }

    fileprivate func cancel() {
        loadID = UUID()
        download?.cancel()
        stopArc()
        viewport.isPlaying = false
        if let cachedFile { try? FileManager.default.removeItem(at: cachedFile) }
        cachedFile = nil
    }

    fileprivate func load(_ url: URL) {
        cancel()
        sourceURL = url
        let currentID = loadID
        viewport.scene = nil
        viewport.alpha = 0
        originalMaterials.removeAll()
        retainedAsset = nil
        pendingArrival = false
        handled = false
        beginLoading()
        statusMessage = "Loading your 3D asset…"
        if url.isFileURL {
            importModel(url, id: currentID)
            return
        }
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            fail("This model URL is not supported.", id: currentID)
            return
        }
        Task { @MainActor [weak self] in
        guard let self else { return }
        do {
        let request = try await CraftCloudMedia.request(url)
        guard self.loadID == currentID else { return }
        download = URLSession.shared.downloadTask(with: request) { [weak self] temporary, response, error in
            guard let self else { return }
            guard error == nil, let temporary,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                DispatchQueue.main.async { self.fail("Couldn’t download this model. Check your connection and reopen it.", id: currentID) }
                return
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("craft-\(UUID().uuidString).glb")
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
                DispatchQueue.main.async {
                    guard self.loadID == currentID else { try? FileManager.default.removeItem(at: destination); return }
                    self.cachedFile = destination
                    self.importModel(destination, id: currentID)
                }
            } catch {
                DispatchQueue.main.async { self.fail("Couldn’t save the model for preview.", id: currentID) }
            }
        }
        download?.resume()
        } catch { self.fail("Couldn’t download this model. Check your connection and reopen it.", id: currentID) }
        }
    }

    private func importModel(_ url: URL, id: UUID) {
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, state, asset, error, stop in
            guard let self else { stop.pointee = true; return }
            DispatchQueue.main.async {
                guard self.loadID == id else { return }
                if state == .complete, let asset {
                    self.retainedAsset = asset
                    self.show(asset, id: id)
                } else if error != nil {
                    self.fail("This model could not be opened. Try another GLB asset.", id: id)
                }
            }
        }
    }

    private func fail(_ message: String, id: UUID) {
        guard loadID == id else { return }
        stopArc()
        arcHost.isHidden = true
        spinner.stopAnimating()
        spinner.isHidden = true
        loadingHost.alpha = 1
        statusMessage = message
    }

    private func show(_ asset: GLTFAsset, id: UUID) {
        let source = GLTFSCNSceneSource(asset: asset)
        guard let imported = source.defaultScene else {
            fail("No renderable scene was found in this asset.", id: id)
            return
        }
        let content = SCNNode()
        for child in imported.rootNode.childNodes { content.addChildNode(child) }
        let (low, high) = content.boundingBox
        let extent = max(high.x - low.x, max(high.y - low.y, high.z - low.z))
        guard extent.isFinite, extent > 0.00001 else {
            fail("The model has no visible geometry.", id: id)
            return
        }
        let scale = 2.0 / extent
        modelSize = SIMD3(high.x - low.x, high.y - low.y, high.z - low.z) * scale
        content.scale = SCNVector3(scale, scale, scale)
        content.position = SCNVector3(-(low.x + high.x) * scale / 2, -low.y * scale, -(low.z + high.z) * scale / 2)
        model = SCNNode()
        model.addChildNode(content)
        // A slight turn reveals depth without moving limbs or altering geometry.
        let yaw: Float = 0.28
        baseYaw = yaw
        model.eulerAngles.y = yaw
        modelSize = SIMD3(modelSize.x * cos(yaw) + modelSize.z * sin(yaw), modelSize.y,
                         modelSize.z * cos(yaw) + modelSize.x * sin(yaw))
        var linearTextures: [ObjectIdentifier: MTLTexture] = [:]
        let textureLoader = (viewport.device ?? MTLCreateSystemDefaultDevice()).map(MTKTextureLoader.init(device:))
        content.enumerateChildNodes { node, _ in
            node.camera = nil
            node.light = nil
            if let geometry = node.geometry?.copy() as? SCNGeometry {
                node.geometry = geometry
                for material in geometry.materials {
                    // glTF normal, occlusion and metallic/roughness channels are linear
                    // data, even when their PNG carries an sRGB ICC tag. Supplying an
                    // explicit non-sRGB Metal texture avoids image color conversion
                    // changing roughness/normal values inside SceneKit. All UVs,
                    // channel masks, factors and original pixel values remain intact.
                    if let textureLoader {
                        for property in [material.normal, material.metalness, material.roughness, material.ambientOcclusion] {
                            guard let value = property.contents as AnyObject?, CFGetTypeID(value) == CGImage.typeID else { continue }
                            let image = value as! CGImage
                            let key = ObjectIdentifier(image)
                            if let cached = linearTextures[key] {
                                property.contents = cached
                            } else if let texture = try? textureLoader.newTexture(cgImage: image, options: [
                                .SRGB: false, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.topLeft
                            ]) {
                                linearTextures[key] = texture
                                property.contents = texture
                            }
                        }
                    }
                }
                self.originalMaterials.append((geometry, geometry.materials))
            }
        }
        let scene = SCNScene()
        scene.rootNode.addChildNode(model)
        // One physical stage shares the model's ground plane, camera and depth buffer.
        // The normalized model's lowest point is y = 0, exactly the plinth top.
        let stage = CraftDisplayStage.make(size: modelSize)
        stageMaterial = stage.childNode(withName: "plinth", recursively: false)?.geometry?.firstMaterial
        stageRimMaterial = stage.childNode(withName: "rim", recursively: false)?.geometry?.firstMaterial
        scene.rootNode.addChildNode(stage)
        keyLight = makeLight(.directional, at: SCNVector3(4, 6, 4), in: scene)
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowMode = .forward
        // 1024 is indistinguishable on a single character at these shadow
        // softnesses, and the map is re-rendered on every frame the idle sway
        // is alive — this is the frame budget that pays for the stage being alive.
        keyLight.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        keyLight.light?.shadowSampleCount = 8
        keyLight.light?.shadowRadius = 6
        keyLight.light?.shadowBias = 0.02
        keyLight.light?.orthographicScale = 3.2
        keyLight.light?.zNear = 0.1
        keyLight.light?.zFar = 20
        rimLight = makeLight(.directional, at: SCNVector3(-5, 2, -3), in: scene)
        fillLight = makeLight(.directional, at: SCNVector3(-4, 3, 5), in: scene)
        backLight = makeLight(.directional, at: SCNVector3(3, 2, -5), in: scene)
        bounceLight = makeLight(.directional, at: SCNVector3(0, -4, 1), in: scene)
        ambientLight = makeLight(.ambient, at: SCNVector3Zero, in: scene)
        camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 20
        camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 100
        // Tone-map highlights before the SDR display output; fixed exposure prevents
        // orbiting against the dark backdrop from pumping the model brightness.
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = -0.25
        camera.camera?.bloomIntensity = 0
        scene.rootNode.addChildNode(camera)
        viewport.scene = scene
        appliedEnvironmentPreset = nil
        appliedStageKey = nil
        applyLighting()
        resetCamera()
        applyMode()
        arrive()
    }

    private func makeLight(_ type: SCNLight.LightType, at position: SCNVector3, in scene: SCNScene) -> SCNNode {
        let node = SCNNode()
        node.light = SCNLight()
        node.light?.type = type
        node.position = position
        if type != .ambient { node.look(at: SCNVector3(0, 0.8, 0)) }
        scene.rootNode.addChildNode(node)
        return node
    }

    // MARK: - Arrival

    /// The character is set down on the podium while the camera settles in — a
    /// pure dolly, so the composition never swings. Reduce Motion goes straight
    /// to the settled frame; the loading state still cross-dissolves, because an
    /// opacity cross-fade is the sanctioned Reduce Motion substitute.
    private func arrive() {
        guard bounds.width > 0, bounds.height > 0 else {
            // No frame yet, so there is no framing to dolly through. `layoutSubviews`
            // picks this back up the moment the view has a size.
            pendingArrival = true
            return
        }
        finishLoading()
        handled = false
        guard !reduceMotion else {
            model.removeAllActions()
            model.position = SCNVector3Zero
            model.scale = SCNVector3(1, 1, 1)
            viewport.alpha = 1
            startIdle()
            boostRendering(0.2)
            return
        }
        let frame = CraftCameraFraming.fit(size: modelSize, aspect: Float(bounds.width / bounds.height))
        let settled = CraftCameraFraming.eye(frame)
        let entry = CraftCameraFraming.eye(CraftCameraFraming.entrance(frame))
        camera.position = SCNVector3(entry.x, entry.y, entry.z)
        let dolly = SCNAction.move(to: SCNVector3(settled.x, settled.y, settled.z), duration: 0.82)
        dolly.timingMode = .easeOut
        camera.runAction(dolly, forKey: "arrival")

        model.removeAllActions()
        model.position = SCNVector3Zero
        model.scale = SCNVector3(0.962, 0.962, 0.962)
        let settle = SCNAction.group([SCNAction.move(to: SCNVector3Zero, duration: 0.72),
                                      SCNAction.scale(to: 1, duration: 0.72)])
        settle.timingMode = .easeOut
        model.runAction(settle, forKey: "arrival") { [weak self] in
            DispatchQueue.main.async { self?.startIdle() }
        }
        viewport.alpha = 0
        UIView.animate(withDuration: 0.46, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.viewport.alpha = 1
        }
        boostRendering(1.05)
    }

    // MARK: - Lighting and stage surface

    fileprivate func setLighting(_ preset: CraftLightingPreset, directional: Double, environment: Double, exposure: Double) {
        let direct = directional.isFinite ? min(3, max(0, directional)) : 1
        let ambient = environment.isFinite ? min(3, max(0, environment)) : 1
        let exp = exposure.isFinite ? min(3, max(0.05, exposure)) : 1
        guard preset != lightingPreset || direct != directionalTrim || ambient != environmentTrim || exp != exposureTrim else { return }
        lightingPreset = preset
        directionalTrim = direct
        environmentTrim = ambient
        exposureTrim = exp
        applyLighting(animated: true)
    }

    fileprivate func setStageAppearance(_ appearance: CraftAppearance?) {
        guard stageAppearance != appearance else { return }
        stageAppearance = appearance
        applyIndicatorTint()
        updateZoomControlAppearance()
        applyLighting(animated: true)
    }

    private func applyLighting(animated: Bool = false) {
        let rig = CraftLightRig.preset(lightingPreset)
        let backdrop: UIColor = stageAppearance == nil ? rig.background : .clear
        backgroundColor = backdrop
        viewport.backgroundColor = backdrop
        guard let scene = viewport.scene else { return }
        let dissolves = animated && !reduceMotion
        if dissolves {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.28
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        // Adjust the existing rig. Camera position, model and texture state are retained.
        keyLight.light?.intensity = rig.key * directionalTrim
        keyLight.light?.color = rig.keyColor
        let soft = stageAppearance != nil && lightingPreset == .studio
        keyLight.light?.shadowColor = UIColor.black.withAlphaComponent(soft ? 0.20 : lightingPreset == .flat ? 0.22 : 0.52)
        keyLight.light?.shadowRadius = soft ? 12 : 6
        rimLight.light?.intensity = rig.rim * directionalTrim
        rimLight.light?.color = rig.rimColor
        fillLight.light?.intensity = rig.key * (soft ? 0.7 : 0.35) * directionalTrim
        fillLight.light?.color = rig.keyColor
        // Broad neutral fills reveal backs and undersides without baking light into
        // the texture. They remain responsive to the user's lighting controls.
        backLight.light?.intensity = (lightingPreset == .studio ? 420 : rig.rim * 0.65) * directionalTrim
        backLight.light?.color = rig.keyColor
        bounceLight.light?.intensity = (lightingPreset == .studio ? 240 : rig.ambient) * environmentTrim
        bounceLight.light?.color = UIColor.white
        ambientLight.light?.intensity = max(rig.ambient, lightingPreset == .studio ? 280 : 0) * environmentTrim
        ambientLight.light?.color = rig.softbox
        scene.lightingEnvironment.intensity = rig.environment * environmentTrim
        let ev = rig.exposure + CGFloat(log2(exposureTrim))
        camera.camera?.exposureOffset = ev
        // SceneKit may make an orbit camera after gestures; update its exposure too.
        viewport.pointOfView?.camera?.exposureOffset = ev
        if dissolves { SCNTransaction.commit() }
        scene.background.contents = backdrop
        // Cached broad softboxes add neutral wrap and PBR reflections without a CDN.
        if appliedEnvironmentPreset != lightingPreset {
            scene.lightingEnvironment.contents = Self.softboxEnvironment(for: lightingPreset)
            appliedEnvironmentPreset = lightingPreset
        }
        let stageKey = stageAppearance.map { "lit-" + $0.rawValue } ?? "dark"
        if appliedStageKey != stageKey {
            stageMaterial?.diffuse.contents = stageAppearance == nil ? rig.floor : UIColor(white: 0.94, alpha: 1)
            stageMaterial?.emission.contents = UIColor(white: 0.09, alpha: 1)
            let accent = stageAppearance.map { UIColor($0.fill) } ?? rig.rimColor
            stageRimMaterial?.diffuse.contents = accent
            stageRimMaterial?.emission.contents = accent.withAlphaComponent(0.35)
            appliedStageKey = stageKey
        }
        if dissolves { boostRendering(0.45) } else { viewport.setNeedsDisplay() }
    }

    private static func softboxEnvironment(for preset: CraftLightingPreset) -> [UIImage] {
        if let cached = environmentCache[preset] { return cached }
        let rig = CraftLightRig.preset(preset)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let size = CGSize(width: 128, height: 128)
        // SceneKit cube order: +X, -X, +Y, -Y, +Z, -Z. Side/front/back
        // panels are symmetric, so rotating the asset does not shift exposure.
        let faces = (0..<6).map { index in
            UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                let cg = renderer.cgContext
                UIColor(white: 0.34, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
                let color = index == 3 ? rig.floor : rig.softbox
                let strength: CGFloat = index == 2 ? 1 : index == 3 ? 0.42 : 0.75
                // Feathered rectangular studio panels, not a point-source hotspot.
                for inset in stride(from: CGFloat(0), through: 24, by: 2) {
                    let alpha = strength * (0.09 + inset / 450)
                    color.withAlphaComponent(alpha).setFill()
                    cg.fill(CGRect(x: 8 + inset, y: 3 + inset, width: 112 - inset * 2, height: 122 - inset * 2))
                }
            }
        }
        environmentCache[preset] = faces
        return faces
    }

    // MARK: - Camera

    private func configureZoomControls() {
        zoomDock.layer.cornerRadius = 28
        zoomDock.clipsToBounds = true
        zoomDock.isHidden = true
        let controls = UIStackView(arrangedSubviews: [zoomOutButton, zoomResetButton, zoomInButton])
        controls.axis = .horizontal
        controls.distribution = .fillEqually
        controls.translatesAutoresizingMaskIntoConstraints = false
        zoomDock.contentView.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: zoomDock.contentView.leadingAnchor, constant: 4),
            controls.trailingAnchor.constraint(equalTo: zoomDock.contentView.trailingAnchor, constant: -4),
            controls.topAnchor.constraint(equalTo: zoomDock.contentView.topAnchor, constant: 4),
            controls.bottomAnchor.constraint(equalTo: zoomDock.contentView.bottomAnchor, constant: -4)
        ])
        let symbols = ["minus.magnifyingglass", "arrow.counterclockwise", "plus.magnifyingglass"]
        for (button, symbol) in zip([zoomOutButton, zoomResetButton, zoomInButton], symbols) {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)), for: .normal)
            button.accessibilityTraits = .button
        }
        zoomOutButton.accessibilityIdentifier = "model.zoomOut"
        zoomResetButton.accessibilityIdentifier = "model.resetZoom"
        zoomInButton.accessibilityIdentifier = "model.zoomIn"
        zoomOutButton.addTarget(self, action: #selector(zoomOut), for: .touchUpInside)
        zoomResetButton.addTarget(self, action: #selector(resetZoom), for: .touchUpInside)
        zoomInButton.addTarget(self, action: #selector(zoomIn), for: .touchUpInside)
        addSubview(zoomDock)
        updateZoomControlAppearance()
    }

    fileprivate func setZoomControlsVisible(_ visible: Bool) {
        guard zoomControlsVisible != visible else { return }
        zoomControlsVisible = visible
        zoomDock.isHidden = !visible
        bringSubviewToFront(zoomDock)
        setNeedsLayout()
    }

    private func updateZoomControlAppearance() {
        zoomDock.tintColor = stageAppearance.map { UIColor($0.ink) } ?? .label
        zoomOutButton.accessibilityLabel = chinese ? "缩小模型" : "Zoom out"
        zoomInButton.accessibilityLabel = chinese ? "放大模型" : "Zoom in"
        zoomResetButton.accessibilityLabel = chinese ? "重置缩放与视角" : "Reset zoom and view"
    }

    @objc private func zoomIn() { changeOpticalZoom(by: 1.25) }
    @objc private func zoomOut() { changeOpticalZoom(by: 0.8) }
    @objc private func resetZoom() { resetCamera(animated: true) }

    private func changeOpticalZoom(by factor: CGFloat) {
        guard viewport.scene != nil,
              let live = viewport.pointOfView, let lens = live.camera else { return }
        stopIdle()
        viewport.defaultCameraController.stopInertia()
        // Changing the lens magnifies the current detail without dollying
        // through geometry or changing the orbit target. Keep both camera
        // copies in sync when SceneKit has created its own orbit camera.
        let current = lens.fieldOfView
        guard current.isFinite else { return }
        let next = min(50, max(3, current / factor))
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        lens.fieldOfView = next
        camera.camera?.fieldOfView = next
        SCNTransaction.commit()
        boostRendering(0.2)
    }

    fileprivate func resetCamera(animated: Bool = false) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        framedSize = bounds.size
        // Fit the actual model AND plinth to both viewport axes. A fixed camera
        // distance crops tall characters in the wide home preview.
        let frame = CraftCameraFraming.fit(size: modelSize, aspect: Float(bounds.width / bounds.height))
        let eye = CraftCameraFraming.eye(frame)
        let settled = SCNVector3(eye.x, eye.y, eye.z)
        let target = SCNVector3(0, frame.targetY, 0)
        // Freeze the displayed pose before cancelling actions/inertia. The orbit
        // camera can be a different node and must be read in world coordinates.
        let live = viewport.pointOfView ?? camera
        let start = live.presentation.simdWorldPosition
        viewport.defaultCameraController.stopInertia()
        camera.camera?.fieldOfView = 20
        camera.removeAction(forKey: "arrival")
        viewport.allowsCameraControl = false
        viewport.pointOfView = camera
        viewport.defaultCameraController.pointOfView = camera
        viewport.defaultCameraController.automaticTarget = false
        viewport.defaultCameraController.target = target
        if animated && !reduceMotion {
            camera.simdPosition = CraftCameraFraming.returnEye(from: start, to: frame, fraction: 0)
            camera.look(at: target)
            let orbit = SCNAction.customAction(duration: 0.65) { node, elapsed in
                node.simdPosition = CraftCameraFraming.returnEye(from: start, to: frame, fraction: Float(elapsed / 0.65))
                node.look(at: target)
            }
            camera.runAction(orbit, forKey: "arrival") { [weak self] in
                DispatchQueue.main.async { self?.viewport.allowsCameraControl = true }
            }
        } else {
            camera.position = settled
            camera.look(at: target)
            viewport.allowsCameraControl = true
        }
        // A reset puts the character back on its mark too, and hands it back its life.
        if animated { restorePose(animated: !reduceMotion) }
        boostRendering(animated ? 0.85 : 0.1)
    }

    private func restorePose(animated: Bool) {
        model.removeAllActions()
        handled = false
        guard animated else {
            model.position = SCNVector3Zero
            model.scale = SCNVector3(1, 1, 1)
            model.eulerAngles = SCNVector3(0, baseYaw, 0)
            startIdle()
            return
        }
        let home = SCNAction.group([
            SCNAction.move(to: SCNVector3Zero, duration: 0.55),
            SCNAction.scale(to: 1, duration: 0.55),
            SCNAction.rotateTo(x: 0, y: CGFloat(baseYaw), z: 0, duration: 0.55, usesShortestUnitArc: true)
        ])
        home.timingMode = .easeInEaseOut
        model.runAction(home, forKey: "home") { [weak self] in
            DispatchQueue.main.async { self?.startIdle() }
        }
    }

    // MARK: - Display mode

    fileprivate func setMode(_ mode: String) {
        guard selectedMode != mode.lowercased() else { return }
        selectedMode = mode.lowercased()
        guard viewport.scene != nil, !originalMaterials.isEmpty else { applyMode(); return }
        // Material / Solid / Wire never snaps. The stage dissolves out, the
        // materials swap in the dark, the stage dissolves back — opacity only,
        // so it is equally correct under Reduce Motion.
        boostRendering(0.8)
        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.viewport.alpha = 0
        } completion: { _ in
            self.applyMode()
            self.viewport.setNeedsDisplay()
            UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.viewport.alpha = 1
            }
        }
    }

    private func applyMode() {
        for (geometry, materials) in originalMaterials {
            if selectedMode == "solid" || selectedMode == "wire" || selectedMode == "wireframe" {
                geometry.materials = materials.map { _ in
                    let material = SCNMaterial()
                    material.diffuse.contents = UIColor(white: 0.77, alpha: 1)
                    material.roughness.contents = 0.85
                    material.fillMode = selectedMode == "solid" ? .fill : .lines
                    material.isDoubleSided = true
                    return material
                }
            } else { geometry.materials = materials }
        }
    }

    // MARK: - Loading state

    private func beginLoading() {
        loadingHost.alpha = 1
        if reduceMotion {
            arcHost.isHidden = true
            stopArc()
            spinner.isHidden = false
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
            spinner.isHidden = true
            arcHost.isHidden = false
            startArc()
        }
    }

    private func finishLoading() {
        guard loadingHost.alpha > 0 else { return }
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.loadingHost.alpha = 0
        } completion: { _ in
            self.stopArc()
            self.spinner.stopAnimating()
        }
        statusMessage = nil
    }

    /// A trimmed accent arc turning inside its own track, on the same 1.6 s
    /// linear period the generation journey's active node uses — the app has one
    /// idea of what "working" looks like. Under Reduce Motion this is swapped for
    /// the platform's own indicator rather than being removed, because a load
    /// still has to say that it is loading.
    private func startArc() {
        guard arcStroke.animation(forKey: "spin") == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = 1.6
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        arcStroke.add(spin, forKey: "spin")
        let breath = CABasicAnimation(keyPath: "strokeEnd")
        breath.fromValue = 0.16
        breath.toValue = 0.46
        breath.duration = 0.95
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        arcStroke.add(breath, forKey: "breath")
    }

    private func stopArc() { arcStroke.removeAllAnimations() }

    private func applyIndicatorTint() {
        let accent = stageAppearance.map { UIColor($0.deep) } ?? UIColor(white: 0.80, alpha: 1)
        arcStroke.strokeColor = accent.cgColor
        arcTrack.strokeColor = accent.withAlphaComponent(0.16).cgColor
        spinner.color = stageAppearance.map { UIColor($0.ink) } ?? .lightGray
        status.textColor = stageAppearance == nil ? .lightGray : UIColor(white: 0.42, alpha: 1)
    }

    // MARK: - Language and status copy

    fileprivate func setLanguage(chinese: Bool) {
        self.chinese = chinese
        updateZoomControlAppearance()
        viewport.accessibilityLabel = chinese ? "可交互的 3D 模型。拖动旋转，双指缩放。" : "Interactive 3D model. Drag to rotate. Pinch to zoom."
        updateStatus()
    }

    fileprivate func setReduceMotion(_ value: Bool) {
        guard reduceMotion != value else { return }
        reduceMotion = value
        if loadingHost.alpha > 0, statusMessage == "Loading your 3D asset…" { beginLoading() }
        if value {
            model.removeAction(forKey: "sway")
            model.removeAction(forKey: "bob")
            model.removeAction(forKey: "turntable")
            settleRenderLoop()
        } else {
            startIdle()
        }
    }

    private func updateStatus() {
        guard let message = statusMessage else { status.text = nil; return }
        let translations: [String: String] = [
            "Loading your 3D asset…": "正在载入你的 3D 资产…",
            "This model URL is not supported.": "不支持此模型链接。",
            "Couldn’t download this model. Check your connection and reopen it.": "无法下载此模型。请检查连接，然后重新打开。",
            "Couldn’t save the model for preview.": "无法保存模型用于预览。",
            "This model could not be opened. Try another GLB asset.": "无法打开此模型，请尝试其他 GLB 资产。",
            "No renderable scene was found in this asset.": "此资产没有可显示的 3D 场景。",
            "The model has no visible geometry.": "此模型没有可显示的几何体。"
        ]
        status.text = chinese ? (translations[message] ?? message) : message
    }

    // MARK: - Idle life

    fileprivate func setIdle(turntable: Bool, sway: Bool) {
        guard turntables != turntable || sways != sway else { return }
        turntables = turntable
        sways = sway
        startIdle()
    }

    /// A very slow turn, or — by default — a grounded breathing turn of a few degrees. Never both. Never while a finger
    /// is down. Never under Reduce Motion, Low Power Mode or an inactive scene:
    /// `ModelViewport` folds all three into the flags before they arrive here.
    private func startIdle() {
        model.removeAction(forKey: "turntable")
        model.removeAction(forKey: "sway")
        model.removeAction(forKey: "bob")
        guard viewport.scene != nil, !handled, !reduceMotion else { settleRenderLoop(); return }
        if turntables {
            model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 30)), forKey: "turntable")
        } else if sways {
            let out = SCNAction.rotateBy(x: 0, y: 0.085, z: 0, duration: 4.6)
            out.timingMode = .easeInEaseOut
            let back = SCNAction.rotateBy(x: 0, y: -0.085, z: 0, duration: 4.6)
            back.timingMode = .easeInEaseOut
            model.runAction(.repeatForever(.sequence([out, back])), forKey: "sway")
            // A grounded turn carries life without lifting the feet off the stage.

        }
        settleRenderLoop()
    }

    /// The idle life ends the moment the stage is touched, so it can never drag
    /// against the orbit gesture. A reset gives it back.
    private func stopIdle() {
        guard !handled else { return }
        handled = true
        model.removeAction(forKey: "turntable")
        model.removeAction(forKey: "sway")
        model.removeAction(forKey: "bob")
        camera.removeAction(forKey: "arrival")
        viewport.allowsCameraControl = true
    }

    @objc private func handleTouchProbe(_ recognizer: UIGestureRecognizer) {
        switch recognizer.state {
        case .began:
            stopIdle()
            interacting = true
            renderBoost += 1
            viewport.preferredFramesPerSecond = 60
            viewport.isPlaying = true
        case .ended, .cancelled, .failed:
            interacting = false
            // Long enough to carry SceneKit's orbit inertia to a stop.
            boostRendering(1.4)
        default: break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - Render loop

    /// The renderer runs at full rate for a beat, then falls back to whatever the
    /// stage actually needs: 30 fps while something drifts, nothing at all when
    /// the scene is at rest.
    private func boostRendering(_ seconds: Double) {
        renderBoost += 1
        let token = renderBoost
        viewport.preferredFramesPerSecond = 60
        viewport.isPlaying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.renderBoost == token else { return }
            self.settleRenderLoop()
        }
    }

    private func settleRenderLoop() {
        guard !interacting else { return }
        let drifting = model.hasActions || camera.hasActions
        viewport.preferredFramesPerSecond = drifting ? 30 : 60
        viewport.isPlaying = drifting
        if !drifting { viewport.setNeedsDisplay() }
    }
}
