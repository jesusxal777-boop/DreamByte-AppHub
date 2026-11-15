import Foundation

public enum DownloadState: String, Codable, Sendable, Equatable {
    case waiting
    case downloading
    case validating
    case completed
    case failed
    case cancelled
}

public struct DownloadJob: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var appName: String
    public var bundleIdentifier: String
    public var version: String
    public var downloadURL: String
    public var sourceName: String
    public var fileName: String
    public var bytesReceived: Int64
    public var totalBytes: Int64
    public var state: DownloadState
    public var createdAt: Date
    public var completedAt: Date?
    public var errorMessage: String?
    public var sha256: String?
    public var validationNotes: [String]
    public var taskIdentifier: Int?

    public init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        version: String,
        downloadURL: String,
        sourceName: String,
        fileName: String,
        bytesReceived: Int64 = 0,
        totalBytes: Int64 = 0,
        state: DownloadState = .waiting,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        sha256: String? = nil,
        validationNotes: [String] = [],
        taskIdentifier: Int? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.downloadURL = downloadURL
        self.sourceName = sourceName
        self.fileName = fileName
        self.bytesReceived = bytesReceived
        self.totalBytes = totalBytes
        self.state = state
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.sha256 = sha256
        self.validationNotes = validationNotes
        self.taskIdentifier = taskIdentifier
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(bytesReceived) / Double(totalBytes)))
    }

    public var isActive: Bool {
        state == .waiting || state == .downloading || state == .validating
    }
}

public struct DownloadValidation: Sendable, Equatable {
    public let isValid: Bool
    public let sha256: String?
    public let notes: [String]
    public let inspection: IPAInspection?

    public init(isValid: Bool, sha256: String?, notes: [String], inspection: IPAInspection?) {
        self.isValid = isValid
        self.sha256 = sha256
        self.notes = notes
        self.inspection = inspection
    }
}

public enum DownloadValidator {
    public static func validate(
        fileURL: URL,
        expectedSize: Int64?,
        expectedSHA256: String?,
        expectedBundleIdentifier: String,
        expectedVersion: String?
    ) throws -> DownloadValidation {
        var notes: [String] = []
        let size = try FileStore.size(of: fileURL)
        if let expectedSize, expectedSize > 0, expectedSize != size {
            throw AppHubError(.validationFailed, "Size mismatch: expected \(expectedSize) bytes, got \(size).")
        }

        let data = try FileStore.read(fileURL)
        let sha = SHA256.hex(data)
        if let expectedSHA256, !expectedSHA256.isEmpty {
            let normalized = expectedSHA256.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized == sha else {
                throw AppHubError(.validationFailed, "SHA-256 mismatch for the downloaded file.")
            }
            notes.append("SHA-256 verified.")
        } else {
            notes.append("SHA-256 recorded; no publisher checksum supplied.")
        }

        let result = try IPAInspector(url: fileURL).inspect()
        guard result.inspection.bundleIdentifier == expectedBundleIdentifier else {
            throw AppHubError(
                .validationFailed,
                "The IPA identifies as \(result.inspection.bundleIdentifier), not \(expectedBundleIdentifier)."
            )
        }
        if let expectedVersion, expectedVersion != "—", result.inspection.version != expectedVersion {
            notes.append("Source lists \(expectedVersion); IPA reports \(result.inspection.version).")
        }
        if result.inspection.isEncrypted {
            notes.append("The IPA is FairPlay-encrypted and cannot be installed by AppHub.")
        }
        if !result.inspection.hasCodeSignature {
            notes.append("The IPA has no code signature; signing is required before installation.")
        }

        return DownloadValidation(
            isValid: true,
            sha256: sha,
            notes: notes,
            inspection: result.inspection
        )
    }
}

