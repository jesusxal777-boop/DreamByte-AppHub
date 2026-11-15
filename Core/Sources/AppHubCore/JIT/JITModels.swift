import Foundation

public enum JITMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case waitForDebugger
    case stikDebug
    case builtIn

    public var id: String { rawValue }

    public var isAvailableInThisBuild: Bool {
        self == .waitForDebugger || self == .stikDebug
    }
}

public enum JITReadiness: String, Codable, Sendable, Equatable {
    case ready
    case requiresSetup
    case unavailable
    case unknown
}

public struct JITPrerequisites: Codable, Sendable, Equatable {
    public var systemVersion: String
    public var hasGetTaskAllow: Bool?
    public var pairingFilePresent: Bool
    public var stikDebugInstalled: Bool?
    public var isTXMPresent: Bool?

    public init(
        systemVersion: String,
        hasGetTaskAllow: Bool?,
        pairingFilePresent: Bool,
        stikDebugInstalled: Bool?,
        isTXMPresent: Bool?
    ) {
        self.systemVersion = systemVersion
        self.hasGetTaskAllow = hasGetTaskAllow
        self.pairingFilePresent = pairingFilePresent
        self.stikDebugInstalled = stikDebugInstalled
        self.isTXMPresent = isTXMPresent
    }

    public var readiness: JITReadiness {
        guard let hasGetTaskAllow else { return .unknown }
        guard hasGetTaskAllow else { return .unavailable }
        guard pairingFilePresent, stikDebugInstalled == true else { return .requiresSetup }
        return .ready
    }
}

/// Builds the documented StikDebug handoff URL. AppHub never pretends that
/// opening this URL enabled JIT; success must be verified separately.
public enum StikDebugHandoff {
    public static func enableJITURL(
        bundleIdentifier: String,
        processIdentifier: Int32,
        scriptName: String? = nil,
        scriptBase64: String? = nil
    ) -> URL? {
        guard !bundleIdentifier.isEmpty, processIdentifier > 0 else { return nil }
        var components = URLComponents()
        components.scheme = "stikdebug"
        components.host = "enable-jit"
        var items = [
            URLQueryItem(name: "bundle-id", value: bundleIdentifier),
            URLQueryItem(name: "pid", value: String(processIdentifier))
        ]
        if let scriptBase64, !scriptBase64.isEmpty {
            items.append(URLQueryItem(name: "script-data", value: scriptBase64))
        } else if let scriptName, !scriptName.isEmpty {
            items.append(URLQueryItem(name: "script-name", value: scriptName))
        }
        components.queryItems = items
        return components.url
    }

    public static let bundleQueryScheme = "stikdebug"
    public static let supportedScriptNames = ["universal.js", "legacy.js"]
}

public struct PairingFileImporter {
    /// Basic structural validation of a pairing plist. It does not prove the
    /// pairing is currently valid; only the debug connection can do that.
    public static func validate(data: Data) -> Bool {
        guard !data.isEmpty, data.count <= 2 << 20 else { return false }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return false
        }
        return dictionary["DeviceCertificate"] != nil
            || dictionary["HostCertificate"] != nil
            || dictionary["UDID"] != nil
    }
}
