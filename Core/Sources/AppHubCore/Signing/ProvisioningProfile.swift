import Foundation

public enum ProfileKind: String, Codable, Sendable {
    case development
    case adHoc
    case appStore
    case enterprise
    case unknown
}

public struct ProvisioningProfileInfo: Codable, Sendable, Equatable {
    public let name: String
    public let appIDName: String?
    public let teamName: String?
    public let teamIdentifiers: [String]
    public let applicationIdentifier: String?
    public let creationDate: Date?
    public let expirationDate: Date?
    public let provisionedDeviceCount: Int?
    public let kind: ProfileKind
    public let entitlements: [String: String]
    public let certificates: [X509CertificateSummary]
    public let signatureVerified: Bool

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expirationDate else { return false }
        return expirationDate < date
    }
}

public enum ProvisioningProfileParser {
    /// Extracts the embedded property list from a CMS-signed `.mobileprovision`.
    /// The CMS signature itself is not verified here; `signatureVerified` is
    /// therefore always false unless a platform verifier checked it.
    public static func parse(data: Data) throws -> ProvisioningProfileInfo {
        guard let plistData = embeddedPlist(in: data) else {
            throw AppHubError(.profileUnreadable, "No property list found in the provisioning profile.")
        }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil)
        } catch {
            throw AppHubError(.profileUnreadable, "The provisioning profile plist could not be parsed.")
        }
        guard let dictionary = object as? [String: Any] else {
            throw AppHubError(.profileUnreadable, "The provisioning profile plist is not a dictionary.")
        }

        let name = (dictionary["Name"] as? String) ?? "—"
        let appIDName = dictionary["AppIDName"] as? String
        let teamName = dictionary["TeamName"] as? String
        let teamIdentifiers = (dictionary["TeamIdentifier"] as? [String]) ?? []
        let entitlementsDictionary = (dictionary["Entitlements"] as? [String: Any]) ?? [:]
        let applicationIdentifier = entitlementsDictionary["application-identifier"] as? String
        let provisionedDevices = dictionary["ProvisionedDevices"] as? [String]
        let creationDate = dictionary["CreationDate"] as? Date
        let expirationDate = dictionary["ExpirationDate"] as? Date
        let provisionsAllDevices = (dictionary["ProvisionsAllDevices"] as? Bool) ?? false
        let getTaskAllow = (entitlementsDictionary["get-task-allow"] as? Bool) ?? false
        let betaReports = (dictionary["BetaReportsActive"] as? Bool) ?? false

        let kind: ProfileKind
        if provisionsAllDevices {
            kind = .enterprise
        } else if getTaskAllow {
            kind = .development
        } else if provisionedDevices != nil {
            kind = .adHoc
        } else if betaReports {
            kind = .appStore
        } else {
            kind = .appStore
        }

        var flattenedEntitlements: [String: String] = [:]
        for (key, value) in entitlementsDictionary {
            flattenedEntitlements[key] = describe(value)
        }

        let certificateData = (dictionary["DeveloperCertificates"] as? [Data]) ?? []
        let certificates = certificateData.compactMap { X509CertificateSummary.parse(der: $0) }

        return ProvisioningProfileInfo(
            name: name,
            appIDName: appIDName,
            teamName: teamName,
            teamIdentifiers: teamIdentifiers,
            applicationIdentifier: applicationIdentifier,
            creationDate: creationDate,
            expirationDate: expirationDate,
            provisionedDeviceCount: provisionedDevices?.count,
            kind: kind,
            entitlements: flattenedEntitlements,
            certificates: certificates,
            signatureVerified: false
        )
    }

    public static func embeddedPlist(in data: Data) -> Data? {
        let xmlStart = Data("<?xml".utf8)
        let xmlEnd = Data("</plist>".utf8)
        if let start = data.range(of: xmlStart),
           let end = data.range(of: xmlEnd, in: start.lowerBound..<data.endIndex) {
            return data.subdata(in: start.lowerBound..<end.upperBound)
        }

        let binaryMagic = Data("bplist00".utf8)
        var searchRange = data.startIndex..<data.endIndex
        while let range = data.range(of: binaryMagic, options: [], in: searchRange) {
            let candidate = data.subdata(in: range.lowerBound..<data.endIndex)
            if (try? PropertyListSerialization.propertyList(from: candidate, options: [], format: nil)) != nil {
                return candidate
            }
            searchRange = range.upperBound..<data.endIndex
        }
        return nil
    }

    private static func describe(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value ? "true" : "false" }
        if let value = value as? NSNumber { return value.stringValue }
        if let value = value as? [Any] {
            return value.map(describe).joined(separator: ", ")
        }
        if let value = value as? [String: Any] {
            return value.keys.sorted().joined(separator: ", ")
        }
        return String(describing: value)
    }
}

