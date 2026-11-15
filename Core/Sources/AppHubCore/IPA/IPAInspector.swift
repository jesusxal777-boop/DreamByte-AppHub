import Foundation

public enum InspectionWarning: String, Codable, Sendable, CaseIterable {
    case unsigned
    case encrypted
    case missingProvisioningProfile
    case noArm64Slice
    case unknownArchitecture
    case missingIcon
    case missingMinimumOS
}

public struct IPAInspection: Codable, Sendable, Equatable {
    public var bundleIdentifier: String
    public var name: String
    public var version: String
    public var build: String
    public var minimumOSVersion: String?
    public var supportedPlatforms: [String]
    public var executableName: String?
    public var architectures: [CPUArchitecture]
    public var isEncrypted: Bool
    public var hasCodeSignature: Bool
    public var hasProvisioningProfile: Bool
    public var fileSize: Int64
    public var iconEntryName: String?
    public var warnings: [InspectionWarning]
    public var inspectedAt: Date

    public init(
        bundleIdentifier: String,
        name: String,
        version: String,
        build: String,
        minimumOSVersion: String?,
        supportedPlatforms: [String],
        executableName: String?,
        architectures: [CPUArchitecture],
        isEncrypted: Bool,
        hasCodeSignature: Bool,
        hasProvisioningProfile: Bool,
        fileSize: Int64,
        iconEntryName: String?,
        warnings: [InspectionWarning],
        inspectedAt: Date = Date()
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.build = build
        self.minimumOSVersion = minimumOSVersion
        self.supportedPlatforms = supportedPlatforms
        self.executableName = executableName
        self.architectures = architectures
        self.isEncrypted = isEncrypted
        self.hasCodeSignature = hasCodeSignature
        self.hasProvisioningProfile = hasProvisioningProfile
        self.fileSize = fileSize
        self.iconEntryName = iconEntryName
        self.warnings = warnings
        self.inspectedAt = inspectedAt
    }

    public var supportsDevice: Bool {
        architectures.contains(where: \.isDeviceNative)
    }

    public var architectureSummary: String {
        architectures.isEmpty ? "—" : architectures.map(\.displayName).joined(separator: ", ")
    }
}

public struct IPAResult: Sendable {
    public let inspection: IPAInspection
    public let iconData: Data?

    public init(inspection: IPAInspection, iconData: Data?) {
        self.inspection = inspection
        self.iconData = iconData
    }
}

/// Reads an IPA's metadata without extracting or executing it.
public struct IPAInspector: Sendable {
    public let url: URL
    public let limits: ZipLimits

    public init(url: URL, limits: ZipLimits = .default) {
        self.url = url
        self.limits = limits
    }

