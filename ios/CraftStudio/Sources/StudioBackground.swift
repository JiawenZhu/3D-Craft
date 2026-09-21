import SwiftUI

/// Supported studio backdrop environments for concept generation.
enum StudioBackground: String, CaseIterable, Identifiable {
    case grey, white, black
    var id: String { rawValue }

    func title(chinese: Bool) -> String {
        switch self {
        case .grey: return chinese ? "灰色背景（默认）" : "Studio Grey (Default)"
        case .white: return chinese ? "白色背景" : "Pure White"
        case .black: return chinese ? "黑色背景" : "Deep Black"
        }
    }

    func shortTitle(chinese: Bool) -> String {
        switch self {
        case .grey: return chinese ? "灰色背景" : "Grey"
        case .white: return chinese ? "白色背景" : "White"
        case .black: return chinese ? "黑色背景" : "Black"
        }
    }

    func promptPhrase(chinese: Bool) -> String {
        switch self {
        case .grey: return chinese ? "摄影棚中性灰背景" : "neutral solid studio grey background"
        case .white: return chinese ? "极简无缝纯白背景" : "seamless pure white studio background"
        case .black: return chinese ? "深黑摄影棚纯色背景" : "solid deep black studio backdrop"
        }
    }

    static func detect(in text: String) -> StudioBackground {
        let lower = text.lowercased()
        if lower.contains("white") || lower.contains("纯白") || lower.contains("白背景") {
            return .white
        }
        if lower.contains("black") || lower.contains("纯黑") || lower.contains("深黑") || lower.contains("黑背景") {
            return .black
        }
        return .grey
    }

    static func applying(_ bg: StudioBackground, to prompt: String, chinese: Bool) -> String {
        var trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return bg.promptPhrase(chinese: chinese) }

        let phrases = [
            "摄影棚中性灰背景", "摄影棚中性灰色背景", "中性灰背景", "灰色背景",
            "极简无缝纯白背景", "纯白无缝背景", "纯白背景", "白色背景",
            "深黑摄影棚纯色背景", "深黑摄影棚背景", "纯黑背景", "黑色背景",
            "neutral solid studio grey background", "neutral studio grey background", "studio grey background",
            "seamless pure white studio background", "pure white background", "white background",
            "solid deep black studio backdrop", "deep black background", "black background"
        ]
        for p in phrases {
            trimmed = trimmed.replacingOccurrences(of: "，" + p, with: "")
            trimmed = trimmed.replacingOccurrences(of: ", " + p, with: "")
            trimmed = trimmed.replacingOccurrences(of: p, with: "")
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let sep = chinese ? "，" : ", "
        return trimmed + sep + bg.promptPhrase(chinese: chinese)
    }
}
