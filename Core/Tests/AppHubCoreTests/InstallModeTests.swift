import Foundation
import XCTest
@testable import AppHubCore

final class InstallModeTests: XCTestCase {
    private func capabilities(
        apple: Bool = true,
        identity: Bool = false,
        pairing: Bool = false,
        developerMode: Bool? = true,
        pipelineReady: Bool = true
    ) -> InstallCapabilities {
        InstallCapabilities(
            isOnApplePlatform: apple,
            hasSigningIdentity: identity,
            hasPairingFile: pairing,
            hasDeveloperMode: developerMode,
            iosMajorVersion: 18,
            signingPipelineReady: pipelineReady
        )
    }

    func testOTAAndExternalWorkOnApplePlatforms() {
        let caps = capabilities()
        XCTAssertEqual(InstallModePlanner.availability(of: .otaHandoff, capabilities: caps), .available)
        XCTAssertEqual(InstallModePlanner.availability(of: .externalTool, capabilities: caps), .available)
        XCTAssertEqual(InstallModePlanner.recommendedMode(for: caps), .otaHandoff)
    }

    func testEverythingAppleOnlyNeedsApplePlatform() {
        let caps = capabilities(apple: false)
        XCTAssertEqual(
            InstallModePlanner.availability(of: .otaHandoff, capabilities: caps),
            .requiresApplePlatform
        )
        XCTAssertEqual(
            InstallModePlanner.availability(of: .onDeviceSigning, capabilities: caps),
            .requiresApplePlatform
        )
        XCTAssertEqual(
            InstallModePlanner.availability(of: .deviceBridge, capabilities: caps),
            .requiresApplePlatform
        )
        XCTAssertEqual(InstallModePlanner.availableModes(for: caps), [.externalTool])
    }

    func testSigningNeedsIdentityThenPipeline() {
        XCTAssertEqual(
            InstallModePlanner.availability(of: .onDeviceSigning, capabilities: capabilities()),
            .needsSigningIdentity
        )
        XCTAssertEqual(
            InstallModePlanner.availability(
                of: .onDeviceSigning,
                capabilities: capabilities(identity: true, pipelineReady: false)
            ),
            .notImplemented("Local re-signing is not finished; export the IPA or use OTA.")
        )
        XCTAssertEqual(
            InstallModePlanner.availability(
                of: .onDeviceSigning,
                capabilities: capabilities(identity: true)
            ),
            .available
        )
    }

    func testBridgeNeedsPairingAndDeveloperMode() {
        XCTAssertEqual(
            InstallModePlanner.availability(of: .deviceBridge, capabilities: capabilities()),
            .needsPairingFile
        )
        XCTAssertEqual(
            InstallModePlanner.availability(
                of: .deviceBridge,
                capabilities: capabilities(pairing: true, developerMode: false)
            ),
            .needsDeveloperMode
        )
        XCTAssertFalse(
            InstallModePlanner.availability(
                of: .deviceBridge,
                capabilities: capabilities(pairing: true)
            ).isAvailable
        )
    }

    func testAvailableModesAreOrderedAndNeverEmpty() {
        let empty = capabilities(apple: false)
        XCTAssertEqual(InstallModePlanner.availableModes(for: empty), [.externalTool])
        XCTAssertEqual(InstallModePlanner.recommendedMode(for: empty), .externalTool)

        let everything = capabilities(identity: true, pairing: true)
        XCTAssertEqual(
            InstallModePlanner.availableModes(for: everything),
            [.otaHandoff, .onDeviceSigning, .externalTool]
        )
    }

    func testModeRawValuesAreStableForPersistence() {
        XCTAssertEqual(
            InstallMode.allCases.map(\.rawValue),
            ["otaHandoff", "onDeviceSigning", "deviceBridge", "externalTool"]
        )
        XCTAssertEqual(InstallMode(rawValue: "otaHandoff"), .otaHandoff)
    }
}
