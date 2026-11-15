import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin wrapper around the StikDebug URL scheme. AppHub only *hands off*; it
/// cannot confirm that JIT was enabled, and it never reports success on its own.
enum StikDebugLauncher {
    static let scheme = "stikdebug"

    @MainActor
    static var isInstalled: Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    @MainActor
    static func open(_ url: URL) -> Bool {
        #if canImport(UIKit)
        guard UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
        #else
        return false
        #endif
    }

    @MainActor
    static func openApp() -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return open(url)
    }
}
