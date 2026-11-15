#if os(iOS)
import Foundation
import Security
import AppHubCore

/// Imports a PKCS#12 identity into the iOS keychain and returns a metadata
/// record. The password is used once for `SecPKCS12Import` and is never stored.
/// The private key only ever lives inside the keychain.
enum P12Importer {
    /// Label used when listing/removing imported identities.
    static let keychainLabel = "DreamByte AppHub identity"

    static func importIdentity(from url: URL, password: String) throws -> SigningRecord {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppHubError.fileRead("The .p12 file could not be read.")
        }

        var rawItems: CFArray?
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        let status = SecPKCS12Import(data as CFData, options, &rawItems)
        guard status == errSecSuccess else {
            throw AppHubError(.certificateUnreadable, message(for: status))
        }
        guard let items = rawItems as? [[String: Any]], !items.isEmpty else {
            throw AppHubError(.certificateUnreadable, "The .p12 contains no identity.")
        }
        guard let rawIdentity = items[0][kSecImportItemIdentity as String] else {
            throw AppHubError(.certificateUnreadable, "The .p12 contains no private key identity.")
        }
        let identity = rawIdentity as! SecIdentity

        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
              let certificate else {
            throw AppHubError(.certificateUnreadable, "The identity has no certificate.")
        }

        try store(identity: identity, certificate: certificate)

        let der = SecCertificateCopyData(certificate) as Data
        let summary = X509CertificateSummary.parse(der: der)
        let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? "—"

        return SigningRecord(
            kind: .certificate,
            displayName: summary?.commonName ?? subject,
            teamName: nil,
            teamIdentifiers: [],
            applicationIdentifier: nil,
            profileKind: nil,
            createdAt: summary?.notBefore,
            expiresAt: summary?.notAfter,
            entitlements: [:],
            certificates: summary.map { [$0] } ?? [],
            signatureVerified: false,
            sourceFileName: url.lastPathComponent
        )
    }

    /// Adds the identity label so Settings can show what AppHub created. A
    /// duplicate is treated as already imported, never as a failure.
    private static func store(identity: SecIdentity, certificate: SecCertificate) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecValueRef as String: identity,
            kSecAttrLabel as String: keychainLabel
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw AppHubError(.certificateUnreadable, message(for: status))
        }
    }

    static func importedIdentityCount() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return 0
        }
        return items.count
    }

    static func removeImportedIdentities() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: keychainLabel
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func message(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return message
        }
        return "Keychain error \(status)."
    }
}
#endif
