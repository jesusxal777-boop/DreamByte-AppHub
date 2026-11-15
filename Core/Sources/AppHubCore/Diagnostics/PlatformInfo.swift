import Foundation

public enum PlatformInfo {
    public static func environment(
        interfaceLanguage: AppLanguage,
        localeIdentifier: String = Locale.current.identifier,
        deviceModel: String = "unknown"
    ) -> DiagnosticEnvironment {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        let build = (info?["CFBundleVersion"] as? String) ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osName = operatingSystemName
        return DiagnosticEnvironment(
            appVersion: version,
            appBuild: build,
            osName: osName,
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            deviceModel: deviceModel,
            localeIdentifier: localeIdentifier,
            interfaceLanguage: interfaceLanguage.rawValue,
            isDevelopmentBuild: isDevelopmentBuild
        )
    }

    public static var operatingSystemName: String {
        #if os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #elseif os(Linux)
        "Linux"
        #else
        "Unknown"
        #endif
    }

    public static var isDevelopmentBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    public static var deviceModel: String {
        #if os(iOS)
        // UIDevice is a UIKit dependency; the app target injects the real model.
        "iOS device"
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    public static var physicalMemory: Int64 {
        Int64(ProcessInfo.processInfo.physicalMemory)
    }

    public static func freeDiskSpace(at url: URL) -> Int64 {
        #if canImport(Darwin)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        #endif
        // Portable fallback: `volumeAvailableCapacityForImportantUsage` is a
        // Darwin-only hint, and corelibs-foundation does not expose it.
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
           let free = attributes[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return 0
    }
}