    public func inspect() throws -> IPAResult {
        let archive = try ZipArchive(url: url, limits: limits)
        let fileSize = (try? FileStore.size(of: url)) ?? 0

        let plistEntries = archive.entries.filter { entry in
            let components = entry.name.split(separator: "/", omittingEmptySubsequences: false)
            return components.count == 3
                && components[0] == "Payload"
                && components[1].hasSuffix(".app")
                && components[2] == "Info.plist"
        }

        guard !plistEntries.isEmpty else {
            let hasPayload = archive.entries.contains { $0.name.hasPrefix("Payload/") }
            throw AppHubError(
                hasPayload ? .missingInfoPlist : .missingPayload,
                hasPayload ? "The archive has no app Info.plist." : "The archive has no Payload folder."
            )
        }
        guard plistEntries.count == 1, let plistEntry = plistEntries.first else {
            throw AppHubError(.multipleAppBundles, "The archive contains more than one application bundle.")
        }

        let appPrefix = String(plistEntry.name.dropLast("Info.plist".count))
        let plistData = try archive.data(for: plistEntry, maxSize: 8 << 20)

        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
            )
        } catch {
            throw AppHubError(.invalidInfoPlist, "Info.plist could not be parsed: \(error.localizedDescription)")
        }
        guard let info = propertyList as? [String: Any] else {
            throw AppHubError(.invalidInfoPlist, "Info.plist root is not a dictionary.")
        }

        guard let bundleIdentifier = (info["CFBundleIdentifier"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty else {
            throw AppHubError(.missingBundleIdentifier, "Info.plist has no CFBundleIdentifier.")
        }

        let executableName = info["CFBundleExecutable"] as? String
        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleIdentifier
        let shortVersion = (info["CFBundleShortVersionString"] as? String) ?? "—"
        let build = (info["CFBundleVersion"] as? String) ?? "—"
        let minimumOS = info["MinimumOSVersion"] as? String
        let platforms = (info["CFBundleSupportedPlatforms"] as? [String]) ?? []

        var architectures: [CPUArchitecture] = []
        var isEncrypted = false
        var executableFound = false

        if let executableName, !executableName.isEmpty {
            let executablePath = appPrefix + executableName
            if let entry = archive.entry(named: executablePath) {
                executableFound = true
                let headerLimit = min(entry.uncompressedSize, 4 << 20)
                if let header = try? archive.data(for: entry, maxSize: headerLimit),
                   let machO = MachOParser.parse(header) {
                    architectures = machO.architectures
                    isEncrypted = machO.isEncrypted
                }
            }
        }

        guard executableFound else {
            throw AppHubError(
                .missingExecutable,
                "The app executable \(executableName ?? "(unnamed)") was not found."
            )
        }

        let codeSignature = archive.contains(appPrefix + "_CodeSignature/CodeResources")
        let provisioningProfile = archive.contains(appPrefix + "embedded.mobileprovision")

        let icon = bestIconEntry(in: archive, info: info, appPrefix: appPrefix)
        let iconData = icon.flatMap { try? archive.data(for: $0, maxSize: 4 << 20) }

        var warnings: [InspectionWarning] = []
        if !codeSignature { warnings.append(.unsigned) }
        if isEncrypted { warnings.append(.encrypted) }
        if !provisioningProfile { warnings.append(.missingProvisioningProfile) }
        if !architectures.contains(where: \.isDeviceNative) { warnings.append(.noArm64Slice) }
        if architectures.contains(.unknown) { warnings.append(.unknownArchitecture) }
        if icon == nil { warnings.append(.missingIcon) }
        if minimumOS == nil { warnings.append(.missingMinimumOS) }

        let inspection = IPAInspection(
            bundleIdentifier: bundleIdentifier,
            name: displayName,
            version: shortVersion,
            build: build,
            minimumOSVersion: minimumOS,
            supportedPlatforms: platforms,
            executableName: executableName,
            architectures: architectures,
            isEncrypted: isEncrypted,
            hasCodeSignature: codeSignature,
            hasProvisioningProfile: provisioningProfile,
            fileSize: fileSize,
            iconEntryName: icon?.name,
            warnings: warnings
        )

        return IPAResult(inspection: inspection, iconData: iconData)
    }

    private func bestIconEntry(in archive: ZipArchive, info: [String: Any], appPrefix: String) -> ZipEntry? {
        var names: [String] = []

        if let icons = info["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files.reversed())
        }
        if let icons = info["CFBundleIcons~ipad"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            names.append(contentsOf: files.reversed())
        }
        if let file = info["CFBundleIconFile"] as? String {
            names.append(file)
        }

        for name in names {
            guard !name.isEmpty, !name.contains("/"), !name.contains("..") else { continue }
            let candidates = [
                appPrefix + name,
                appPrefix + name + ".png",
                appPrefix + name + "@2x.png",
                appPrefix + name + "@3x.png"
            ]
            for candidate in candidates {
                if let entry = archive.entry(named: candidate), !entry.isDirectory {
                    return entry
                }
            }
        }
        return nil
    }
}
