import Foundation
import XCTest
@testable import AppHubCore

final class SourceModelsTests: XCTestCase {
    private func decode(_ name: String) throws -> SourceDocument {
        let decoder = JSONDecoder()
        return try decoder.decode(SourceDocument.self, from: Fixtures.data(name))
    }

    func testDecodesAltSourceV2Document() throws {
        let document = try decode("source_valid.json")
        XCTAssertEqual(document.name, "DreamByte Test Source")
        XCTAssertEqual(document.identifier, "com.dreambyte.testsource")
        XCTAssertEqual(document.apps.count, 1)

        let app = try XCTUnwrap(document.apps.first)
        XCTAssertEqual(app.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertEqual(app.versions.count, 1)
        XCTAssertEqual(app.latestVersion?.version, "1.2.3")
        XCTAssertEqual(app.latestVersion?.size, 12_345)
        XCTAssertEqual(app.latestVersion?.minOSVersion, "18.0")
        XCTAssertEqual(app.beta, false)
    }

    func testDecodesLegacyFlatVersionFields() throws {
        let document = try decode("source_legacy.json")
        let app = try XCTUnwrap(document.apps.first)
        XCTAssertEqual(app.versions.count, 1)
        XCTAssertEqual(app.versions[0].version, "0.9")
        XCTAssertEqual(app.versions[0].downloadURL, "https://example.com/legacy.ipa")
        XCTAssertEqual(app.versions[0].size, 99)
        XCTAssertEqual(app.versions[0].date, "2025-01-01")
    }

    func testRoundTripsThroughJSON() throws {
        let document = try decode("source_valid.json")
        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(SourceDocument.self, from: encoded)
        XCTAssertEqual(decoded, document)
    }

    func testValidatorRejectsInvalidSource() throws {
        let document = try decode("source_invalid.json")
        let validation = SourceValidator.validate(document)
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains { $0.severity == .error && $0.message.contains("Download URL") })
        XCTAssertTrue(validation.issues.contains { $0.message.contains("Version string") })
        XCTAssertTrue(validation.apps.isEmpty)
    }

    func testValidatorRejectsDuplicateIdentifier() {
        let version = SourceVersion(version: "1.0", downloadURL: "https://example.com/a.ipa")
        let app = SourceApp(name: "App", bundleIdentifier: "com.example.app", versions: [version])
        let document = SourceDocument(
            name: "Duplicate",
            identifier: "com.example.source",
            apps: [app, app]
        )
        let validation = SourceValidator.validate(document)
        XCTAssertFalse(validation.isValid)
        XCTAssertTrue(validation.issues.contains { $0.message.contains("Duplicate") })
        XCTAssertEqual(validation.apps.count, 1)
    }

    func testValidatorAcceptsValidDocument() throws {
        let validation = SourceValidator.validate(try decode("source_valid.json"))
        XCTAssertTrue(validation.isValid)
        XCTAssertEqual(validation.apps.count, 1)
    }

    func testURLSafetyRejectsHostileURLs() {
        XCTAssertNotNil(URLSafety.httpURL(from: "https://example.com/apps.json"))
        XCTAssertNotNil(URLSafety.httpURL(from: "  http://example.com  "))
        XCTAssertNil(URLSafety.httpURL(from: "file:///etc/passwd"))
        XCTAssertNil(URLSafety.httpURL(from: "javascript:alert(1)"))
        XCTAssertNil(URLSafety.httpURL(from: "https://user:secret@example.com/apps.json"))
        XCTAssertNil(URLSafety.httpURL(from: "not a url"))
    }

    func testVersionCompatibilityComparison() {
        let version = SourceVersion(version: "1.0", downloadURL: "https://example.com/a.ipa", minOSVersion: "18.0")
        XCTAssertTrue(version.isCompatible(withOSVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 0, patchVersion: 0)))
        XCTAssertTrue(version.isCompatible(withOSVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 0)))
        XCTAssertFalse(version.isCompatible(withOSVersion: OperatingSystemVersion(majorVersion: 17, minorVersion: 6, patchVersion: 0)))

        let capped = SourceVersion(
            version: "1.0",
            downloadURL: "https://example.com/a.ipa",
            maxOSVersion: "18.5"
        )
        XCTAssertTrue(capped.isCompatible(withOSVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 4, patchVersion: 0)))
        XCTAssertFalse(capped.isCompatible(withOSVersion: OperatingSystemVersion(majorVersion: 18, minorVersion: 6, patchVersion: 0)))
    }
}
