import Foundation

/// Stable, user-mappable error kinds. UI code localizes these; the raw engine
/// messages stay in English for diagnostics and logs.
public enum AppHubErrorKind: String, Codable, Sendable, Equatable {
    case fileRead
    case fileWrite
    case invalidArchive
    case unsupportedCompression
    case encryptedArchive
    case missingPayload
    case multipleAppBundles
    case missingInfoPlist
    case invalidInfoPlist
    case missingBundleIdentifier
    case missingExecutable
    case unsafePath
    case archiveTooLarge
    case entryTooLarge
    case checksumMismatch
    case invalidURL
    case invalidSource
    case duplicateSource
    case network
    case httpStatus
    case timeout
    case cancelled
    case downloadFailed
    case validationFailed
    case profileUnreadable
    case certificateUnreadable
    case unsupportedPlatform
    case notAvailable
    case unknown
}

public struct AppHubError: Error, Sendable, Equatable, LocalizedError {
    public let kind: AppHubErrorKind
    public let message: String
    public let statusCode: Int?

    public init(_ kind: AppHubErrorKind, _ message: String, statusCode: Int? = nil) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
    }

    public var errorDescription: String? { message }

    public static func fileRead(_ message: String) -> AppHubError {
        AppHubError(.fileRead, message)
    }

    public static func fileWrite(_ message: String) -> AppHubError {
        AppHubError(.fileWrite, message)
    }

    public static func invalidArchive(_ message: String) -> AppHubError {
        AppHubError(.invalidArchive, message)
    }

    public static func invalidSource(_ message: String) -> AppHubError {
        AppHubError(.invalidSource, message)
    }

    public static func network(_ message: String) -> AppHubError {
        AppHubError(.network, message)
    }

    public static let cancelled = AppHubError(.cancelled, "The operation was cancelled.")
    public static let notAvailable = AppHubError(.notAvailable, "This capability is not available on this device.")
}
