import Foundation
import XCTest
@testable import AppHubCore

final class BrandingTests: XCTestCase {
    func testPlaceholderThemeIsMarkedPlaceholder() {
        let theme = BrandTheme.placeholder
        XCTAssertTrue(theme.isPlaceholder)
        XCTAssertEqual(theme.logoAssetName, "BrandMarkPlaceholder")
        XCTAssertTrue(theme.usesLiquidGlass)
        XCTAssertTrue(BrandTheme.isValidHex(theme.primaryHex))
        XCTAssertTrue(BrandTheme.isValidHex(theme.secondaryHex))
        XCTAssertTrue(BrandTheme.isValidHex(theme.accentHex))
    }

    func testHexValidation() {
        XCTAssertTrue(BrandTheme.isValidHex("#0A1A33"))
        XCTAssertTrue(BrandTheme.isValidHex("0A1A33"))
        XCTAssertTrue(BrandTheme.isValidHex("#0A1A33FF"))
        XCTAssertFalse(BrandTheme.isValidHex("#0A1A3"))
        XCTAssertFalse(BrandTheme.isValidHex("ZZZZZZ"))
        XCTAssertFalse(BrandTheme.isValidHex(""))
    }

    func testOverridesApplyAndClamp() {
        var overrides = BrandOverrides()
        overrides.displayName = "DreamByte"
        overrides.primaryHex = "#123456"
        overrides.accentHex = "not-a-color"
        overrides.cornerRadius = 200
        overrides.isPlaceholder = false
        let theme = overrides.applied()
        XCTAssertEqual(theme.displayName, "DreamByte")
        XCTAssertEqual(theme.primaryHex, "#123456")
        XCTAssertEqual(theme.accentHex, BrandTheme.placeholder.accentHex)
        XCTAssertEqual(theme.cornerRadius, BrandTheme.placeholder.cornerRadius)
        XCTAssertFalse(theme.isPlaceholder)
    }

    func testLoaderReadsJSONAndFallsBack() throws {
        let paths = try temporaryPaths()
        let good = paths.root.appendingPathComponent("branding.json")
        try FileStore.writeAtomically(Data(##"{"wordmarkText":"DB","primaryHex":"#FF0000"}"##.utf8), to: good)
        let loaded = BrandLoader.load(from: good)
        XCTAssertEqual(loaded.wordmarkText, "DB")
        XCTAssertEqual(loaded.primaryHex, "#FF0000")
        XCTAssertEqual(loaded.displayName, BrandTheme.placeholder.displayName)

        let bad = paths.root.appendingPathComponent("bad.json")
        try FileStore.writeAtomically(Data("not json".utf8), to: bad)
        XCTAssertEqual(BrandLoader.load(from: bad), BrandTheme.placeholder)
        XCTAssertEqual(BrandLoader.load(from: paths.root.appendingPathComponent("missing.json")), BrandTheme.placeholder)
    }
}

final class DiagnosticsTests: XCTestCase {
    private func makeReport() -> DiagnosticReport {
        DiagnosticReport(
            environment: DiagnosticEnvironment(
                appVersion: "1.0",
                appBuild: "1",
                osName: "iOS",
                osVersion: "26.0",
                deviceModel: "iPhone",
                localeIdentifier: "es_ES",
                interfaceLanguage: "es",
                isDevelopmentBuild: true
            ),
            modules: [DiagnosticModule(name: "IPA engine", status: "ok", detail: "tested")],
            counts: ["ipas": 2],
            notes: ["Report generated locally."]
        )
    }

    func testEncodeProducesStableJSON() throws {
        let data = try DiagnosticBuilder.encode(makeReport())
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(object["environment"])
        let modules = try XCTUnwrap(object["modules"] as? [[String: Any]])
        XCTAssertEqual(modules.first?["name"] as? String, "IPA engine")
    }

    func testRedactionRemovesFileSystemPaths() {
        XCTAssertEqual(DiagnosticBuilder.redact("/Users/alice/Library/AppHub/file.ipa"), "<path>")
        XCTAssertEqual(DiagnosticBuilder.redact("saved at /var/mobile/Containers/Data/app.json now"), "saved at <path> now")
        XCTAssertEqual(DiagnosticBuilder.redact("C:\\Users\\alice\\AppHub"), "<path>")
        XCTAssertEqual(DiagnosticBuilder.redact("no paths here"), "no paths here")
    }

    func testShareTextIsRedactedAndValidJSON() throws {
        var report = makeReport()
        report.notes = ["path /home/ubuntu/secret/pairing.plist"]
        let text = try DiagnosticBuilder.shareText(report)
        XCTAssertFalse(text.contains("/home/ubuntu/secret"))
        XCTAssertTrue(text.contains("<path>"))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(text.utf8)))
    }
}

final class JITTests: XCTestCase {
    func testHandoffURLCarriesBundleAndPID() throws {
        let url = try XCTUnwrap(StikDebugHandoff.enableJITURL(bundleIdentifier: "com.dreambyte.app", processIdentifier: 4242))
        XCTAssertEqual(url.scheme, "stikdebug")
        XCTAssertEqual(url.host, "enable-jit")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["bundle-id"], "com.dreambyte.app")
        XCTAssertEqual(items["pid"], "4242")
        XCTAssertNil(items["script-name"])
    }

    func testHandoffURLRejectsInvalidInput() {
        XCTAssertNil(StikDebugHandoff.enableJITURL(bundleIdentifier: "", processIdentifier: 10))
        XCTAssertNil(StikDebugHandoff.enableJITURL(bundleIdentifier: "com.example.app", processIdentifier: 0))
        XCTAssertNil(StikDebugHandoff.enableJITURL(bundleIdentifier: "com.example.app", processIdentifier: -5))
    }

    func testHandoffURLEscapesScriptValues() throws {
        let url = try XCTUnwrap(
            StikDebugHandoff.enableJITURL(
                bundleIdentifier: "com.example.app",
                processIdentifier: 1,
                scriptName: "universal.js"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertTrue(components.queryItems?.contains { $0.name == "script-name" && $0.value == "universal.js" } == true)
    }

    func testReadinessMatrix() {
        let ready = JITPrerequisites(systemVersion: "26.0", hasGetTaskAllow: true, pairingFilePresent: true, stikDebugInstalled: true, isTXMPresent: true)
        XCTAssertEqual(ready.readiness, .ready)

        var setup = ready
        setup.stikDebugInstalled = false
        XCTAssertEqual(setup.readiness, .requiresSetup)

        var unavailable = ready
        unavailable.hasGetTaskAllow = false
        XCTAssertEqual(unavailable.readiness, .unavailable)

        var unknown = ready
        unknown.hasGetTaskAllow = nil
        XCTAssertEqual(unknown.readiness, .unknown)
    }

    func testPairingFileValidation() throws {
        let plist: [String: Any] = [
            "UDID": "00008110-001234567890001E",
            "DeviceCertificate": Data([0x01, 0x02])
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        XCTAssertTrue(PairingFileImporter.validate(data: data))
        XCTAssertFalse(PairingFileImporter.validate(data: Data("nope".utf8)))
        XCTAssertFalse(PairingFileImporter.validate(data: Data()))
        XCTAssertFalse(PairingFileImporter.validate(data: Data(repeating: 0, count: (2 << 20) + 1)))
    }

    func testBuiltInJITIsReportedUnavailable() {
        XCTAssertFalse(JITMethod.builtIn.isAvailableInThisBuild)
        XCTAssertTrue(JITMethod.stikDebug.isAvailableInThisBuild)
        XCTAssertTrue(JITMethod.waitForDebugger.isAvailableInThisBuild)
    }
}
