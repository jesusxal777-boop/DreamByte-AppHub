import Foundation
import XCTest
@testable import AppHubCore

final class OTAInstallTests: XCTestCase {
    private func makeManifest(
        title: String = "Test App",
        bundleIdentifier: String = "com.dreambyte.testapp",
        version: String = "1.2.3"
    ) throws -> OTAInstallManifest {
        try OTAInstallManifest(
            title: title,
            bundleIdentifier: bundleIdentifier,
            bundleVersion: version,
            ipaURL: try XCTUnwrap(URL(string: "https://cdn.example.com/TestApp.ipa")),
            displayImageURL: URL(string: "https://cdn.example.com/icon.png")
        )
    }

    func testManifestPlistHasAppleShape() throws {
        let manifest = try makeManifest()
        let data = try manifest.plistData()
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let root = try XCTUnwrap(object as? [String: Any])
        let items = try XCTUnwrap(root["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        let assets = try XCTUnwrap(item["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 2)
        XCTAssertEqual(assets[0]["kind"] as? String, "software-package")
        XCTAssertEqual(assets[0]["url"] as? String, "https://cdn.example.com/TestApp.ipa")
        XCTAssertEqual(assets[1]["kind"] as? String, "display-image")

        let metadata = try XCTUnwrap(item["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["bundle-identifier"] as? String, "com.dreambyte.testapp")
        XCTAssertEqual(metadata["bundle-version"] as? String, "1.2.3")
        XCTAssertEqual(metadata["kind"] as? String, "software")
        XCTAssertEqual(metadata["title"] as? String, "Test App")
    }

    func testManifestEscapesTitleAndOmitsMissingIcons() throws {
        let manifest = try OTAInstallManifest(
            title: "Fish & Chips <beta>",
            bundleIdentifier: "com.example.app",
            bundleVersion: "2.0",
            ipaURL: try XCTUnwrap(URL(string: "https://example.com/a.ipa"))
        )
        let data = try manifest.plistData()
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let item = try XCTUnwrap((object as? [String: Any])?["items"] as? [[String: Any]]).first
        let assets = try XCTUnwrap(item?["assets"] as? [[String: Any]])
        XCTAssertEqual(assets.count, 1)
        let metadata = try XCTUnwrap(item?["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["title"] as? String, "Fish & Chips <beta>")
    }

    func testRejectsInsecureOrInvalidManifest() throws {
        let httpURL = try XCTUnwrap(URL(string: "http://example.com/a.ipa"))
        XCTAssertThrowsError(
            try OTAInstallManifest(
                title: "App",
                bundleIdentifier: "com.example.app",
                bundleVersion: "1.0",
                ipaURL: httpURL
            )
        ) { error in
            XCTAssertEqual((error as? AppHubError)?.kind, .validationFailed)
        }

        XCTAssertThrowsError(
            try OTAInstallManifest(
                title: "   ",
                bundleIdentifier: "com.example.app",
                bundleVersion: "1.0",
                ipaURL: try XCTUnwrap(URL(string: "https://example.com/a.ipa"))
            )
        )
        XCTAssertThrowsError(
            try OTAInstallManifest(
                title: "App",
                bundleIdentifier: "not-a-bundle-id",
                bundleVersion: "1.0",
                ipaURL: try XCTUnwrap(URL(string: "https://example.com/a.ipa"))
            )
        )
        XCTAssertThrowsError(
            try OTAInstallManifest(
                title: "App",
                bundleIdentifier: "com.example.app",
                bundleVersion: "",
                ipaURL: try XCTUnwrap(URL(string: "https://example.com/a.ipa"))
            )
        )
    }

    func testItmsLinkRoundTrips() throws {
        let manifestURL = try XCTUnwrap(URL(string: "https://cdn.example.com/path/manifest.plist?token=a%20b&x=1"))
        let itms = try XCTUnwrap(OTAInstall.itmsServicesURL(manifestURL: manifestURL))
        XCTAssertEqual(itms.scheme, "itms-services")
        XCTAssertTrue(itms.absoluteString.contains("action=download-manifest"))
        XCTAssertFalse(itms.absoluteString.contains(" "))

        let extracted = try XCTUnwrap(OTAInstall.manifestURL(from: itms.absoluteString))
        XCTAssertEqual(extracted.host, "cdn.example.com")
        XCTAssertEqual(extracted.path, "/path/manifest.plist")
    }

    func testAcceptsPlainHTTPSManifestAndRejectsOthers() throws {
        XCTAssertNotNil(OTAInstall.manifestURL(from: "https://example.com/manifest.plist"))
        XCTAssertNil(OTAInstall.manifestURL(from: "http://example.com/manifest.plist"))
        XCTAssertNil(OTAInstall.manifestURL(from: "itms-services://?action=download-manifest&url=http%3A%2F%2Fexample.com%2Fm.plist"))
        XCTAssertNil(OTAInstall.manifestURL(from: "itms-services://?action=install&url=https%3A%2F%2Fexample.com%2Fm.plist"))
        XCTAssertNil(OTAInstall.manifestURL(from: "https://"))
        XCTAssertNil(OTAInstall.manifestURL(from: "not a url"))
        XCTAssertNil(OTAInstall.manifestURL(from: ""))
    }

    func testWritesManifestFile() throws {
        let paths = try temporaryPaths()
        let manifest = try makeManifest()
        let url = try manifest.writeManifest(in: paths.exports)
        XCTAssertEqual(url.lastPathComponent, "manifest.plist")
        XCTAssertEqual(try Data(contentsOf: url), try manifest.plistData())
    }

    func testManifestFromInspectedPackage() throws {
        let inspection = IPAInspection(
            bundleIdentifier: "com.dreambyte.testapp",
            name: "Fixture App",
            version: "1.2.3",
            build: "45",
            minimumOSVersion: "18.0",
            supportedPlatforms: ["iPhoneOS"],
            executableName: "TestApp",
            architectures: [.arm64],
            isEncrypted: false,
            hasCodeSignature: true,
            hasProvisioningProfile: true,
            fileSize: 1024,
            iconEntryName: nil,
            warnings: []
        )
        let package = AppPackage(
            originalName: "Fixture.ipa",
            storedFileName: "fixture.ipa",
            fileSize: 1024,
            inspection: inspection
        )
        let manifest = try OTAInstallManifest(
            package: package,
            ipaURL: try XCTUnwrap(URL(string: "https://example.com/Fixture.ipa"))
        )
        XCTAssertEqual(manifest.title, "Fixture App")
        XCTAssertEqual(manifest.bundleIdentifier, "com.dreambyte.testapp")
        XCTAssertEqual(manifest.bundleVersion, "1.2.3")

        let uninspected = AppPackage(
            originalName: "Broken.ipa",
            storedFileName: "broken.ipa",
            fileSize: 10,
            inspection: nil
        )
        XCTAssertThrowsError(
            try OTAInstallManifest(
                package: uninspected,
                ipaURL: try XCTUnwrap(URL(string: "https://example.com/Broken.ipa"))
            )
        )
    }
}
