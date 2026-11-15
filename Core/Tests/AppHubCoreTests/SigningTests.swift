import Foundation
import XCTest
@testable import AppHubCore

final class SigningTests: XCTestCase {
    func testParsesProvisioningProfileFixture() throws {
        let profile = try ProvisioningProfileParser.parse(data: Fixtures.data("profile.mobileprovision"))

        XCTAssertEqual(profile.name, "DreamByte Test Profile")
        XCTAssertEqual(profile.teamName, "DreamByte Studios")
        XCTAssertEqual(profile.teamIdentifiers, ["DBYTE12345"])
        XCTAssertEqual(profile.applicationIdentifier, "DBYTE12345.com.dreambyte.testapp")
        XCTAssertEqual(profile.provisionedDeviceCount, 1)
        XCTAssertEqual(profile.kind, .development)
        XCTAssertEqual(profile.entitlements["get-task-allow"], "true")
        XCTAssertEqual(profile.certificates.count, 1)
        XCTAssertFalse(profile.signatureVerified)
        XCTAssertNotNil(profile.expirationDate)
        XCTAssertFalse(profile.isExpired(at: Date(timeIntervalSince1970: 0)))
        XCTAssertTrue(profile.isExpired(at: Date(timeIntervalSince1970: 2_000_000_000)))
    }

    func testEmbeddedPlistRequiresPlist() {
        XCTAssertNil(ProvisioningProfileParser.embeddedPlist(in: Data("garbage".utf8)))
        XCTAssertThrowsError(try ProvisioningProfileParser.parse(data: Data("garbage".utf8))) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, .profileUnreadable)
        }
    }

    func testParsesX509Certificate() throws {
        let summary = try XCTUnwrap(X509CertificateSummary.parse(der: Fixtures.data("cert.der")))
        XCTAssertEqual(summary.commonName, "DreamByte Test Signing")
        XCTAssertEqual(summary.issuerCommonName, "DreamByte Test Signing")
        XCTAssertEqual(summary.serialNumber, "52724fe6c55fd1c378ae24101f23f6b39f9db291")
        XCTAssertEqual(summary.sha256Fingerprint.count, 64)
        XCTAssertNotNil(summary.notBefore)
        XCTAssertNotNil(summary.notAfter)

        let calendar = Calendar(identifier: .gregorian)
        var utc = calendar
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let expiryYear = utc.component(.year, from: try XCTUnwrap(summary.notAfter))
        XCTAssertEqual(expiryYear, 2027)
    }

    func testX509RejectsGarbage() {
        XCTAssertNil(X509CertificateSummary.parse(der: Data("not a certificate".utf8)))
        XCTAssertNil(X509CertificateSummary.parse(der: Data()))
    }

    func testSigningStoreImportPersists() async throws {
        let paths = try temporaryPaths()
        let source = paths.root.appendingPathComponent("profile.mobileprovision")
        try FileStore.writeAtomically(try Fixtures.data("profile.mobileprovision"), to: source)

        let store = SigningStore(paths: paths)
        let record = try await store.importProfile(from: source)
        XCTAssertEqual(record.kind, .provisioningProfile)
        XCTAssertEqual(record.displayName, "DreamByte Test Profile")
        XCTAssertEqual(record.profileKind, .development)
        XCTAssertEqual(record.certificates.count, 1)

        let reopened = SigningStore(paths: paths)
        let records = try await reopened.list()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, record.id)

        try await reopened.remove(id: record.id)
        let empty = try await reopened.list()
        XCTAssertTrue(empty.isEmpty)
    }

    func testSigningStoreRejectsUnreadableFile() async throws {
        let paths = try temporaryPaths()
        let source = paths.root.appendingPathComponent("broken.mobileprovision")
        try FileStore.writeAtomically(Data("nope".utf8), to: source)
        let store = SigningStore(paths: paths)
        do {
            _ = try await store.importProfile(from: source)
            XCTFail("Expected profileUnreadable")
        } catch let error as AppHubError {
            XCTAssertEqual(error.kind, .profileUnreadable)
        }
        let records = try await store.list()
        XCTAssertTrue(records.isEmpty)
    }

    func testCertificateRecordCodableRoundTrip() throws {
        let summary = try XCTUnwrap(X509CertificateSummary.parse(der: Fixtures.data("cert.der")))
        let record = SigningRecord(
            kind: .certificate,
            displayName: summary.commonName ?? "Certificate",
            teamIdentifiers: ["DBYTE12345"],
            expiresAt: summary.notAfter,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000),
            certificates: [summary]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SigningRecord.self, from: encoder.encode(record))
        XCTAssertEqual(decoded, record)
    }
}
