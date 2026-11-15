import Foundation

/// The installation strategies AppHub can offer. Every mode is explicit about
/// what it needs, and none reports success on its own: OTA and the device bridge
/// are executed by iOS, signing only produces a signed package.
public enum InstallMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Hand a signed IPA to iOS through an HTTPS manifest + `itms-services://`.
    case otaHandoff
    /// Re-sign locally with an imported identity, then install by another mode.
    case onDeviceSigning
    /// Talk to `installation_proxy` through a pairing file and loopback bridge.
    case deviceBridge
    /// Share/export to AltStore, SideStore, Xcode, or another tool.
    case externalTool

    public var id: String { rawValue }
}

/// Facts the planner needs. The app fills these from the real device/state; tests
/// fill them explicitly, so availability logic is deterministic and testable.
public struct InstallCapabilities: Sendable, Equatable {
    public var isOnApplePlatform: Bool
    public var hasSigningIdentity: Bool
    public var hasPairingFile: Bool
    public var hasDeveloperMode: Bool?
    public var iosMajorVersion: Int?
    public var signingPipelineReady: Bool

    public init(
        isOnApplePlatform: Bool,
        hasSigningIdentity: Bool = false,
        hasPairingFile: Bool = false,
        hasDeveloperMode: Bool? = nil,
        iosMajorVersion: Int? = nil,
        signingPipelineReady: Bool = false
    ) {
        self.isOnApplePlatform = isOnApplePlatform
        self.hasSigningIdentity = hasSigningIdentity
        self.hasPairingFile = hasPairingFile
        self.hasDeveloperMode = hasDeveloperMode
        self.iosMajorVersion = iosMajorVersion
        self.signingPipelineReady = signingPipelineReady
    }
}

public enum InstallModeAvailability: Sendable, Equatable {
    case available
    case needsSigningIdentity
    case needsPairingFile
    case needsDeveloperMode
    case requiresApplePlatform
    case notImplemented(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum InstallModePlanner {
    /// Availability is ordered from the most direct to the most manual path.
    public static let displayOrder: [InstallMode] = [
        .otaHandoff,
        .onDeviceSigning,
        .deviceBridge,
        .externalTool
    ]

    public static func availability(
        of mode: InstallMode,
        capabilities: InstallCapabilities
    ) -> InstallModeAvailability {
        guard mode != .externalTool else { return .available }

        switch mode {
        case .externalTool:
            return .available

        case .otaHandoff:
            guard capabilities.isOnApplePlatform else { return .requiresApplePlatform }
            return .available

        case .onDeviceSigning:
            guard capabilities.isOnApplePlatform else { return .requiresApplePlatform }
            guard capabilities.hasSigningIdentity else { return .needsSigningIdentity }
            guard capabilities.signingPipelineReady else {
                return .notImplemented("Local re-signing is not finished; export the IPA or use OTA.")
            }
            return .available

        case .deviceBridge:
            guard capabilities.isOnApplePlatform else { return .requiresApplePlatform }
            guard capabilities.hasPairingFile else { return .needsPairingFile }
            if capabilities.hasDeveloperMode == false { return .needsDeveloperMode }
            return .notImplemented("The installation_proxy bridge is not implemented yet.")
        }
    }

    /// Modes that can be used right now, in display order.
    public static func availableModes(
        for capabilities: InstallCapabilities
    ) -> [InstallMode] {
        displayOrder.filter { availability(of: $0, capabilities: capabilities).isAvailable }
    }

    /// The best mode the user can use now, falling back to export.
    public static func recommendedMode(
        for capabilities: InstallCapabilities
    ) -> InstallMode {
        availableModes(for: capabilities).first ?? .externalTool
    }
}
