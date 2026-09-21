import SwiftUI
import AVFoundation

/// The 5-step immersive onboarding and introduction flow for 3D Craft.
///
/// Direct Apple-aesthetic adaptation of the MonAi showcase:
/// - OLED dark ambient backdrop with radial glow
/// - Bold typography with glowing gradient keywords
/// - Dynamic interactive cards (Prompt -> Concept -> 3D Mesh Turntable -> AI Video Loop -> 3D Games)
/// - Floating capsule indicator (`• Step N • •`)
/// - Full-width radiant CTA button with haptics
struct CraftIntroductionView: View {
    var onFinish: () -> Void
    @AppStorage(CraftAppearance.storageKey) private var appearance: CraftAppearance = .lavender
    @AppStorage("craftChinese") private var isChinese: Bool = (Locale.current.language.languageCode?.identifier == "zh")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var currentStep: Int = 0
    @State private var dragOffset: CGFloat = 0
    
    // Step 1: Concept State
    @State private var promptTypedText: String = ""
    @State private var showConceptCard: Bool = false
    @State private var typewriterTimer: Timer? = nil
    
    // Step 2: 3D Turntable State
    @State private var modelMode: String = "Material"
    
    // Step 3: Animation State
    @State private var animationLooping: Bool = true
    
    // Step 4: Game Showcase State
    @State private var selectedGameIndex: Int = 0
    
    private let totalSteps = 5
    
