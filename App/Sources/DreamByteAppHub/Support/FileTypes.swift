import Foundation
import UniformTypeIdentifiers

/// Content types used by the document pickers. IPAs and provisioning profiles
/// have no system-declared UTType on every OS version, so we fall back to a
/// dynamic type built from the extension.
enum FileTypes {
    static var ipa: UTType {
        UTType(filenameExtension: "ipa") ?? .data
    }

    static var provisioningProfile: UTType {
        UTType(filenameExtension: "mobileprovision") ?? .data
    }

    static var pkcs12: UTType {
        UTType(filenameExtension: "p12") ?? .data
    }

    static var pairingFile: UTType {
        UTType(filenameExtension: "plist") ?? .data
    }

    static var json: UTType { .json }
}
