import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResult: Sendable {
    public let data: Data
    public let statusCode: Int
    public let etag: String?
    public let lastModified: String?

    public init(data: Data, statusCode: Int, etag: String? = nil, lastModified: String? = nil) {
        self.data = data
        self.statusCode = statusCode
        self.etag = etag
        self.lastModified = lastModified
    }
}

public protocol HTTPFetching: Sendable {
    func fetch(url: URL, etag: String?, lastModified: String?) async throws -> HTTPResult
}

public struct URLSessionHTTPClient: HTTPFetching {
    public let maximumBytes: Int
    public let timeout: TimeInterval

    public init(maximumBytes: Int = 8 << 20, timeout: TimeInterval = 20) {
        self.maximumBytes = maximumBytes
        self.timeout = timeout
    }

    public func fetch(url: URL, etag: String?, lastModified: String?) async throws -> HTTPResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("application/json, text/json;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        request.setValue("DreamByte-AppHub/0.1", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppHubError.network("The server returned a non-HTTP response.")
            }
            if http.statusCode == 304 {
                return HTTPResult(data: Data(), statusCode: 304, etag: http.value(forHTTPHeaderField: "ETag"), lastModified: http.value(forHTTPHeaderField: "Last-Modified"))
            }
            guard (200..<300).contains(http.statusCode) else {
                throw AppHubError(.httpStatus, "The server returned HTTP \(http.statusCode).", statusCode: http.statusCode)
            }
            guard data.count <= maximumBytes else {
                throw AppHubError(.archiveTooLarge, "The repository response exceeds the size limit.")
            }
            return HTTPResult(
                data: data,
                statusCode: http.statusCode,
                etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified")
            )
        } catch let error as AppHubError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw AppHubError.cancelled
            case .timedOut:
                throw AppHubError(.timeout, "The request timed out.")
            default:
                throw AppHubError.network(error.localizedDescription)
            }
        } catch {
            throw AppHubError.network(error.localizedDescription)
        }
    }
}

// MARK: - Source fetching

public struct SourceFetchResult: Sendable {
    public let document: SourceDocument
    public let validation: SourceValidation
    public let etag: String?
    public let lastModified: String?
    public let notModified: Bool

    public init(
        document: SourceDocument,
        validation: SourceValidation,
        etag: String?,
        lastModified: String?,
        notModified: Bool
    ) {
        self.document = document
        self.validation = validation
        self.etag = etag
        self.lastModified = lastModified
        self.notModified = notModified
    }
}

public struct SourceFetcher: Sendable {
    private let client: any HTTPFetching

    public init(client: any HTTPFetching = URLSessionHTTPClient()) {
        self.client = client
    }

    public func fetch(url: URL, etag: String?, lastModified: String?) async throws -> SourceFetchResult {
        let result = try await client.fetch(url: url, etag: etag, lastModified: lastModified)
        if result.statusCode == 304 {
            throw SourceFetchError.notModified
        }

        let document: SourceDocument
        do {
            document = try JSONDecoder().decode(SourceDocument.self, from: result.data)
        } catch {
            throw AppHubError.invalidSource("Repository JSON could not be decoded: \(error.localizedDescription)")
        }

        let validation = SourceValidator.validate(document)
        let errors = validation.issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            let summary = errors.prefix(3).map(\.message).joined(separator: " ")
            throw AppHubError.invalidSource("Repository is invalid: \(summary)")
        }

        return SourceFetchResult(
            document: document,
            validation: validation,
            etag: result.etag,
            lastModified: result.lastModified,
            notModified: false
        )
    }
}

public enum SourceFetchError: Error, Sendable, Equatable {
    case notModified
}

// MARK: - Persistence

public struct RepositoryRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var url: String
    public var nameOverride: String?
    public var addedAt: Date
    public var lastFetchedAt: Date?
    public var etag: String?
    public var lastModified: String?
    public var document: SourceDocument?
    public var lastError: String?

    public init(
        id: UUID = UUID(),
        url: String,
        nameOverride: String? = nil,
        addedAt: Date = Date(),
        lastFetchedAt: Date? = nil,
        etag: String? = nil,
        lastModified: String? = nil,
        document: SourceDocument? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.url = url
        self.nameOverride = nameOverride
        self.addedAt = addedAt
        self.lastFetchedAt = lastFetchedAt
        self.etag = etag
        self.lastModified = lastModified
        self.document = document
        self.lastError = lastError
    }

    public var displayName: String {
        nameOverride?.isEmpty == false ? nameOverride! : (document?.name ?? url)
    }

    public var appCount: Int { document?.apps.count ?? 0 }
}

