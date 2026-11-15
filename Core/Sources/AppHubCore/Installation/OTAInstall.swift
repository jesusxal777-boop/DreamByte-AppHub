import Foundation

/// A single-app OTA installation manifest (the format iOS expects when it
/// receives an `itms-services://?action=download-manifest&url=…` link).
///
/// iOS performs the installation; the app only prepares or forwards the
/// manifest URL. The IPA must already be signed (enterprise, ad-hoc, or
/// development) and reachable over HTTPS.
public struct OTAInstallManifest: Sendable, Equatable {
    public let title: String
    public let bundleIdentifier: String
    public let bundleVersion: String
    public let ipaURL: URL
    public let displayImageURL: URL?
    public let fullSizeImageURL: URL?

    public init(
        title: String,
        bundleIdentifier: String,
        bundleVersion: String,
        ipaURL: URL,
        displayImageURL: URL? = nil,
        fullSizeImageURL: URL? = nil
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw AppHubError(.validationFailed, "The manifest needs a display title.")
        }
        guard Self.isValidBundleIdentifier(bundleIdentifier) else {
            throw AppHubError(.validationFailed, "The manifest bundle identifier is invalid.")
        }
        guard !bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppHubError(.validationFailed, "The manifest needs a bundle version.")
        }
        guard Self.isHTTPS(ipaURL) else {
            throw AppHubError(.validationFailed, "The IPA URL must be HTTPS.")
        }
        if let displayImageURL, !Self.isHTTPS(displayImageURL) {
            throw AppHubError(.validationFailed, "The display image URL must be HTTPS.")
        }
        if let fullSizeImageURL, !Self.isHTTPS(fullSizeImageURL) {
            throw AppHubError(.validationFailed, "The full-size image URL must be HTTPS.")
        }

        self.title = trimmedTitle
        self.bundleIdentifier = bundleIdentifier
        self.bundleVersion = bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ipaURL = ipaURL
        self.displayImageURL = displayImageURL
        self.fullSizeImageURL = fullSizeImageURL
    }

    /// Builds a manifest from an inspected, stored IPA. The IPA URL is the
    /// public HTTPS location the user uploaded the signed file to.
    public init(
        package: AppPackage,
        ipaURL: URL,
        inspection: IPAInspection? = nil
    ) throws {
        let details = inspection ?? package.inspection
        guard let details else {
            throw AppHubError(.validationFailed, "Inspect the IPA before building a manifest.")
        }
        try self.init(
            title: details.name,
            bundleIdentifier: details.bundleIdentifier,
            bundleVersion: details.version,
            ipaURL: ipaURL
        )
    }

    /// The manifest as an XML property list (`manifest.plist`).
    public func plistData() throws -> Data {
        var assets: [[String: Any]] = [
            ["kind": "software-package", "url": ipaURL.absoluteString]
        ]
        if let displayImageURL {
            assets.append([
                "kind": "display-image",
                "needs-shine": false,
                "url": displayImageURL.absoluteString
            ])
        }
        if let fullSizeImageURL {
            assets.append([
                "kind": "full-size-image",
                "needs-shine": false,
                "url": fullSizeImageURL.absoluteString
            ])
        }

        let item: [String: Any] = [
            "assets": assets,
            "metadata": [
                "bundle-identifier": bundleIdentifier,
                "bundle-version": bundleVersion,
                "kind": "software",
                "title": title
            ]
        ]
        let root: [String: Any] = ["items": [item]]

        do {
            return try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .xml,
                options: 0
            )
        } catch {
            throw AppHubError.fileWrite("Could not encode the manifest: \(error.localizedDescription)")
        }
    }

    /// Writes `manifest.plist` into a directory and returns the file URL.
    public func writeManifest(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("manifest.plist")
        try FileStore.writeAtomically(try plistData(), to: url)
        return url
    }

    static func isValidBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains(".") else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    static func isHTTPS(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }
}

public enum OTAInstall {
    /// Turns an HTTPS manifest URL into the `itms-services://` link iOS opens.
    public static func itmsServicesURL(manifestURL: URL) -> URL? {
        guard OTAInstallManifest.isHTTPS(manifestURL) else { return nil }
        let encoded = percentEncode(manifestURL.absoluteString)
        return URL(string: "itms-services://?action=download-manifest&url=\(encoded)")
    }

    /// Accepts either an `itms-services://` link or an HTTPS manifest URL and
    /// returns the manifest URL inside it. `nil` for anything else, including
    /// plain HTTP.
    public static func manifestURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        if scheme == "https" {
            return OTAInstallManifest.isHTTPS(url) ? url : nil
        }
        guard scheme == "itms-services" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard items.contains(where: { $0.name == "action" && $0.value == "download-manifest" }) else {
            return nil
        }
        guard let raw = items.first(where: { $0.name == "url" })?.value,
              let manifest = URL(string: raw),
              OTAInstallManifest.isHTTPS(manifest) else {
            return nil
        }
        return manifest
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
