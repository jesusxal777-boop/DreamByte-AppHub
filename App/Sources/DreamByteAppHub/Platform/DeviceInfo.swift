import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum DeviceInfo {
    /// Hardware identifier such as `iPhone17,1`. Diagnostics only; never used to
    /// gate features.
    static var modelIdentifier: String {
        #if os(iOS) && canImport(Darwin)
        var info = utsname()
        guard uname(&info) == 0 else { return "iOS device" }
        return withUnsafeBytes(of: &info.machine) { buffer in
            let bytes = buffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    static var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}