    // Glowing gradient matching MonAi's signature warm/coral radiance
    private var warmGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.48, blue: 0.28), Color(red: 1.0, green: 0.32, blue: 0.36)],
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
    
    var body: some View {
        ZStack {
            // Deep OLED black background with subtle ambient radial glow
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
            
            // Ambient soft lighting aura behind the center card
            ambientAura
            
            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                
                // Step header: Bold headline with gradient focus keyword + subtitle
                stepHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                
                // Main Interactive Visual Stage
                GeometryReader { geo in
                    ZStack {
                        switch currentStep {
                        case 0:
                            step1ConceptCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 1.04))
                                ))
                        case 1:
                            step2ModelCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 1.04))
                                ))
                        case 2:
                            step3AnimationCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 1.04))
                                ))
                        case 3:
                            step4GameCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 1.04))
                                ))
                        default:
                            step5WelcomeCard
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                    removal: .opacity.combined(with: .scale(scale: 1.04))
                                ))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dragOffset = value.translation.width * 0.6
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 50
                                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                    if value.translation.width < -threshold, currentStep < totalSteps - 1 {
                                        nextStep()
                                    } else if value.translation.width > threshold, currentStep > 0 {
                                        previousStep()
                                    }
                                    dragOffset = 0
                                }
                            }
                    )
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 12)
                
                // Floating Step Capsule Indicator
                floatingPillIndicator
                    .padding(.bottom, 12)
                
                // Bottom Radiant Action Button
                bottomActionButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            startStep1Animation()
        }
        .onChange(of: currentStep) { _, newStep in
            triggerHaptic()
            if newStep == 0 {
                startStep1Animation()
            }
        }
    }
    
    // MARK: - Ambient Aura
    
    private var ambientAura: some View {
        Circle()
            .fill(currentStep == 1 ? Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.18)
                  : currentStep == 2 ? Color(red: 0.6, green: 0.2, blue: 0.8).opacity(0.18)
                  : Color(red: 1.0, green: 0.4, blue: 0.2).opacity(0.18))
            .blur(radius: 80)
            .frame(width: 320, height: 320)
            .offset(y: -40)
            .animation(.easeInOut(duration: 0.8), value: currentStep)
            .allowsHitTesting(false)
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            // App Brand Pill
            HStack(spacing: 6) {
                Image(systemName: "cube.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(warmGradient)
                Text("3D Craft")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: Capsule())
            
            Spacer()
            
            // Skip button
            Button {
                triggerHaptic()
                onFinish()
            } label: {
                Text(isChinese ? "跳过" : "Skip")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
            .buttonStyle(CraftPressStyle(scale: 0.94))
            .accessibilityLabel(isChinese ? "跳过介绍" : "Skip introduction")
        }
    }
    
    // MARK: - Step Header
    
    @ViewBuilder
    private var stepHeader: some View {
        VStack(spacing: 8) {
            switch currentStep {
            case 0:
                VStack(spacing: 4) {
                    if isChinese {
                        HStack(spacing: 0) {
                            Text("把你的奇思妙想，变为")
                            Text("专属概念图").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 0) {
                            Text("Turn any idea into a ")
                            Text("3D concept").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                    Text(isChinese ? "用一句话或一张参考图，3D Craft 瞬间生成多角度概念设计。" : "Speak or type your vision. 3D Craft crafts multi-angle concept art in seconds.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            case 1:
                VStack(spacing: 4) {
                    if isChinese {
                        HStack(spacing: 0) {
                            Text("一键重构为")
                            Text("高精 3D 模型").foregroundStyle(cyanGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 0) {
                            Text("Reconstruct into ")
                            Text("production 3D").foregroundStyle(cyanGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                    Text(isChinese ? "自动生成真实 PBR 材质与水密网格，指尖 360° 自由旋转把玩。" : "Watertight geometry and realistic PBR materials, ready for realtime inspection.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            case 2:
                VStack(spacing: 4) {
                    if isChinese {
                        HStack(spacing: 0) {
                            Text("为你的 3D 角色，赋予")
                            Text("专属循环动画").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 0) {
                            Text("Animate characters with ")
                            Text("AI video loops").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                    Text(isChinese ? "一键生成角色专属跳跃、跑步与待机循环动画，衣物与配饰自带真实物理摆动。" : "Generate dynamic jumping, running, and idle loops with realistic clothing physics.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            case 3:
                VStack(spacing: 4) {
                    if isChinese {
                        HStack(spacing: 0) {
                            Text("直接带入")
                            Text("3D 游戏试玩").foregroundStyle(cyanGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 0) {
                            Text("Play your creations in ")
                            Text("3D games").foregroundStyle(cyanGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                    Text(isChinese ? "无需繁琐手动骨骼绑定，带上你的模型直接进入竞技场与古镇冒险。" : "Zero rigging required. Jump directly into action games and racing tracks.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            default:
                VStack(spacing: 4) {
                    if isChinese {
                        HStack(spacing: 0) {
                            Text("开启旅程，赠送")
                            Text("初始创作 Token").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    } else {
                        HStack(spacing: 0) {
                            Text("Start creating with ")
                            Text("complimentary Tokens").foregroundStyle(warmGradient)
                        }
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    }
                    Text(isChinese ? "新用户专享初始创作礼遇，即刻生成你的专属 3D 模型与循环动画。" : "Everything you need to create your first 3D character and animated loops today.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    // MARK: - Step 1: Prompt & Concept Card (Full Bleed Grand Stage)
    
    private var step1ConceptCard: some View {
        ZStack(alignment: .top) {
            // Full-Bleed Grand Character Concept Render
            ZStack {
                // Studio backdrop color
                Color(red: 0.44, green: 0.45, blue: 0.48)
                
                if let imgUrl = Bundle.main.url(forResource: "lantern_cat_showcase", withExtension: "jpg") ?? Bundle.main.url(forResource: "lantern_cat", withExtension: "jpg"),
                   let uiImg = UIImage(contentsOfFile: imgUrl.path) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let fallback = UIImage(named: "PaywallExplorer") {
                    Image(uiImage: fallback)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 24, y: 12)
            
            // Overlaid Floating Controls (Top Prompt Glass Pill + Bottom Angle Badges)
            VStack(spacing: 0) {
                // Floating Typewriter Prompt Bar
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(warmGradient)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text(promptTypedText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 12, y: 5)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                
                Spacer()
                
                // Floating Angle Badges
                HStack(spacing: 8) {
                    angleTag(isChinese ? "正视 Front" : "Front")
                    angleTag(isChinese ? "45° 角" : "3/4 View")
                    angleTag(isChinese ? "侧视 Side" : "Side")
                }
                .padding(.bottom, 16)
                .opacity(showConceptCard ? 1 : 0)
                .scaleEffect(showConceptCard ? 1 : 0.94)
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: showConceptCard)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxHeight: .infinity)
    }
    
    private func angleTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
    }
    
    private func startStep1Animation() {
        promptTypedText = ""
        showConceptCard = false
        typewriterTimer?.invalidate()
        
        let fullText = isChinese
            ? "手提古风发光灯笼的勇敢冒险家小猫，铜质探险盔甲，站立拟人姿态……"
            : "A brave adventurer explorer cat holding a glowing lantern, brass armor..."
        
        var currentIndex = 0
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            if currentIndex < fullText.count {
                let index = fullText.index(fullText.startIndex, offsetBy: currentIndex)
                promptTypedText.append(fullText[index])
                currentIndex += 1
            } else {
                timer.invalidate()
                withAnimation {
                    showConceptCard = true
                }
            }
        }
    }
    
    // MARK: - Step 2: 3D Turntable Card
    
    private var step2ModelCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(cyanGradient.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.cyan.opacity(0.15), radius: 24, y: 12)
            
            VStack(spacing: 10) {
                // Interactive 3D Model Viewport - EXPANDED TO FILL FULL CARD!
                ZStack {
                    if let modelURL = Bundle.main.url(forResource: "lantern_cat", withExtension: "glb") {
                        ModelViewport(
                            modelURL: modelURL,
                            mode: modelMode,
                            autoRotate: true,
                            chinese: isChinese,
                            lighting: .studio,
                            softStage: true,
                            idleMotion: true
                        )
                    } else {
                        ProgressView()
                    }
                    
                    // Subtle touch hint
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 12))
                            Text(isChinese ? "可拖动 360° 旋转 · 双指缩放" : "Drag 360° to rotate · Pinch zoom")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                // Mode switcher: Material / Solid / Wire
                HStack(spacing: 8) {
                    modeButton(title: isChinese ? "真实材质" : "Material", modeKey: "Material")
                    modeButton(title: isChinese ? "实体光影" : "Solid", modeKey: "Solid")
                    modeButton(title: isChinese ? "精细线框" : "Wireframe", modeKey: "Wire")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxHeight: .infinity)
    }
    
    private func modeButton(title: String, modeKey: String) -> some View {
        let isSelected = modelMode.lowercased() == modeKey.lowercased()
        return Button {
            triggerHaptic()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                modelMode = modeKey
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(CraftPressStyle(scale: 0.96))
    }
    
    // MARK: - Step 3: AI Looping Video Card
    
    private var step3AnimationCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.purple.opacity(0.15), radius: 24, y: 12)
            
            VStack(spacing: 10) {
                // Looping Video Player - EXPANDED TO FILL FULL CARD!
                ZStack(alignment: .topTrailing) {
                    if let videoURL = Bundle.main.url(forResource: "lantern_cat_jump", withExtension: "mp4") ?? Bundle.main.url(forResource: "mascot-dragon-concept", withExtension: "mp4") {
                        CraftLoopingVideo(url: videoURL, playing: animationLooping)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else if let fallbackVideo = Bundle.main.url(forResource: "mascot-dragon-model", withExtension: "mp4") {
                        CraftLoopingVideo(url: fallbackVideo, playing: animationLooping)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        Image("PaywallDragon")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    
                    // 4s Loop Badge
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(isChinese ? "4 秒物理循环" : "4s Physics Loop")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                    .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                
                // Looping specs
                HStack(spacing: 10) {
                    specPill(icon: "figure.walk.motion", title: isChinese ? "跳跃动态与物理跟随" : "Dynamic Jump & Physics")
                    specPill(icon: "repeat", title: isChinese ? "首尾帧无缝循环" : "Seamless End-to-Start")
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxHeight: .infinity)
    }
    
    private func specPill(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(warmGradient)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Step 4: 3D Games Card
    
    private var step4GameCard: some View {
        let gameCovers = ["arena", "survivor", "race", "dragon"]
        let gameTitles = [
            ("Emberfront", isChinese ? "装甲竞技场" : "Armor Arena"),
            ("Lanternfall", isChinese ? "古镇求生" : "Lanternfall"),
            ("Coastline Rush", isChinese ? "日落海岸竞速" : "Coastline Racer"),
            ("Emerald Skies", isChinese ? "飞龙守护" : "Emerald Skies")
        ]
        
        return ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.orange.opacity(0.15), radius: 24, y: 12)
            
            VStack(spacing: 14) {
                // Game Preview Display (Native landscape 16:9 proportion, crisp & undistorted)
                ZStack(alignment: .bottomLeading) {
                    if let coverUrl = Bundle.main.url(forResource: gameCovers[selectedGameIndex], withExtension: "jpg"),
                       let coverImg = UIImage(contentsOfFile: coverUrl.path) {
                        Image(uiImage: coverImg)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 220)
                    }
                    
                    // Controller overlay banner
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(warmGradient)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gameTitles[selectedGameIndex].0)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            Text(gameTitles[selectedGameIndex].1)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                        Spacer()
                        Label(isChinese ? "即刻开玩" : "Ready to Play", systemImage: "play.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(warmGradient, in: Capsule())
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                    .padding(10)
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                
                // Game Cover Thumbnails
                HStack(spacing: 10) {
                    ForEach(0..<gameCovers.count, id: \.self) { idx in
                        Button {
                            triggerHaptic()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                selectedGameIndex = idx
                            }
                        } label: {
                            if let thumbUrl = Bundle.main.url(forResource: gameCovers[idx], withExtension: "jpg"),
                               let thumbImg = UIImage(contentsOfFile: thumbUrl.path) {
                                Image(uiImage: thumbImg)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(selectedGameIndex == idx ? Color(red: 1.0, green: 0.48, blue: 0.28) : Color.white.opacity(0.15), lineWidth: selectedGameIndex == idx ? 2.5 : 1)
                                    )
                            }
                        }
                        .buttonStyle(CraftPressStyle(scale: 0.94))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: 420)
    }
    
    // MARK: - Step 5: Creator Welcome Card
    
    private var step5WelcomeCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(warmGradient.opacity(0.4), lineWidth: 1)
                )
            
            VStack(spacing: 16) {
                // Free Starter Token Gift Banner
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(warmGradient)
                            .frame(width: 52, height: 52)
                        Image(systemName: "gift.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isChinese ? "赠送初始创作 Token" : "Complimentary Creator Tokens")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Text(isChinese ? "新用户无需等待，马上体验全套生成功能" : "Instant access to create 3D models & loops")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 18)
                
                Spacer(minLength: 4)
                
                // Feature list checklist
                VStack(spacing: 12) {
                    featureRow(icon: "sparkles", text: isChinese ? "AI 多角度概念图创作" : "Multi-angle AI Concept Art")
                    featureRow(icon: "cube.transparent", text: isChinese ? "高精 3D 网格与 PBR 材质重构" : "High-poly 3D Geometry & PBR Textures")
                    featureRow(icon: "video.fill", text: isChinese ? "4 秒无缝 AI 角色循环视频" : "4-Second Seamless AI Video Loops")
                    featureRow(icon: "gamecontroller.fill", text: isChinese ? "直接导入 3D 游戏试玩" : "Playable in Interactive 3D Games")
                }
                .padding(.horizontal, 16)
                
                Spacer(minLength: 8)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 440)
        .frame(maxHeight: .infinity)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(warmGradient)
            }
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Floating Capsule Step Indicator
    
    private var floatingPillIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                if index == currentStep {
                    Text(isChinese ? "第 \(index + 1) 步" : "Step \(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.20), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 6, height: 6)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentStep = index
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(red: 0.16, green: 0.16, blue: 0.20).opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: currentStep)
    }
    
    // MARK: - Bottom Radiant Action Button
    
    private var bottomActionButton: some View {
        Button {
            triggerHaptic()
            if currentStep < totalSteps - 1 {
                nextStep()
            } else {
                onFinish()
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentStep == totalSteps - 1
                     ? (isChinese ? "开始创作" : "Start Creating")
                     : (isChinese ? "继续" : "Continue"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Image(systemName: currentStep == totalSteps - 1 ? "sparkles" : "arrow.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(warmGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(red: 1.0, green: 0.35, blue: 0.25).opacity(0.38), radius: 14, y: 5)
        }
        .buttonStyle(CraftPressStyle(scale: 0.97))
        .accessibilityIdentifier("onboarding.continue")
    }
    
    // MARK: - Step Navigation
    
    private func nextStep() {
        if currentStep < totalSteps - 1 {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                currentStep += 1
            }
        }
    }
    
    private func previousStep() {
        if currentStep > 0 {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                currentStep -= 1
            }
        }
    }
    
    private func triggerHaptic() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()
        impact.impactOccurred()
    }
}
