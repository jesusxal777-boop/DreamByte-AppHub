import Foundation
import XCTest
@testable import AppHubCore

final class IPAImportPreflightTests: XCTestCase {
    private func makeFile(named name: String, bytes: Int = 16) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPAImportPreflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 0x50, count: bytes).write(to: url)
        return url
    }

    func testAcceptsIPAWithContent() throws {
        let url = try makeFile(named: "Example.ipa")
        XCTAssertEqual(IPAImportPreflight.check(url), .ready)
    }

    func testAcceptsUppercaseExtension() throws {
        let url = try makeFile(named: "Example.IPA")
        XCTAssertEqual(IPAImportPreflight.check(url), .ready)
    }

    func testRejectsOtherExtensions() throws {
        let url = try makeFile(named: "Example.zip")
        XCTAssertEqual(IPAImportPreflight.check(url), .wrongExtension)
    }

    func testRejectsMissingFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Missing-\(UUID().uuidString).ipa")
        XCTAssertEqual(IPAImportPreflight.check(url), .notAFile)
    }

    func testRejectsDirectoryWithIPAName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Folder-\(UUID().uuidString).ipa", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertEqual(IPAImportPreflight.check(directory), .notAFile)
    }

    func testRejectsEmptyFile() throws {
        let url = try makeFile(named: "Empty.ipa", bytes: 0)
        XCTAssertEqual(IPAImportPreflight.check(url), .emptyFile)
    }
}
