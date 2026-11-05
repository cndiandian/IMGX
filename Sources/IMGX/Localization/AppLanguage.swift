import Foundation

enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"

    /// 与参考项目一致：按首选系统语言匹配，不支持时使用英语。
    static func resolve(preferredLanguages: [String]) -> AppLanguage {
        guard let identifier = preferredLanguages.first else { return .english }
        let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        switch parts.first {
        case "en": return .english
        case "ja": return .japanese
        case "zh":
            if parts.contains("hans") { return .simplifiedChinese }
            if parts.contains("hant") { return .traditionalChinese }
            if parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return .traditionalChinese }
            return .simplifiedChinese
        default: return .english
        }
    }

    static var systemPreferred: AppLanguage { resolve(preferredLanguages: Locale.preferredLanguages) }
}
