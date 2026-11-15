import SwiftUI
import AppHubCore

/// OTA installation handoff. AppHub either forwards an existing
/// `itms-services://` link to iOS or generates a `manifest.plist` for an IPA the
/// user hosts over HTTPS. Signing and hosting stay with the user; iOS performs
/// the installation and AppHub never claims it succeeded.
struct OTAInstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let package: AppPackage

    @State private var linkText = ""
    @State private var ipaURLText = ""
    @State private var generatedManifest: URL?
    @State private var message: String?

    private var current: AppPackage {
        model.packages.first { $0.id == package.id } ?? package
    }

    private var manifestURL: URL? {
        OTAInstall.manifestURL(from: linkText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    linkSection
                    manifestSection
                    requirements
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(model.t(.otaTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.t(.otaClose)) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var intro: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(current.inspection?.name ?? current.originalName)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Text(model.t(.otaIntro))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var linkSection: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.otaLinkSection))
                TextField(model.t(.otaLinkPlaceholder), text: $linkText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote.monospaced())

                if !linkText.isEmpty, manifestURL == nil {
                    Text(model.t(.otaInvalidLink))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openInstallLink()
                } label: {
                    Label(model.t(.otaOpen), systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(manifestURL == nil)
            }
        }
    }

    private var manifestSection: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.otaManifestSection))
                TextField(model.t(.otaIpaPlaceholder), text: $ipaURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .font(.footnote.monospaced())

                Button {
                    generateManifest()
                } label: {
                    Label(model.t(.otaGenerate), systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(ipaURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let generatedManifest {
                    ShareLink(item: generatedManifest) {
                        Label(model.t(.otaGenerated), systemImage: "square.and.arrow.up")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var requirements: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.t(.otaRequirementsTitle), systemImage: "checklist")
                    .font(.footnote.weight(.semibold))
                Text(model.t(.otaRequirementsBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.t(.otaNoSigningBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.t(.otaUnconfirmed))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openInstallLink() {
        guard let manifestURL,
              let itms = OTAInstall.itmsServicesURL(manifestURL: manifestURL) else {
            message = model.t(.otaInvalidLink)
            return
        }
        message = nil
        openURL(itms)
    }

    private func generateManifest() {
        message = nil
        generatedManifest = nil
        let trimmed = ipaURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ipaURL = URL(string: trimmed) else {
            message = model.t(.otaInvalidLink)
            return
        }
        do {
            let manifest = try OTAInstallManifest(package: current, ipaURL: ipaURL)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppHubOTA", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            generatedManifest = try manifest.writeManifest(in: directory)
        } catch {
            message = model.errorText(error)
        }
    }
}
