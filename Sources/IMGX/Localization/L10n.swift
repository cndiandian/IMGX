import Foundation

enum L10n {
    static let language = AppLanguage.systemPreferred
    static let translations: [AppLanguage: [L10nKey: String]] = [
        .english: EnglishTranslations.values,
        .simplifiedChinese: SimplifiedChineseTranslations.values,
        .traditionalChinese: TraditionalChineseTranslations.values,
        .japanese: JapaneseTranslations.values
    ]

    static func text(_ key: L10nKey, _ arguments: String..., language: AppLanguage = L10n.language) -> String {
        render(key, arguments: arguments, language: language)
    }

    static func render(_ key: L10nKey, arguments: [String], language: AppLanguage,
                       catalog: [AppLanguage: [L10nKey: String]] = translations) -> String {
        let template = catalog[language]?[key] ?? EnglishTranslations.values[key] ?? key.rawValue
        // 按原模板分段替换，不会把文件名中的占位符再次解释为格式指令。
        let parts = template.components(separatedBy: "%@")
        guard parts.count == arguments.count + 1 else { return template.replacingOccurrences(of: "%%", with: "%") }
        return parts.enumerated().map { index, part in
            (index == 0 ? "" : arguments[index - 1]) + part.replacingOccurrences(of: "%%", with: "%")
        }.joined()
    }
}
