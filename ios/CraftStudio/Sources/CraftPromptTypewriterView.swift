import SwiftUI

/// A typewriter animation that rolls through creative character creation prompts.
/// Types out characters one by one, pauses so the user can read, fades out,
/// and cycles through 6 curated cases.
struct CraftPromptTypewriterView: View {
    let chinese: Bool
    var onSelect: ((String) -> Void)? = nil

    @State private var currentCaseIndex = 0
    @State private var displayedText = ""
    @State private var isBlinking = true
    @State private var animationTask: Task<Void, Never>?

    private static let casesChinese: [String] = [
        "身穿墨绿中式对襟马褂、腰间挂温润玉佩的小橘猫，摄影棚中性灰背景",
        "身披赤红熔岩轻甲、头顶黑曜石双角的小火龙，摄影棚中性灰背景",
        "身穿皮质飞行员夹克、头戴黄铜护目镜的探险家兔子，极简无缝纯白背景",
        "身穿机能战术风外套、手持能量光刃的赛博朋克浣熊，暗夜纯黑背景",
        "身披流光织锦长袍、手握水晶提灯的独角幼兽，摄影棚中性灰背景",
        "身穿高科技太空宇航服、头盔里游动金鱼的企鹅，摄影棚中性灰背景"
    ]

    private static let casesEnglish: [String] = [
        "Adventurous tabby cat wearing a dark teal silk tunic and jade pendant, neutral studio grey background",
        "Baby dragon clad in obsidian rock armor with glowing lava chest, neutral studio grey background",
        "Steampunk aviator bunny wearing a leather bomber jacket and brass goggles, seamless pure white background",
        "Cyberpunk raccoon in tactical techwear jacket wielding an energy blade, deep black studio backdrop",
        "Unicorn guardian in flowing embroidered robes holding a crystal lantern, neutral studio grey background",
        "Astronaut space penguin in a high-tech spacesuit with goldfish in helmet, neutral studio grey background"
    ]

    private var prompts: [String] {
        chinese ? Self.casesChinese : Self.casesEnglish
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(displayedText)
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Text("|")
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary.opacity(isBlinking ? 0.8 : 0.1))
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBlinking)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let prompt = prompts[currentCaseIndex % prompts.count]
            onSelect?(prompt)
        }
        .onAppear {
            isBlinking = true
            startTypingCycle()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func startTypingCycle() {
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                let currentPrompt = prompts[currentCaseIndex % prompts.count]
                displayedText = ""

                // 1. Type out character by character
                for character in currentPrompt {
                    if Task.isCancelled { return }
                    displayedText.append(character)
                    let delayMs: UInt64 = chinese ? 65 : 40
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                // 2. Pause so the user can read the complete character idea
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 3_500_000_000)

                // 3. Clear smoothly by deleting characters or quick transition
                while !displayedText.isEmpty {
                    if Task.isCancelled { return }
                    displayedText.removeLast()
                    let eraseMs: UInt64 = chinese ? 25 : 15
                    try? await Task.sleep(nanoseconds: eraseMs * 1_000_000)
                }

                // Short rest before the next case
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                currentCaseIndex = (currentCaseIndex + 1) % prompts.count
            }
        }
    }
}
