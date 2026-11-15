import SwiftUI
import AppHubCore
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var showResetLibrary = false
    @State private var showClearCaches = false
    @State private var showClearDownloads = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languageCard
                appearanceCard
                installModeCard
                storageCard
                brandingCard
                aboutCard
                dangerZone
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.settingsTitle))
        .confirmationDialog(
            model.t(.settingsResetLibrary),
            isPresented: $showResetLibrary,
            titleVisibility: .visible
        ) {
            Button(model.t(.commonDelete), role: .destructive) {
                Task { await model.resetLibrary() }
            }
            Button(model.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(model.t(.settingsResetLibraryBody))
        }
        .confirmationDialog(
            model.t(.settingsClearCache),
            isPresented: $showClearCaches,
            titleVisibility: .visible
        ) {
            Button(model.t(.commonConfirm)) {
                Task { await model.clearCaches() }
            }
            Button(model.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(model.t(.settingsClearCacheBody))
        }
        .confirmationDialog(
            model.t(.settingsClearDownloads),
            isPresented: $showClearDownloads,
            titleVisibility: .visible
        ) {
            Button(model.t(.commonConfirm)) {
                model.clearCompletedDownloads()
            }
            Button(model.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(model.t(.settingsClearDownloadsBody))
        }
    }

    // MARK: Language

    private var languageCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.settingsLanguage), subtitle: model.t(.settingsLanguageBody))

                Picker(model.t(.settingsLanguage), selection: Binding(
                    get: { model.language },
                    set: { model.language = $0 }
                )) {
                    ForEach(model.catalog.availableLanguages) { language in
                        Text(language.endonym).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .appHubMaterial(cornerRadius: 12)

                Button {
                    model.useSystemLanguage()
                } label: {
                    Label(model.t(.settingsSystemDefault), systemImage: "globe")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.palette.secondary)
            }
        }
    }

    // MARK: Appearance

    private var appearanceCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.settingsTheme))
                Picker(model.t(.settingsTheme), selection: Binding(
                    get: { model.appearance },
                    set: { model.appearance = $0 }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                        Text(model.t(mode.titleKey)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    // MARK: Installation

    private var installModeCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(
                    title: model.t(.installPreferred),
                    subtitle: model.t(.installPreferredFooter)
                )
                Picker(model.t(.installPreferred), selection: Binding(
                    get: { model.installMode },
                    set: { model.installMode = $0 }
                )) {
                    ForEach(InstallModePlanner.displayOrder) { mode in
                        Label(model.t(mode.titleKey), systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .appHubMaterial(cornerRadius: 12)

                ForEach(InstallModePlanner.displayOrder) { mode in
                    let availability = model.installAvailability(for: mode)
                    HStack(spacing: 8) {
                        Image(systemName: mode.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(model.t(mode.titleKey))
                            .font(.caption)
                        Spacer(minLength: 6)
                        StatusChip(
                            text: model.t(availability.statusKey),
                            tone: tone(for: availability)
                        )
                    }
                }
            }
        }
    }

    private func tone(for availability: InstallModeAvailability) -> ChipTone {
        switch availability {
        case .available: .positive
        case .needsSigningIdentity, .needsPairingFile, .needsDeveloperMode: .warning
        case .requiresApplePlatform, .notImplemented: .neutral
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.settingsDataManagement))
                InfoRow(label: model.t(.settingsStorageUsed), value: Format.bytes(model.storageUsed()), monospaced: true)
                InfoRow(
                    label: model.t(.dashboardIpasCard),
                    value: "\(model.packages.count) · \(Format.bytes(model.packages.reduce(0) { $0 + $1.fileSize }))"
                )
                InfoRow(
                    label: model.t(.dashboardDownloadsCard),
                    value: "\(model.downloads.count)"
                )
                InfoRow(
                    label: model.t(.reposTitle),
                    value: "\(model.repositories.count)"
                )

                HStack(spacing: 8) {
                    Button(model.t(.settingsClearCache)) { showClearCaches = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(model.t(.settingsClearDownloads)) { showClearDownloads = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: Branding

    private var brandingCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: model.t(.settingsBranding))
                    Spacer(minLength: 0)
                    if model.theme.isPlaceholder {
                        StatusChip(text: model.t(.settingsTemporaryBranding), tone: .info, symbol: "sparkles")
                    }
                }

                HStack(spacing: 12) {
                    BrandMarkView(theme: model.theme, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.theme.displayName)
                            .font(.footnote.weight(.semibold))
                        Text(model.theme.wordmarkText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    colorSwatch(model.theme.primaryHex)
                    colorSwatch(model.theme.secondaryHex)
                    colorSwatch(model.theme.accentHex)
                }

                if model.theme.isPlaceholder {
                    Text(model.t(.settingsBrandingPlaceholder))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func colorSwatch(_ hex: String) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(BrandColor.color(hex: hex))
            .frame(width: 26, height: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.7)
            }
            .accessibilityLabel(hex)
    }

    // MARK: About

    private var aboutCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.settingsAbout))
                InfoRow(label: model.t(.settingsVersion), value: DeviceInfo.appVersion, monospaced: true)
                InfoRow(label: model.t(.settingsBuildLabel), value: DeviceInfo.appBuild, monospaced: true)
                InfoRow(label: model.t(.settingsMadeBy), value: model.theme.displayName)
                Text(model.t(.settingsAppDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    NavigationLink {
                        TextPageView(
                            title: model.t(.settingsLicenses),
                            bodyText: model.t(.settingsLicensesBody)
                        )
                    } label: {
                        settingsRow(model.t(.settingsLicenses), symbol: "doc.text")
                    }
                    Divider()
                    NavigationLink {
                        TextPageView(
                            title: model.t(.settingsPrivacy),
                            bodyText: model.t(.settingsPrivacyBody)
                        )
                    } label: {
                        settingsRow(model.t(.settingsPrivacy), symbol: "hand.raised")
                    }
                    Divider()
                    NavigationLink {
                        TextPageView(
                            title: model.t(.settingsLegal),
                            bodyText: model.t(.settingsLegalBody)
                        )
                    } label: {
                        settingsRow(model.t(.settingsLegal), symbol: "text.book.closed")
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func settingsRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .font(.footnote)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    // MARK: Danger

    private var dangerZone: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.settingsDangerZone))
                Button(role: .destructive) {
                    showResetLibrary = true
                } label: {
                    Label(model.t(.settingsResetLibrary), systemImage: "trash")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text(model.t(.settingsResetLibraryBody))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TextPageView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let bodyText: String

    var body: some View {
        ScrollView {
            GlassPanel(cornerRadius: 22, padding: 18) {
                Text(bodyText)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
