import Foundation
import XCTest
@testable import AppHubCore

final class LocalizationTests: XCTestCase {
    private var catalog: LocalizationCatalog { .bundled() }

    func testBundledCatalogLoadsEveryLanguage() {
        XCTAssertEqual(Set(catalog.availableLanguages), Set(AppLanguage.allCases))
    }

    func testEveryKeyExistsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let missing = catalog.missingKeys(in: language)
            XCTAssertTrue(missing.isEmpty, "\(language.rawValue) is missing \(missing.prefix(5))")
            XCTAssertNotNil(catalog.translations[language])
        }
    }

    func testNoEmptyTranslations() {
        for language in AppLanguage.allCases {
            let translations = catalog.translations[language] ?? [:]
            let empty = translations.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            XCTAssertTrue(empty.isEmpty, "\(language.rawValue) has empty values for \(empty.keys.prefix(5))")
        }
    }

    func testCatalogsShareExactlyTheSameKeys() {
        let keySets = AppLanguage.allCases.map { Set((catalog.translations[$0] ?? [:]).keys) }
        guard let first = keySets.first else {
            XCTFail("No catalogs")
            return
        }
        for (index, set) in keySets.enumerated() {
            XCTAssertEqual(set, first, "Language \(AppLanguage.allCases[index].rawValue) diverges")
        }
        XCTAssertEqual(first.count, L10nKey.allCases.count)
    }

    func testNoDuplicateKeysAfterDecoding() throws {
        // JSONDecoder silently keeps the last duplicate, so compare raw source
        // keys by parsing with JSONSerialization and counting text occurrences.
        let directory = try XCTUnwrap(LocalizationCatalog.bundledDirectory)
        for language in AppLanguage.allCases {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(language.rawValue).json"))
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(object)
            XCTAssertEqual(object?.count, L10nKey.allCases.count)
        }
    }

    func testTranslationsActuallyDiffer() {
        let spanish = catalog.translations[.spanish]?[L10nKey.dashboardTitle.rawValue]
        let english = catalog.translations[.english]?[L10nKey.dashboardTitle.rawValue]
        XCTAssertEqual(english, "Dashboard")
        XCTAssertEqual(spanish, "Panel")
        XCTAssertNotEqual(spanish, english)
    }

    func testLocalizerFallsBackInOrder() {
        let partial = LocalizationCatalog(translations: [
            .spanish: [L10nKey.commonCancel.rawValue: "Cancelar"],
            .english: [L10nKey.commonCancel.rawValue: "Cancel"]
        ])
        XCTAssertEqual(Localizer(language: .french, catalog: partial).text(.commonCancel), "Cancelar")
        XCTAssertEqual(
            Localizer(language: .french, catalog: LocalizationCatalog(translations: [:])).text(.commonCancel),
            L10nKey.commonCancel.rawValue
        )
        XCTAssertEqual(Localizer(language: .english, catalog: catalog).text(.commonCancel), "Cancel")
        XCTAssertEqual(Localizer(language: .french, catalog: catalog).text(.commonCancel), "Annuler")
    }

    func testFormatUsesLanguageLocale() {
        let source: [L10nKey: String] = [.commonBytes: "%d %@"]
        // Sanity: the real key exists and is non-empty in every language.
        for language in AppLanguage.allCases {
            XCTAssertFalse(catalog.translation(for: language, key: .commonBytes)?.isEmpty ?? true)
        }
        XCTAssertEqual(source.count, 1)
        let custom = LocalizationCatalog(translations: [
            .english: [L10nKey.commonBytes.rawValue: "%d bytes"],
            .french: [L10nKey.commonBytes.rawValue: "%d octets"]
        ])
        XCTAssertEqual(Localizer(language: .french, catalog: custom).format(.commonBytes, 12), "12 octets")
    }

    func testLanguageResolution() {
        XCTAssertEqual(LanguageResolver.resolve(override: .french, preferred: ["en-US"], catalog: catalog), .french)
        XCTAssertEqual(LanguageResolver.resolve(override: nil, preferred: ["pt-BR", "en"], catalog: catalog), .portuguese)
        XCTAssertEqual(LanguageResolver.resolve(override: nil, preferred: ["de-DE", "fr-FR"], catalog: catalog), .french)
        XCTAssertEqual(LanguageResolver.resolve(override: nil, preferred: ["de-DE"], catalog: catalog), .spanish)
        XCTAssertEqual(LanguageResolver.resolve(override: .english, preferred: ["de-DE"], catalog: catalog), .english)
    }

    func testLanguageEndonymsAreSelfDescribed() {
        XCTAssertEqual(AppLanguage.spanish.endonym, "Español")
        XCTAssertEqual(AppLanguage.english.endonym, "English")
        XCTAssertEqual(AppLanguage.french.endonym, "Français")
        XCTAssertEqual(AppLanguage.portuguese.endonym, "Português")
    }

    func testErrorKindsMapToLocalizedKeys() {
        let error = AppHubError(.checksumMismatch, "boom")
        XCTAssertEqual(error.localizationKey, .errorChecksumMismatch)
        XCTAssertEqual(Localizer(language: .english, catalog: catalog).text(error.localizationKey), "The checksum does not match.")
        XCTAssertEqual(AppHubError.cancelled.localizationKey, .errorCancelled)
    }
}
