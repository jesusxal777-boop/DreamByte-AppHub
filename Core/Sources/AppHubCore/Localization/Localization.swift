import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case spanish = "es"
    case english = "en"
    case french = "fr"
    case portuguese = "pt"

    public var id: String { rawValue }

    /// Endonym: always shown in the language itself, never translated.
    public var endonym: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        case .french: "Français"
        case .portuguese: "Português"
        }
    }

    public var localeIdentifier: String {
        switch self {
        case .spanish: "es"
        case .english: "en"
        case .french: "fr"
        case .portuguese: "pt"
        }
    }
}

/// Immutable catalog of every bundled language. Loaded once, shared by the UI.
public struct LocalizationCatalog: Sendable {
    public let translations: [AppLanguage: [String: String]]

    public init(translations: [AppLanguage: [String: String]]) {
        self.translations = translations
    }

    public static func bundled() -> LocalizationCatalog {
        guard let directory = bundledDirectory else {
            return LocalizationCatalog(translations: [:])
        }
        return load(directory: directory)
    }

    /// Directory holding the bundled `es/en/fr/pt` JSON catalogs. Exposed for
    /// diagnostics and tests; `nil` only if the resource bundle is missing.
    public static var bundledDirectory: URL? {
        Bundle.module.url(forResource: "Localization", withExtension: nil)
    }

    public static func load(directory: URL) -> LocalizationCatalog {
        var translations: [AppLanguage: [String: String]] = [:]
        for language in AppLanguage.allCases {
            let url = directory.appendingPathComponent("\(language.rawValue).json")
            guard let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                continue
            }
            translations[language] = decoded
        }
        return LocalizationCatalog(translations: translations)
    }

    public var availableLanguages: [AppLanguage] {
        AppLanguage.allCases.filter { translations[$0] != nil }
    }

    public func translation(for language: AppLanguage, key: L10nKey) -> String? {
        translations[language]?[key.rawValue]
    }

    public func missingKeys(in language: AppLanguage) -> [String] {
        guard let catalog = translations[language] else {
            return L10nKey.allCases.map(\.rawValue)
        }
        return L10nKey.allCases.map(\.rawValue).filter { catalog[$0] == nil }
    }

    public func language(preferred: [String]) -> AppLanguage {
        for identifier in preferred {
            let prefix = identifier.lowercased().split(separator: "-").first.map(String.init) ?? ""
            if let match = AppLanguage(rawValue: prefix), translations[match] != nil {
                return match
            }
        }
        return .spanish
    }
}

public struct Localizer: Sendable {
    public let language: AppLanguage
    public let catalog: LocalizationCatalog

    public init(language: AppLanguage, catalog: LocalizationCatalog) {
        self.language = language
        self.catalog = catalog
    }

    /// Spanish is the primary development language, so it is the first fallback,
    /// followed by English, then the raw key (never an empty string).
    public func text(_ key: L10nKey) -> String {
        if let value = catalog.translation(for: language, key: key), !value.isEmpty {
            return value
        }
        if let value = catalog.translation(for: .spanish, key: key), !value.isEmpty {
            return value
        }
        if let value = catalog.translation(for: .english, key: key), !value.isEmpty {
            return value
        }
        return key.rawValue
    }

    public func format(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    public func withLanguage(_ language: AppLanguage) -> Localizer {
        Localizer(language: language, catalog: catalog)
    }
}

public enum LanguageResolver {
    /// User override wins; otherwise the first preferred language AppHub
    /// supports; otherwise Spanish.
    public static func resolve(
        override: AppLanguage?,
        preferred: [String],
        catalog: LocalizationCatalog
    ) -> AppLanguage {
        if let override, catalog.translations[override] != nil {
            return override
        }
        return catalog.language(preferred: preferred)
    }
}

public extension AppHubError {
    var localizationKey: L10nKey {
        switch kind {
        case .fileRead: .errorFileRead
        case .fileWrite: .errorFileWrite
        case .invalidArchive: .errorInvalidArchive
        case .unsupportedCompression: .errorUnsupportedCompression
        case .encryptedArchive: .errorEncryptedArchive
        case .missingPayload: .errorMissingPayload
        case .multipleAppBundles: .errorMultipleAppBundles
        case .missingInfoPlist: .errorMissingInfoPlist
        case .invalidInfoPlist: .errorInvalidInfoPlist
        case .missingBundleIdentifier: .errorMissingBundleIdentifier
        case .missingExecutable: .errorMissingExecutable
        case .unsafePath: .errorUnsafePath
        case .archiveTooLarge: .errorArchiveTooLarge
        case .entryTooLarge: .errorEntryTooLarge
        case .checksumMismatch: .errorChecksumMismatch
        case .invalidURL: .errorInvalidURL
        case .invalidSource: .errorInvalidSource
        case .duplicateSource: .errorDuplicateSource
        case .network: .errorNetwork
        case .httpStatus: .errorHttpStatus
        case .timeout: .errorTimeout
        case .cancelled: .errorCancelled
        case .downloadFailed: .errorDownloadFailed
        case .validationFailed: .errorValidationFailed
        case .profileUnreadable: .errorProfileUnreadable
        case .certificateUnreadable: .errorCertificateUnreadable
        case .unsupportedPlatform: .errorUnsupportedPlatform
        case .notAvailable: .errorNotAvailable
        case .unknown: .errorUnknown
        }
    }
}
