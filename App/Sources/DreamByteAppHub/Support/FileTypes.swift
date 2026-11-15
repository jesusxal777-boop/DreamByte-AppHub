import Foundation
import UniformTypeIdentifiers

/// Content types used by the document pickers.
///
/// `.ipa` is declared as an imported type in `Info.plist`
/// (`com.dreambyte.apphub.ipa`). When the declaration is present, `UTType(_:)`
/// resolves it and Files can match it against real `.ipa` files. If the app is
/// built without that plist (SwiftPM previews, tests), we fall back to the
/// dynamic type for the extension.
///
/// The picker variants also include `.data`. Files on iOS sometimes reports an
/// `.ipa` as generic data or a ZIP archive, and a strict filter greys the file
/// out so it cannot be selected. Import always validates the extension itself,
/// so a broader picker is safe and much less frustrating.
enum FileTypes {
    static let ipaIdentifier = "com.dreambyte.apphub.ipa"

    static var ipa: UTType {
        if let declared = UTType(ipaIdentifier) { return declared }
        return UTType(filenameExtension: "ipa") ?? .data
    }

    static var ipaImportTypes: [UTType] {
        var types: [UTType] = [.data]
        if ipa != .data { types.insert(ipa, at: 0) }
        return types
    }

    static var provisioningProfile: UTType {
        UTType(filenameExtension: "mobileprovision") ?? .data
    }

    static var provisioningImportTypes: [UTType] {
        var types: [UTType] = [.data]
        if provisioningProfile != .data { types.insert(provisioningProfile, at: 0) }
        return types
    }

    static var pkcs12: UTType {
        UTType(filenameExtension: "p12") ?? .data
    }

    static var pkcs12ImportTypes: [UTType] {
        var types: [UTType] = [.data]
        if pkcs12 != .data { types.insert(pkcs12, at: 0) }
        return types
    }

    static var pairingFile: UTType {
        UTType(filenameExtension: "plist") ?? .data
    }

    static var pairingImportTypes: [UTType] {
        var types: [UTType] = [.data]
        if pairingFile != .data { types.insert(pairingFile, at: 0) }
        return types
    }

    static var json: UTType { .json }
}