public actor RepositoryService {
    private let paths: AppHubPaths
    private let fetcher: SourceFetcher
    private var records: [RepositoryRecord]?

    public init(paths: AppHubPaths, fetcher: SourceFetcher = SourceFetcher()) {
        self.paths = paths
        self.fetcher = fetcher
    }

    public func list() throws -> [RepositoryRecord] {
        try loadIfNeeded()
        return (records ?? []).sorted { $0.addedAt < $1.addedAt }
    }

    public func record(id: UUID) throws -> RepositoryRecord? {
        try loadIfNeeded()
        return records?.first { $0.id == id }
    }

    @discardableResult
    public func add(urlString: String, name: String? = nil) async throws -> RepositoryRecord {
        try loadIfNeeded()
        guard let url = URLSafety.httpURL(from: urlString) else {
            throw AppHubError(.invalidURL, "Enter a valid http or https repository URL.")
        }
        let normalized = url.absoluteString
        if records?.contains(where: { $0.url == normalized }) == true {
            throw AppHubError(.duplicateSource, "This repository is already added.")
        }

        let result: SourceFetchResult
        do {
            result = try await fetcher.fetch(url: url, etag: nil, lastModified: nil)
        } catch let error as AppHubError {
            throw error
        } catch {
            throw AppHubError.network(error.localizedDescription)
        }

        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = RepositoryRecord(
            url: normalized,
            nameOverride: (trimmedName?.isEmpty ?? true) ? nil : trimmedName,
            lastFetchedAt: Date(),
            etag: result.etag,
            lastModified: result.lastModified,
            document: result.document
        )
        records = (records ?? []) + [record]
        try persist()
        return record
    }

    @discardableResult
    public func refresh(id: UUID) async throws -> RepositoryRecord {
        try loadIfNeeded()
        guard let index = records?.firstIndex(where: { $0.id == id }), let current = records?[index] else {
            throw AppHubError(.notAvailable, "The repository no longer exists.")
        }
        guard let url = URLSafety.httpURL(from: current.url) else {
            throw AppHubError(.invalidURL, "The stored repository URL is invalid.")
        }

        do {
            let result = try await fetcher.fetch(url: url, etag: current.etag, lastModified: current.lastModified)
            var updated = current
            updated.document = result.document
            updated.etag = result.etag ?? current.etag
            updated.lastModified = result.lastModified ?? current.lastModified
            updated.lastFetchedAt = Date()
            updated.lastError = nil
            records?[index] = updated
            try persist()
            return updated
        } catch SourceFetchError.notModified {
            var updated = current
            updated.lastFetchedAt = Date()
            updated.lastError = nil
            records?[index] = updated
            try persist()
            return updated
        } catch {
            var updated = current
            updated.lastError = (error as? AppHubError)?.message ?? error.localizedDescription
            records?[index] = updated
            try persist()
            throw error
        }
    }

    public func remove(id: UUID) throws {
        try loadIfNeeded()
        records?.removeAll { $0.id == id }
        try persist()
    }

    /// Replaces a record in place. Used when cached repository documents are
    /// cleared without deleting the source URL.
    public func replace(_ record: RepositoryRecord) throws {
        try loadIfNeeded()
        guard let index = records?.firstIndex(where: { $0.id == record.id }) else { return }
        records?[index] = record
        try persist()
    }

    public func removeAll() throws {
        records = []
        try persist()
    }

    private var fileURL: URL {
        paths.repositories.appendingPathComponent("sources.json")
    }

    private func loadIfNeeded() throws {
        guard records == nil else { return }
        try paths.prepare()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            records = []
            return
        }
        let data = try FileStore.read(fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            records = try decoder.decode([RepositoryRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records ?? [])
        try FileStore.writeAtomically(data, to: fileURL)
    }
}
