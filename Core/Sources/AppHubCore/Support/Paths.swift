import Foundation

/// Resolves AppHub's on-disk locations. Injectable so tests never touch the
/// user's real application data.
public struct AppHubPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var ipas: URL { root.appendingPathComponent("IPAs", isDirectory: true) }
    public var downloads: URL { root.appendingPathComponent("Downloads", isDirectory: true) }
    public var icons: URL { root.appendingPathComponent("Icons", isDirectory: true) }
    public var certificates: URL { root.appendingPathComponent("Certificates", isDirectory: true) }
    public var exports: URL { root.appendingPathComponent("Exports", isDirectory: true) }
    public var caches: URL { root.appendingPathComponent("Caches", isDirectory: true) }
    public var repositories: URL { root.appendingPathComponent("Repositories", isDirectory: true) }
    public var libraryFile: URL { root.appendingPathComponent("library.json") }

    public func prepare() throws {
        for directory in [root, ipas, downloads, icons, certificates, exports, caches, repositories] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Real application location. Kept separate from `init(root:)` so the core
    /// remains usable in tests and on non-Apple platforms.
    public static func applicationDefault() throws -> AppHubPaths {
        #if os(iOS)
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        #else
        let base = FileManager.default.temporaryDirectory
        #endif
        let paths = AppHubPaths(root: base.appendingPathComponent("AppHub", isDirectory: true))
        try paths.prepare()
        return paths
    }
}

public enum FileStore {
    public static func writeAtomically(_ data: Data, to url: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppHubError.fileWrite("Could not write \((url.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    public static func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw AppHubError.fileRead("Could not read \((url.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    public static func size(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    public static func removeIfExists(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AppHubError.fileWrite("Could not remove \((url.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    /// Copies a file that may come from a security-scoped document picker URL.
    public static func importCopy(from source: URL, to destination: URL) throws {
        #if canImport(Darwin)
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw AppHubError.fileRead("Could not import \((source.lastPathComponent)): \(error.localizedDescription)")
        }
    }
}
