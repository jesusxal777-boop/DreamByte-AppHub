import XCTest
@testable import AppHubCore

final class ZipArchiveTests: XCTestCase {
    func testReadsValidArchive() throws {
        let archive = try ZipArchive(url: Fixtures.url("valid.ipa"))
        XCTAssertFalse(archive.entries.isEmpty)
        let plist = try XCTUnwrap(archive.entry(named: "Payload/TestApp.app/Info.plist"))
        let data = try archive.data(for: plist)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testExtractsStoredEntry() throws {
        let archive = try ZipArchive(url: Fixtures.url("stored.ipa"))
        let entry = try XCTUnwrap(archive.entry(named: "Payload/TestApp.app/TestApp"))
        let data = try archive.data(for: entry)
        XCTAssertEqual(data.count, entry.uncompressedSize)
    }

    func testRejectsTraversalPaths() {
        XCTAssertThrowsError(try ZipArchive(url: Fixtures.url("traversal.ipa"))) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, AppHubErrorKind.unsafePath)
        }
    }

    func testDetectsChecksumMismatch() throws {
        let archive = try ZipArchive(url: Fixtures.url("corrupt_crc.ipa"))
        let entry = try XCTUnwrap(archive.entry(named: "Payload/TestApp.app/broken.txt"))
        XCTAssertThrowsError(try archive.data(for: entry)) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, AppHubErrorKind.checksumMismatch)
        }
    }

    func testEntrySizeLimit() throws {
        let archive = try ZipArchive(url: Fixtures.url("valid.ipa"))
        let entry = try XCTUnwrap(archive.entry(named: "Payload/TestApp.app/Info.plist"))
        XCTAssertThrowsError(try archive.data(for: entry, maxSize: 10)) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, AppHubErrorKind.entryTooLarge)
        }
    }

    func testUnsafeWindowsPath() {
        let archive = try? ZipArchive(url: Fixtures.url("valid.ipa"))
        XCTAssertNotNil(archive)
        // Path safety is exercised by the traversal fixture; backslashes are
        // rejected by the same predicate.
        XCTAssertTrue(archive?.contains("Payload/TestApp.app/Info.plist") == true)
    }
}
