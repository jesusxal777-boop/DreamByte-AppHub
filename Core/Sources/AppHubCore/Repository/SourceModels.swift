import Foundation

public struct SourceVersion: Codable, Sendable, Equatable, Identifiable {
    public var version: String
    public var date: String?
    public var localizedDescription: String?
    public var downloadURL: String
    public var size: Int64?
    public var minOSVersion: String?
    public var maxOSVersion: String?
    /// Optional publisher checksum (`apphub.sha256` extension).
    public var sha256: String?

    public var id: String { "\(version)|\(downloadURL)" }

    public init(
        version: String,
        date: String? = nil,
        localizedDescription: String? = nil,
        downloadURL: String,
        size: Int64? = nil,
        minOSVersion: String? = nil,
        maxOSVersion: String? = nil,
        sha256: String? = nil
    ) {
        self.version = version
        self.date = date
        self.localizedDescription = localizedDescription
        self.downloadURL = downloadURL
        self.size = size
        self.minOSVersion = minOSVersion
        self.maxOSVersion = maxOSVersion
        self.sha256 = sha256
    }
}

public struct SourceApp: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var bundleIdentifier: String
    public var developerName: String?
    public var subtitle: String?
    public var localizedDescription: String?
    public var iconURL: String?
    public var tintColor: String?
    public var versions: [SourceVersion]
    public var beta: Bool?
    public var screenshotURLs: [String]?
    public var apphub: AppHubMetadata?

    public var id: String { bundleIdentifier }

    public init(
        name: String,
        bundleIdentifier: String,
        developerName: String? = nil,
        subtitle: String? = nil,
        localizedDescription: String? = nil,
        iconURL: String? = nil,
        tintColor: String? = nil,
        versions: [SourceVersion],
        beta: Bool? = nil,
        screenshotURLs: [String]? = nil,
        apphub: AppHubMetadata? = nil
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.developerName = developerName
        self.subtitle = subtitle
        self.localizedDescription = localizedDescription
        self.iconURL = iconURL
        self.tintColor = tintColor
        self.versions = versions
        self.beta = beta
        self.screenshotURLs = screenshotURLs
        self.apphub = apphub
    }

    /// AltStore treats the first entry as latest. AppHub keeps that behavior and
    /// exposes the raw list for transparency.
    public var latestVersion: SourceVersion? { versions.first }

    private enum CodingKeys: String, CodingKey {
        case name, bundleIdentifier, developerName, subtitle, localizedDescription
        case iconURL, tintColor, versions, beta, screenshotURLs, apphub
        case legacyVersion = "version"
        case legacyDate = "versionDate"
        case legacyDescription = "versionDescription"
        case legacyDownloadURL = "downloadURL"
        case legacySize = "size"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        developerName = try container.decodeIfPresent(String.self, forKey: .developerName)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
        tintColor = try container.decodeIfPresent(String.self, forKey: .tintColor)
        beta = try container.decodeIfPresent(Bool.self, forKey: .beta)
        versions = try container.decodeIfPresent([SourceVersion].self, forKey: .versions) ?? []
        screenshotURLs = try? container.decodeIfPresent([String].self, forKey: .screenshotURLs)
        apphub = try container.decodeIfPresent(AppHubMetadata.self, forKey: .apphub)

        if versions.isEmpty {
            let legacyVersion = try container.decodeIfPresent(String.self, forKey: .legacyVersion)
            let legacyDownload = try container.decodeIfPresent(String.self, forKey: .legacyDownloadURL)
            if let legacyVersion, let legacyDownload {
                versions = [
                    SourceVersion(
                        version: legacyVersion,
                        date: try container.decodeIfPresent(String.self, forKey: .legacyDate),
                        localizedDescription: try container.decodeIfPresent(String.self, forKey: .legacyDescription),
                        downloadURL: legacyDownload,
                        size: try container.decodeIfPresent(Int64.self, forKey: .legacySize)
                    )
                ]
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encodeIfPresent(developerName, forKey: .developerName)
        try container.encodeIfPresent(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(localizedDescription, forKey: .localizedDescription)
        try container.encodeIfPresent(iconURL, forKey: .iconURL)
        try container.encodeIfPresent(tintColor, forKey: .tintColor)
        try container.encode(versions, forKey: .versions)
        try container.encodeIfPresent(beta, forKey: .beta)
        try container.encodeIfPresent(screenshotURLs, forKey: .screenshotURLs)
        try container.encodeIfPresent(apphub, forKey: .apphub)
    }
}

public struct AppHubMetadata: Codable, Sendable, Equatable {
    public var category: String?
    public var source: String?
    public var homepage: String?
    public var sha256: String?
    public var notes: String?

    public init(
        category: String? = nil,
        source: String? = nil,
        homepage: String? = nil,
        sha256: String? = nil,
        notes: String? = nil
    ) {
        self.category = category
        self.source = source
        self.homepage = homepage
        self.sha256 = sha256
        self.notes = notes
    }
}

public struct SourceNews: Codable, Sendable, Equatable, Identifiable {
    public var title: String
    public var identifier: String
    public var caption: String?
    public var date: String?
    public var url: String?
    public var appID: String?

    public var id: String { identifier }

    public init(
        title: String,
        identifier: String,
        caption: String? = nil,
        date: String? = nil,
        url: String? = nil,
        appID: String? = nil
    ) {
        self.title = title
        self.identifier = identifier
        self.caption = caption
        self.date = date
        self.url = url
        self.appID = appID
    }
}

public struct SourceDocument: Codable, Sendable, Equatable {
    public var name: String
    public var identifier: String
    public var sourceURL: String?
    public var apps: [SourceApp]
    public var news: [SourceNews]

    public init(
        name: String,
        identifier: String,
        sourceURL: String? = nil,
        apps: [SourceApp],
        news: [SourceNews] = []
    ) {
        self.name = name
        self.identifier = identifier
        self.sourceURL = sourceURL
        self.apps = apps
        self.news = news
    }

    private enum CodingKeys: String, CodingKey {
        case name, identifier, sourceURL, apps, news
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        identifier = try container.decode(String.self, forKey: .identifier)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        apps = try container.decodeIfPresent([SourceApp].self, forKey: .apps) ?? []
        news = try container.decodeIfPresent([SourceNews].self, forKey: .news) ?? []
    }
}

// MARK: - Validation

public enum SourceIssueSeverity: String, Sendable, Codable {
    case warning
    case error
}

public struct SourceIssue: Sendable, Equatable, Identifiable {
    public let severity: SourceIssueSeverity
    public let message: String
    public let appIdentifier: String?

    public var id: String { "\(severity.rawValue)|\(appIdentifier ?? "")|\(message)" }

    public init(severity: SourceIssueSeverity, message: String, appIdentifier: String? = nil) {
        self.severity = severity
        self.message = message
        self.appIdentifier = appIdentifier
    }
}

public struct SourceValidation: Sendable {
    public let document: SourceDocument
    public let issues: [SourceIssue]
    public let apps: [SourceApp]

    public var isValid: Bool {
        !issues.contains { $0.severity == .error }
    }
}

public enum URLSafety {
    public static func httpURL(from string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }
}

public enum SourceValidator {
    public static func validate(_ document: SourceDocument) -> SourceValidation {
        var issues: [SourceIssue] = []
        let trimmedName = document.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(SourceIssue(severity: .error, message: "Source name is empty."))
        }
        if document.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(SourceIssue(severity: .error, message: "Source identifier is empty."))
        }
        if let sourceURL = document.sourceURL, URLSafety.httpURL(from: sourceURL) == nil {
            issues.append(SourceIssue(severity: .warning, message: "sourceURL is not an http(s) URL."))
        }

        var seen: Set<String> = []
        var validApps: [SourceApp] = []

        for app in document.apps {
            var appIsValid = true
            let identifier = app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if identifier.isEmpty || !identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) {
                issues.append(SourceIssue(severity: .error, message: "Invalid bundle identifier.", appIdentifier: identifier))
                appIsValid = false
            }
            if seen.contains(identifier) {
                issues.append(SourceIssue(severity: .error, message: "Duplicate bundle identifier.", appIdentifier: identifier))
                appIsValid = false
            }
            seen.insert(identifier)

            if app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(SourceIssue(severity: .error, message: "App name is empty.", appIdentifier: identifier))
                appIsValid = false
            }
            if app.versions.isEmpty {
                issues.append(SourceIssue(severity: .error, message: "App has no versions.", appIdentifier: identifier))
                appIsValid = false
            }
            if let iconURL = app.iconURL, URLSafety.httpURL(from: iconURL) == nil {
                issues.append(SourceIssue(severity: .warning, message: "App icon URL is invalid.", appIdentifier: identifier))
            }

            for version in app.versions {
                if version.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(SourceIssue(severity: .error, message: "Version string is empty.", appIdentifier: identifier))
                    appIsValid = false
                }
                if URLSafety.httpURL(from: version.downloadURL) == nil {
                    issues.append(SourceIssue(severity: .error, message: "Download URL is not http(s).", appIdentifier: identifier))
                    appIsValid = false
                }
                if let size = version.size, size < 0 {
                    issues.append(SourceIssue(severity: .error, message: "Download size is negative.", appIdentifier: identifier))
                    appIsValid = false
                }
            }

            if appIsValid {
                validApps.append(app)
            }
        }

        return SourceValidation(document: document, issues: issues, apps: validApps)
    }
}

public extension SourceVersion {
    func isCompatible(withOSVersion version: OperatingSystemVersion) -> Bool {
        let current = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        if let minOSVersion, compareVersions(current, minOSVersion) < 0 { return false }
        if let maxOSVersion, compareVersions(current, maxOSVersion) > 0 { return false }
        return true
    }
}

private func compareVersions(_ lhs: String, _ rhs: String) -> Int {
    let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
    let count = max(left.count, right.count)
    for index in 0..<count {
        let a = index < left.count ? left[index] : 0
        let b = index < right.count ? right[index] : 0
        if a != b { return a < b ? -1 : 1 }
    }
    return 0
}
