import Foundation
import XCTest
@testable import AppHubCore

final class DownloadTests: XCTestCase {
    func testValidatorAcceptsMatchingPackage() throws {
        let url = Fixtures.url("valid.ipa")
        let validation = try DownloadValidator.validate(
            fileURL: url,
            expectedSize: try FileStore.size(of: url),
            expectedSHA256: nil,
            expectedBundleIdentifier: "com.dreambyte.testapp",
            expectedVersion: "1.2.3"
        )
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.sha256?.count, 64)
        XCTAssertEqual(validation.inspection?.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertTrue(validation.notes.contains { $0.contains("SHA-256") })
    }

    func testValidatorRejectsBundleMismatch() {
        XCTAssertThrowsError(
            try DownloadValidator.validate(
                fileURL: Fixtures.url("valid.ipa"),
                expectedSize: nil,
                expectedSHA256: nil,
                expectedBundleIdentifier: "com.example.other",
                expectedVersion: nil
            )
        ) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, .validationFailed)
        }
    }

    func testValidatorRejectsSizeMismatch() {
        XCTAssertThrowsError(
            try DownloadValidator.validate(
                fileURL: Fixtures.url("valid.ipa"),
                expectedSize: 1,
                expectedSHA256: nil,
                expectedBundleIdentifier: "com.dreambyte.testapp",
                expectedVersion: nil
            )
        ) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, .validationFailed)
        }
    }

    func testValidatorRejectsChecksumMismatch() {
        let bogus = String(repeating: "a", count: 64)
        XCTAssertThrowsError(
            try DownloadValidator.validate(
                fileURL: Fixtures.url("valid.ipa"),
                expectedSize: nil,
                expectedSHA256: bogus,
                expectedBundleIdentifier: "com.dreambyte.testapp",
                expectedVersion: nil
            )
        ) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, .validationFailed)
        }
    }

    func testDownloadJobProgressMath() {
        var job = DownloadJob(
            appName: "App",
            bundleIdentifier: "com.example.app",
            version: "1.0",
            downloadURL: "https://example.com/a.ipa",
            sourceName: "Source",
            fileName: "a.ipa"
        )
        XCTAssertEqual(job.fraction, 0)
        job.bytesReceived = 50
        job.totalBytes = 200
        XCTAssertEqual(job.fraction, 0.25, accuracy: 0.0001)
        XCTAssertTrue(job.isActive)
        job.state = .completed
        XCTAssertFalse(job.isActive)
    }

    func testDownloadServicePersistsAndResetsStaleJobs() async throws {
        let paths = try temporaryPaths()
        // Seed the store through a persisted file and verify the stale-job
        // recovery path without touching the network.
        let stale = DownloadJob(
            appName: "Stale",
            bundleIdentifier: "com.example.stale",
            version: "1.0",
            downloadURL: "https://example.com/stale.ipa",
            sourceName: "Source",
            fileName: "stale.ipa",
            bytesReceived: 10,
            totalBytes: 100,
            state: .downloading
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileStore.writeAtomically(
            try encoder.encode([stale]),
            to: paths.downloads.appendingPathComponent("downloads.json")
        )

        let reopened = DownloadService(paths: paths)
        let jobs = try await reopened.list()
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].state, .failed)
        XCTAssertEqual(jobs[0].errorMessage, "Interrupted by app restart.")
    }

    func testEndToEndDownloadAndValidation() async throws {
        let server = try LocalHTTPServer(body: try Fixtures.data("valid.ipa"))
        server.start()
        defer { server.stop() }
        try await Task.sleep(nanoseconds: 80_000_000)

        let paths = try temporaryPaths()
        let service = DownloadService(paths: paths)
        let app = makeApp(url: server.baseURL + "valid.ipa")
        let version = try XCTUnwrap(app.versions.first)

        let started = try await service.start(app: app, version: version, sourceName: "Local fixture")
        XCTAssertEqual(started.state, .waiting)

        var finished: DownloadJob?
        for _ in 0..<400 {
            let current = try await service.job(id: started.id)
            if let current, !current.isActive {
                finished = current
                break
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        let job = try XCTUnwrap(finished, "Download did not finish in time")
        XCTAssertEqual(job.state, .completed, job.errorMessage ?? "")
        XCTAssertEqual(job.sha256?.count, 64)
        XCTAssertGreaterThan(job.bytesReceived, 0)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: service.fileURL(for: job).path))
    }

    private func makeApp(url: String) -> SourceApp {
        SourceApp(
            name: "Test App",
            bundleIdentifier: "com.dreambyte.testapp",
            versions: [SourceVersion(version: "1.2.3", downloadURL: url)]
        )
    }
}
