import Foundation
import XCTest
@testable import AppHubCore

actor MockHTTPClient: HTTPFetching {
    enum Behavior: Sendable {
        case respond(data: Data, statusCode: Int, etag: String?)
        case notModified
    }

    private var behavior: Behavior
    private(set) var requests: [(url: String, etag: String?, lastModified: String?)] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func set(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func fetch(url: URL, etag: String?, lastModified: String?) async throws -> HTTPResult {
        requests.append((url.absoluteString, etag, lastModified))
        switch behavior {
        case let .respond(data, statusCode, responseETag):
            return HTTPResult(data: data, statusCode: statusCode, etag: responseETag, lastModified: nil)
        case .notModified:
            return HTTPResult(data: Data(), statusCode: 304)
        }
    }
}

final class RepositoryServiceTests: XCTestCase {
    private func makeService(
        paths: AppHubPaths,
        behavior: MockHTTPClient.Behavior
    ) -> (RepositoryService, MockHTTPClient, SourceFetcher) {
        let client = MockHTTPClient(behavior: behavior)
        let fetcher = SourceFetcher(client: client)
        return (RepositoryService(paths: paths, fetcher: fetcher), client, fetcher)
    }

    func testAddPersistsRepository() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_valid.json")
        let (service, _, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: "W/\"1\""))

        let record = try await service.add(urlString: "https://example.com/apps.json")
        XCTAssertEqual(record.appCount, 1)
        XCTAssertEqual(record.etag, "W/\"1\"")
        XCTAssertEqual(record.displayName, "DreamByte Test Source")

        let listed = try await service.list()
        XCTAssertEqual(listed.count, 1)

        // A fresh instance must see the same record from disk.
        let reopened = RepositoryService(paths: paths, fetcher: SourceFetcher(client: MockHTTPClient(behavior: .notModified)))
        let restored = try await reopened.list()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].document?.apps.count, 1)
    }

    func testAddRejectsDuplicateURL() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_valid.json")
        let (service, _, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: nil))
        _ = try await service.add(urlString: "https://example.com/apps.json")

        do {
            _ = try await service.add(urlString: "https://example.com/apps.json")
            XCTFail("Expected duplicateSource")
        } catch let error as AppHubError {
            XCTAssertEqual(error.kind, .duplicateSource)
        }
    }

    func testAddRejectsNonHTTPURL() async throws {
        let paths = try temporaryPaths()
        let (service, _, _) = makeService(paths: paths, behavior: .respond(data: Data(), statusCode: 200, etag: nil))
        do {
            _ = try await service.add(urlString: "file:///etc/passwd")
            XCTFail("Expected invalidURL")
        } catch let error as AppHubError {
            XCTAssertEqual(error.kind, .invalidURL)
        }
    }

    func testFetcherRejectsMalformedJSON() async throws {
        let paths = try temporaryPaths()
        let (service, _, _) = makeService(
            paths: paths,
            behavior: .respond(data: Data("{\"name\":42}".utf8), statusCode: 200, etag: nil)
        )
        do {
            _ = try await service.add(urlString: "https://example.com/broken.json")
            XCTFail("Expected invalidSource")
        } catch let error as AppHubError {
            XCTAssertEqual(error.kind, .invalidSource)
        }
        let listed = try await service.list()
        XCTAssertTrue(listed.isEmpty)
    }

    func testFetcherRejectsInvalidSourceContent() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_invalid.json")
        let (service, _, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: nil))
        do {
            _ = try await service.add(urlString: "https://example.com/invalid.json")
            XCTFail("Expected invalidSource")
        } catch let error as AppHubError {
            XCTAssertEqual(error.kind, .invalidSource)
        }
    }

    func testRefreshHandlesNotModified() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_valid.json")
        let (service, client, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: "abc"))
        let record = try await service.add(urlString: "https://example.com/apps.json")

        await client.set(.notModified)
        let refreshed = try await service.refresh(id: record.id)
        XCTAssertEqual(refreshed.document?.apps.count, 1)
        XCTAssertEqual(refreshed.etag, "abc")
        XCTAssertNotNil(refreshed.lastFetchedAt)

        let requests = await client.requests
        XCTAssertEqual(requests.last?.etag, "abc")
    }

    func testRefreshUpdatesDocumentAndRecordsError() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_valid.json")
        let (service, client, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: nil))
        let record = try await service.add(urlString: "https://example.com/apps.json")

        let legacy = try Fixtures.data("source_legacy.json")
        await client.set(.respond(data: legacy, statusCode: 200, etag: nil))
        let refreshed = try await service.refresh(id: record.id)
        XCTAssertEqual(refreshed.document?.name, "Legacy Source")

        await client.set(.respond(data: Data("nope".utf8), statusCode: 200, etag: nil))
        do {
            _ = try await service.refresh(id: record.id)
            XCTFail("Expected invalidSource")
        } catch {
            // expected
        }
        let stored = try await service.record(id: record.id)
        XCTAssertNotNil(stored?.lastError)
        // The previous good document survives a failed refresh.
        XCTAssertEqual(stored?.document?.name, "Legacy Source")
    }

    func testRemoveAllClearsPersistence() async throws {
        let paths = try temporaryPaths()
        let data = try Fixtures.data("source_valid.json")
        let (service, _, _) = makeService(paths: paths, behavior: .respond(data: data, statusCode: 200, etag: nil))
        _ = try await service.add(urlString: "https://example.com/apps.json")
        try await service.removeAll()

        let reopened = RepositoryService(paths: paths)
        let listed = try await reopened.list()
        XCTAssertTrue(listed.isEmpty)
    }

    func testCorruptPersistenceFallsBackToEmpty() async throws {
        let paths = try temporaryPaths()
        try FileStore.writeAtomically(Data("not json".utf8), to: paths.repositories.appendingPathComponent("sources.json"))
        let service = RepositoryService(paths: paths)
        let listed = try await service.list()
        XCTAssertTrue(listed.isEmpty)
    }
}
