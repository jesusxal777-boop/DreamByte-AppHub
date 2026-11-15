import Foundation

public struct PackageFailure: Codable, Sendable, Equatable {
    public let kind: AppHubErrorKind
    public let message: String

    public init(kind: AppHubErrorKind, message: String) {
        self.kind = kind
        self.message = message
    }

    public init(error: AppHubError) {
        self.kind = error.kind
        self.message = error.message
    }
}

public struct AppPackage: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var originalName: String
    public var storedFileName: String
    public var importedAt: Date
    public var fileSize: Int64
    public var inspection: IPAInspection?
    public var failure: PackageFailure?
    public var iconFileName: String?
    public var quarantined: Bool

    public init(
        id: UUID = UUID(),
        originalName: String,
        storedFileName: String,
        importedAt: Date = Date(),
        fileSize: Int64,
        inspection: IPAInspection?,
        failure: PackageFailure? = nil,
        iconFileName: String? = nil,
        quarantined: Bool = true
    ) {
        self.id = id
        self.originalName = originalName
        self.storedFileName = storedFileName
        self.importedAt = importedAt
        self.fileSize = fileSize
        self.inspection = inspection
        self.failure = failure
        self.iconFileName = iconFileName
        self.quarantined = quarantined
    }
}

/// File-backed IPA library. All mutations happen inside the actor; the JSON
/// index is rewritten atomically after each change.
public actor AppPackageStore {
    private let paths: AppHubPaths
    private var packages: [AppPackage]?

    public init(paths: AppHubPaths) {
        self.paths = paths
    }

    public func all() throws -> [AppPackage] {
        try loadIfNeeded()
        return (packages ?? []).sorted { $0.importedAt > $1.importedAt }
    }

    public func packageURL(for package: AppPackage) -> URL {
        paths.ipas.appendingPathComponent(package.storedFileName)
    }

    public func iconURL(for package: AppPackage) -> URL? {
        guard let iconFileName = package.iconFileName else { return nil }
        let url = paths.icons.appendingPathComponent(iconFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    public func importPackage(from source: URL) throws -> AppPackage {
        try loadIfNeeded()
        try paths.prepare()

        let id = UUID()
        let storedFileName = "\(id.uuidString).ipa"
        let destination = paths.ipas.appendingPathComponent(storedFileName)
        try FileStore.importCopy(from: source, to: destination)

        let size = (try? FileStore.size(of: destination)) ?? 0
        var inspection: IPAInspection?
        var failure: PackageFailure?
        var iconFileName: String?

        do {
            let result = try IPAInspector(url: destination).inspect()
            inspection = result.inspection
            if let iconData = result.iconData, !iconData.isEmpty {
                let name = "\(id.uuidString).png"
                try FileStore.writeAtomically(iconData, to: paths.icons.appendingPathComponent(name))
                iconFileName = name
            }
        } catch let error as AppHubError {
            failure = PackageFailure(error: error)
        } catch {
            failure = PackageFailure(kind: .unknown, message: error.localizedDescription)
        }

        let package = AppPackage(
            id: id,
            originalName: source.lastPathComponent,
            storedFileName: storedFileName,
            fileSize: size,
            inspection: inspection,
            failure: failure,
            iconFileName: iconFileName
        )
        packages = (packages ?? []) + [package]
        try persist()
        return package
    }

    /// Replaces a stored record in place (used after re-inspection). Throws only
    /// if the index cannot be written; a missing record is a no-op.
    public func replace(_ package: AppPackage) throws {
        try loadIfNeeded()
        guard let index = packages?.firstIndex(where: { $0.id == package.id }) else { return }
        packages?[index] = package
        try persist()
    }

    public func delete(_ package: AppPackage) throws {
        try loadIfNeeded()
        try FileStore.removeIfExists(packageURL(for: package))
        if let iconFileName = package.iconFileName {
            try? FileStore.removeIfExists(paths.icons.appendingPathComponent(iconFileName))
        }
        packages?.removeAll { $0.id == package.id }
        try persist()
    }

    public func rename(_ package: AppPackage, to newName: String) throws {
        try loadIfNeeded()
        guard let index = packages?.firstIndex(where: { $0.id == package.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        packages?[index].originalName = trimmed
        try persist()
    }

    public func totalBytes() throws -> Int64 {
        try loadIfNeeded()
        return (packages ?? []).reduce(0) { $0 + $1.fileSize }
    }

    private func loadIfNeeded() throws {
        guard packages == nil else { return }
        try paths.prepare()
        guard FileManager.default.fileExists(atPath: paths.libraryFile.path) else {
            packages = []
            return
        }
        let data = try FileStore.read(paths.libraryFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            packages = try decoder.decode([AppPackage].self, from: data)
        } catch {
            // A corrupt index must not hide the files: start clean and rebuild lazily.
            packages = []
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(packages ?? [])
        try FileStore.writeAtomically(data, to: paths.libraryFile)
    }
}
