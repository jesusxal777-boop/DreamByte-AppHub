import XCTest
@testable import AppHubCore

final class IPAInspectorTests: XCTestCase {
    func testInspectsValidIPA() throws {
        let result = try IPAInspector(url: Fixtures.url("valid.ipa")).inspect()
        let inspection = result.inspection

        XCTAssertEqual(inspection.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertEqual(inspection.name, "Test App")
        XCTAssertEqual(inspection.version, "1.2.3")
        XCTAssertEqual(inspection.build, "42")
        XCTAssertEqual(inspection.minimumOSVersion, "18.0")
        XCTAssertEqual(inspection.architectures, [.arm64])
        XCTAssertFalse(inspection.isEncrypted)
        XCTAssertTrue(inspection.hasCodeSignature)
        XCTAssertTrue(inspection.hasProvisioningProfile)
        XCTAssertTrue(inspection.supportsDevice)
        XCTAssertNotNil(result.iconData)
        XCTAssertFalse(inspection.warnings.contains(.unsigned))
        XCTAssertFalse(inspection.warnings.contains(.encrypted))
    }

    func testReadsBinaryInfoPlist() throws {
        let inspection = try IPAInspector(url: Fixtures.url("binary_plist.ipa")).inspect().inspection
        XCTAssertEqual(inspection.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertEqual(inspection.version, "1.2.3")
    }

    func testDetectsFairPlayEncryption() throws {
        let inspection = try IPAInspector(url: Fixtures.url("encrypted.ipa")).inspect().inspection
        XCTAssertTrue(inspection.isEncrypted)
        XCTAssertTrue(inspection.warnings.contains(.encrypted))
    }

    func testDetectsUnsignedPackage() throws {
        let inspection = try IPAInspector(url: Fixtures.url("unsigned.ipa")).inspect().inspection
        XCTAssertFalse(inspection.hasCodeSignature)
        XCTAssertFalse(inspection.hasProvisioningProfile)
        XCTAssertTrue(inspection.warnings.contains(.unsigned))
        XCTAssertTrue(inspection.warnings.contains(.missingProvisioningProfile))
    }

    func testMissingPayloadFailsClearly() {
        XCTAssertThrowsError(try IPAInspector(url: Fixtures.url("no_payload.ipa")).inspect()) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, AppHubErrorKind.missingPayload)
        }
    }

    func testRejectsTraversalDuringInspection() {
        XCTAssertThrowsError(try IPAInspector(url: Fixtures.url("traversal.ipa")).inspect()) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, AppHubErrorKind.unsafePath)
        }
    }

    func testMachOParserRejectsGarbage() {
        XCTAssertNil(MachOParser.parse(Data("not a mach-o binary".utf8)))
    }
}
