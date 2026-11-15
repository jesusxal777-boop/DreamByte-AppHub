import Foundation
import XCTest
@testable import AppHubCore

final class AppPackageStoreTests: XCTestCase {
    func testImportStoresFileAndInspection() async throws {
        let paths = try temporaryPaths()
        let store = AppPackageStore(paths: paths)

        let package = try await store.importPackage(from: Fixtures.url("valid.ipa"))
        XCTAssertEqual(package.originalName, "valid.ipa")
        XCTAssertEqual(package.inspection?.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertNil(package.failure)
        XCTAssertTrue(package.quarantined)
        XCTAssertGreaterThan(package.fileSize, 0)

        let storedURL = await store.packageURL(for: package)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertEqual(try Data(contentsOf: storedURL), try Fixtures.data("valid.ipa"))

        let iconURL = await store.iconURL(for: package)
        XCTAssertNotNil(iconURL)
        XCTAssertTrue(try FileManager.default.fileExists(atPath: XCTUnwrap(iconURL).path))

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        let total = try await store.totalBytes()
        XCTAssertEqual(total, package.fileSize)
    }

    func testImportRecordsFailureWithoutLosingFile() async throws {
        let paths = try temporaryPaths()
        let store = AppPackageStore(paths: paths)

        let package = try await store.importPackage(from: Fixtures.url("no_payload.ipa"))
        XCTAssertNil(package.inspection)
        XCTAssertEqual(package.failure?.kind, .missingPayload)
        let storedURL = await store.packageURL(for: package)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        let all = try await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].failure?.kind, .missingPayload)
    }

    func testRenameAndDelete() async throws {
        let paths = try temporaryPaths()
        let store = AppPackageStore(paths: paths)
        let package = try await store.importPackage(from: Fixtures.url("valid.ipa"))

        try await store.rename(package, to: "  Renamed App  ")
        let renamed = try await store.all()
        XCTAssertEqual(renamed.first?.originalName, "Renamed App")

        let storedURL = await store.packageURL(for: package)
        try await store.delete(package)
        let remaining = try await store.all()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedURL.path))
    }

    func testPersistenceSurvivesNewInstance() async throws {
        let paths = try temporaryPaths()
        let first = AppPackageStore(paths: paths)
        let package = try await first.importPackage(from: Fixtures.url("unsigned.ipa"))

        let second = AppPackageStore(paths: paths)
        let restored = try await second.all()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, package.id)
        XCTAssertEqual(restored[0].inspection?.hasCodeSignature, false)
    }

    func testCorruptIndexDoesNotCrash() async throws {
        let paths = try temporaryPaths()
        try FileStore.writeAtomically(Data("{".utf8), to: paths.libraryFile)
        let store = AppPackageStore(paths: paths)
        let all = try await store.all()
        XCTAssertTrue(all.isEmpty)
    }
}
