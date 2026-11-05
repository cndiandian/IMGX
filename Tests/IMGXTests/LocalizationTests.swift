import Testing
import Foundation
@testable import IMGX

@Test func systemLanguageMatchingUsesPrimaryPreferenceAndEnglishFallback() {
    let cases: [([String], AppLanguage)] = [
        ([], .english), (["en-US"], .english), (["EN_gb"], .english),
        (["zh"], .simplifiedChinese), (["zh-CN"], .simplifiedChinese),
        (["zh-SG"], .simplifiedChinese), (["zh-Hans"], .simplifiedChinese),
        (["zh-Hans-TW"], .simplifiedChinese), (["zh-Hant-CN"], .traditionalChinese),
        (["zh-TW"], .traditionalChinese), (["zh-HK"], .traditionalChinese),
        (["zh_MO"], .traditionalChinese), (["zh-Hant-HK"], .traditionalChinese),
        (["ja"], .japanese), (["ja-JP"], .japanese),
        (["fr-FR", "zh-Hans"], .english), (["de-DE", "ja"], .english),
        (["ko-KR"], .english), ([""], .english), (["jargon"], .english)
    ]
    for (preferences, expected) in cases {
        #expect(AppLanguage.resolve(preferredLanguages: preferences) == expected)
    }
}

@Test func allLanguagesCoverEveryKeyWithMatchingPlaceholders() throws {
    let keys = Set(L10nKey.allCases)
    #expect(Set(L10n.translations.keys) == Set(AppLanguage.allCases))
    for language in AppLanguage.allCases {
        let values = try #require(L10n.translations[language])
        #expect(Set(values.keys) == keys)
        for key in L10nKey.allCases {
            let value = try #require(values[key])
            let english = try #require(EnglishTranslations.values[key])
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(value.components(separatedBy: "%@").count == english.components(separatedBy: "%@").count)
        }
    }
}

@Test func missingTranslationsFallBackToEnglishAndArgumentsRemainLiteral() {
    #expect(L10n.render(.exportCount, arguments: ["2"], language: .japanese, catalog: [:]) == "Export Images (2)")
    let filename = "test-%@-100%%.pdf"
    for language in AppLanguage.allCases {
        let text = L10n.text(.pdfPageName, filename, "12", language: language)
        #expect(text.contains(filename))
        #expect(text.contains("12"))
        #expect(L10n.text(.reduction, "97.3", language: language).contains("97.3%"))
        #expect(!L10n.text(.exportSummary, "2", "3", language: language).contains("%@"))
    }
    #expect(L10n.text(.chooseImages, language: .english) == "Choose Images")
    #expect(L10n.text(.chooseImages, language: .traditionalChinese) == "選擇圖片")
    #expect(L10n.text(.chooseImages, language: .japanese) == "画像を選択")
}
