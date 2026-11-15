import Foundation

public struct DiagnosticEnvironment: Codable, Sendable, Equatable {
    public var appVersion: String
    public var appBuild: String
    public var osName: String
    public var osVersion: String
    public var deviceModel: String
    public var localeIdentifier: String
    public var interfaceLanguage: String
    public var isDevelopmentBuild: Bool

    public init(
        appVersion: String,
        appBuild: String,
        osName: String,
        osVersion: String,
        deviceModel: String,
        localeIdentifier: String,
        interfaceLanguage: String,
        isDevelopmentBuild: Bool
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.localeIdentifier = localeIdentifier
        self.interfaceLanguage = interfaceLanguage
        self.isDevelopmentBuild = isDevelopmentBuild
    }
}

public struct DiagnosticModule: Codable, Sendable, Equatable {
    public var name: String
    public var status: String
    public var detail: String

    public init(name: String, status: String, detail: String) {
        self.name = name
        self.status = status
        self.detail = detail
    }
}

public struct DiagnosticReport: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var environment: DiagnosticEnvironment
    public var modules: [DiagnosticModule]
    public var counts: [String: Int]
    public var notes: [String]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        environment: DiagnosticEnvironment,
        modules: [DiagnosticModule],
        counts: [String: Int],
        notes: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.environment = environment
        self.modules = modules
        self.counts = counts
        self.notes = notes
    }
}

public enum DiagnosticBuilder {
    public static func encode(_ report: DiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    /// Defense in depth: reports never intentionally include pairing paths or
    /// secrets, but free-form strings are scrubbed before export.
    public static func redact(_ value: String) -> String {
        var result = value
        let patterns = [
            #"(/(?:Users|home|private|var/mobile)/[^\s"']+)"#,
            #"([A-Za-z]:\\[^\s"']+)"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "<path>")
            }
        }
        return result
    }

    public static func shareText(_ report: DiagnosticReport) throws -> String {
        let data = try encode(report)
        let json = String(decoding: data, as: UTF8.self)
        return redact(json)
    }
}
