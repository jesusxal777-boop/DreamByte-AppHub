import Foundation

/// Cheap checks performed before an IPA is copied into the library. Keeping
/// them in Core makes the failure cases testable on Linux, where the SwiftUI
/// document picker is not available.
public enum IPAImportPreflightResult: String, Sendable, Equatable {
    case ready
    case wrongExtension
    case notAFile
    case emptyFile
}

public enum IPAImportPreflight {
    public static func check(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> IPAImportPreflightResult {
        guard url.isFileURL else { return .notAFile }
        guard url.pathExtension.lowercased() == "ipa" else { return .wrongExtension }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return .notAFile
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber,
           size.int64Value == 0 {
            return .emptyFile
        }

        return .ready
    }
}
