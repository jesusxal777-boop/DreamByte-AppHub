import SwiftUI
import AppHubCore

/// Lets the user pick an installation strategy per package. Each row states its
/// real availability; nothing pretends to have installed anything. OTA opens the
/// OTA handoff sheet, external export shares the file, and unfinished paths say so.
struct InstallModeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let package: AppPackage

    @State private var showOTA = false

    private var current: AppPackage {
        model.packages.first { $0.id == package.id } ?? package
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(InstallModePlanner.displayOrder) { mode in
                        modeRow(mode)
                    }
                    Text(model.t(.installPickOther))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(model.t(.installChooseMode))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.t(.otaClose)) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showOTA) {
            OTAInstallSheet(package: current)
        }
    }

    private func modeRow(_ mode: InstallMode) -> some View {
        let availability = model.installAvailability(for: mode)
        let preferred = model.installMode == mode

        return GlassPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(model.t(mode.titleKey), systemImage: mode.symbol)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    if preferred {
                        StatusChip(text: model.t(.installPreferred), tone: .info)
                    }
                    Spacer(minLength: 6)
                    StatusChip(text: model.t(availability.statusKey), tone: tone(for: availability))
                }

                Text(model.t(mode.detailKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                action(for: mode, availability: availability)
            }
        }
    }

    @ViewBuilder
    private func action(for mode: InstallMode, availability: InstallModeAvailability) -> some View {
        switch mode {
        case .otaHandoff:
            Button {
                showOTA = true
            } label: {
                Label(model.t(.otaInstallAction), systemImage: "arrow.down.circle")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!availability.isAvailable)

        case .externalTool:
            ShareLink(item: model.packageFileURL(current)) {
                Label(model.t(.installModeExternalDetail), systemImage: "square.and.arrow.up")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .onDeviceSigning:
            if case .needsSigningIdentity = availability {
                Text(model.t(.installImportIdentity))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .deviceBridge:
            EmptyView()
        }
    }

    private func tone(for availability: InstallModeAvailability) -> ChipTone {
        switch availability {
        case .available: .positive
        case .needsSigningIdentity, .needsPairingFile, .needsDeveloperMode: .warning
        case .requiresApplePlatform, .notImplemented: .neutral
        }
    }
}