public enum SigningRecordKind: String, Codable, Sendable {
    case provisioningProfile
    case certificate
}

public struct SigningRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var kind: SigningRecordKind
    public var displayName: String
    public var teamName: String?
    public var teamIdentifiers: [String]
    public var applicationIdentifier: String?
    public var profileKind: ProfileKind?
    public var createdAt: Date?
    public var expiresAt: Date?
    public var importedAt: Date
    public var deviceCount: Int?
    public var entitlements: [String: String]
    public var certificates: [X509CertificateSummary]
    public var signatureVerified: Bool
    public var sourceFileName: String?

    public init(
        id: UUID = UUID(),
        kind: SigningRecordKind,
        displayName: String,
        teamName: String? = nil,
        teamIdentifiers: [String] = [],
        applicationIdentifier: String? = nil,
        profileKind: ProfileKind? = nil,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        importedAt: Date = Date(),
        deviceCount: Int? = nil,
        entitlements: [String: String] = [:],
        certificates: [X509CertificateSummary] = [],
        signatureVerified: Bool = false,
        sourceFileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.teamName = teamName
        self.teamIdentifiers = teamIdentifiers
        self.applicationIdentifier = applicationIdentifier
        self.profileKind = profileKind
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.importedAt = importedAt
        self.deviceCount = deviceCount
        self.entitlements = entitlements
        self.certificates = certificates
        self.signatureVerified = signatureVerified
        self.sourceFileName = sourceFileName
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < date
    }

    public static func from(profile: ProvisioningProfileInfo, fileName: String?) -> SigningRecord {
        SigningRecord(
            kind: .provisioningProfile,
            displayName: profile.name,
            teamName: profile.teamName,
            teamIdentifiers: profile.teamIdentifiers,
            applicationIdentifier: profile.applicationIdentifier,
            profileKind: profile.kind,
            createdAt: profile.creationDate,
            expiresAt: profile.expirationDate,
            deviceCount: profile.provisionedDeviceCount,
            entitlements: profile.entitlements,
            certificates: profile.certificates,
            signatureVerified: profile.signatureVerified,
            sourceFileName: fileName
        )
    }
}

public actor SigningStore {
    private let paths: AppHubPaths
    private var records: [SigningRecord]?

    public init(paths: AppHubPaths) {
        self.paths = paths
    }

    public func list() throws -> [SigningRecord] {
        try loadIfNeeded()
        return (records ?? []).sorted { $0.importedAt > $1.importedAt }
    }

    @discardableResult
    public func importProfile(from url: URL) throws -> SigningRecord {
        let data = try FileStore.read(url)
        let profile = try ProvisioningProfileParser.parse(data: data)
        let record = SigningRecord.from(profile: profile, fileName: url.lastPathComponent)
        try add(record)
        return record
    }

    public func add(_ record: SigningRecord) throws {
        try loadIfNeeded()
        try paths.prepare()
        records = (records ?? []) + [record]
        try persist()
    }

    public func remove(id: UUID) throws {
        try loadIfNeeded()
        records?.removeAll { $0.id == id }
        try persist()
    }

    public func removeAll() throws {
        records = []
        try persist()
    }

    private var fileURL: URL {
        paths.certificates.appendingPathComponent("signing-records.json")
    }

    private func loadIfNeeded() throws {
        guard records == nil else { return }
        try paths.prepare()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        let data = try FileStore.read(fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            records = try decoder.decode([SigningRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records ?? [])
        try FileStore.writeAtomically(data, to: fileURL)
    }
}