public actor DownloadService {
    private let paths: AppHubPaths
    private let downloader: FileDownloader
    private var jobs: [DownloadJob]?
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(paths: AppHubPaths, downloader: FileDownloader = FileDownloader()) {
        self.paths = paths
        self.downloader = downloader
    }

    public func list() throws -> [DownloadJob] {
        try loadIfNeeded()
        return (jobs ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    public func job(id: UUID) throws -> DownloadJob? {
        try loadIfNeeded()
        return jobs?.first { $0.id == id }
    }

    public nonisolated func fileURL(for job: DownloadJob) -> URL {
        paths.downloads.appendingPathComponent(job.fileName)
    }

    @discardableResult
    public func start(
        app: SourceApp,
        version: SourceVersion,
        sourceName: String,
        progress: @escaping @Sendable (DownloadJob) -> Void = { _ in },
        completion: @escaping @Sendable (DownloadJob) -> Void = { _ in }
    ) throws -> DownloadJob {
        try loadIfNeeded()
        guard let url = URLSafety.httpURL(from: version.downloadURL) else {
            throw AppHubError(.invalidURL, "The download URL is not valid.")
        }
        try paths.prepare()

        let id = UUID()
        let job = DownloadJob(
            id: id,
            appName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            version: version.version,
            downloadURL: url.absoluteString,
            sourceName: sourceName,
            fileName: "\(id.uuidString).ipa",
            totalBytes: version.size ?? 0,
            state: .waiting
        )
        jobs = (jobs ?? []) + [job]
        try persist()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(
                jobID: id,
                url: url,
                expectedSize: version.size,
                expectedSHA256: version.sha256 ?? app.apphub?.sha256,
                expectedBundleIdentifier: app.bundleIdentifier,
                expectedVersion: version.version,
                progress: progress,
                completion: completion
            )
        }
        tasks[id] = task
        return job
    }

    public func cancel(id: UUID) throws {
        try loadIfNeeded()
        guard let index = jobs?.firstIndex(where: { $0.id == id }) else { return }
        if let taskIdentifier = jobs?[index].taskIdentifier {
            downloader.cancel(taskIdentifier: taskIdentifier)
        }
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs?[index].state = .cancelled
        jobs?[index].completedAt = Date()
        try persist()
    }

    public func remove(id: UUID) throws {
        try loadIfNeeded()
        guard let job = jobs?.first(where: { $0.id == id }) else { return }
        if job.isActive {
            try cancel(id: id)
        }
        try? FileStore.removeIfExists(fileURL(for: job))
        jobs?.removeAll { $0.id == id }
        try persist()
    }

    public func clearCompleted() throws {
        try loadIfNeeded()
        for job in jobs ?? [] where !job.isActive {
            try? FileStore.removeIfExists(fileURL(for: job))
        }
        jobs?.removeAll { !$0.isActive }
        try persist()
    }

    private func run(
        jobID: UUID,
        url: URL,
        expectedSize: Int64?,
        expectedSHA256: String?,
        expectedBundleIdentifier: String,
        expectedVersion: String,
        progress: @escaping @Sendable (DownloadJob) -> Void,
        completion: @escaping @Sendable (DownloadJob) -> Void
    ) async {
        guard let index = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
        jobs?[index].state = .downloading
        try? persist()
        let snapshot = jobs?[index]
        if let snapshot { progress(snapshot) }

        let destination = paths.downloads.appendingPathComponent(jobs?[index].fileName ?? "\(jobID.uuidString).ipa")

        do {
            _ = try await downloader.download(
                from: url,
                to: destination,
                expectedSize: expectedSize,
                progress: { update in
                    Task { await self.applyProgress(jobID: jobID, update: update, callback: progress) }
                },
                onTaskCreated: { identifier in
                    Task { await self.setTaskIdentifier(jobID: jobID, identifier: identifier) }
                }
            )

            if Task.isCancelled {
                throw AppHubError.cancelled
            }

            guard let validatingIndex = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
            jobs?[validatingIndex].state = .validating
            try? persist()
            if let snapshot = jobs?[validatingIndex] { progress(snapshot) }

            let validation = try DownloadValidator.validate(
                fileURL: destination,
                expectedSize: expectedSize,
                expectedSHA256: expectedSHA256,
                expectedBundleIdentifier: expectedBundleIdentifier,
                expectedVersion: expectedVersion
            )

            guard let doneIndex = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
            jobs?[doneIndex].state = .completed
            jobs?[doneIndex].completedAt = Date()
            jobs?[doneIndex].sha256 = validation.sha256
            jobs?[doneIndex].validationNotes = validation.notes
            let finalSize = (try? FileStore.size(of: destination)) ?? 0
            jobs?[doneIndex].bytesReceived = finalSize
            jobs?[doneIndex].totalBytes = finalSize
            try? persist()
            if let finished = jobs?[doneIndex] { completion(finished) }
        } catch let error as AppHubError {
            guard let failedIndex = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
            jobs?[failedIndex].state = error.kind == .cancelled ? .cancelled : .failed
            jobs?[failedIndex].errorMessage = error.message
            jobs?[failedIndex].completedAt = Date()
            try? persist()
            if let failed = jobs?[failedIndex] { completion(failed) }
        } catch {
            guard let failedIndex = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
            jobs?[failedIndex].state = .failed
            jobs?[failedIndex].errorMessage = error.localizedDescription
            jobs?[failedIndex].completedAt = Date()
            try? persist()
            if let failed = jobs?[failedIndex] { completion(failed) }
        }
        tasks[jobID] = nil
    }

    private func applyProgress(
        jobID: UUID,
        update: DownloadProgress,
        callback: @escaping @Sendable (DownloadJob) -> Void
    ) {
        guard let index = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
        jobs?[index].bytesReceived = update.bytesReceived
        if update.totalBytes > 0 {
            jobs?[index].totalBytes = update.totalBytes
        }
        if let snapshot = jobs?[index] { callback(snapshot) }
    }

    private func setTaskIdentifier(jobID: UUID, identifier: Int) {
        guard let index = jobs?.firstIndex(where: { $0.id == jobID }) else { return }
        jobs?[index].taskIdentifier = identifier
    }

    private var fileURL: URL {
        paths.downloads.appendingPathComponent("downloads.json")
    }

    private func loadIfNeeded() throws {
        guard jobs == nil else { return }
        try paths.prepare()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            jobs = []
            return
        }
        let data = try FileStore.read(fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            jobs = try decoder.decode([DownloadJob].self, from: data)
        } catch {
            jobs = []
        }
        // Jobs persisted as active are stale after a relaunch.
        if var loaded = jobs {
            for index in loaded.indices where loaded[index].isActive {
                loaded[index].state = .failed
                loaded[index].errorMessage = "Interrupted by app restart."
            }
            jobs = loaded
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(jobs ?? [])
        try FileStore.writeAtomically(data, to: fileURL)
    }
}
