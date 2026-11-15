import SwiftUI
import AppHubCore

struct IPALibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var showImporter = false

    private var filtered: [AppPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return model.packages }
        return model.packages.filter { package in
            package.originalName.localizedCaseInsensitiveContains(trimmed)
                || (package.inspection?.name.localizedCaseInsensitiveContains(trimmed) ?? false)
                || (package.inspection?.bundleIdentifier.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: model.t(.ipaEmptyTitle),
                        message: model.t(.ipaEmptyBody),
                        actionTitle: model.t(.ipaImport),
                        action: { showImporter = true }
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(filtered) { package in
                        NavigationLink {
                            IPADetailView(package: package)
                        } label: {
                            IPARow(package: package)
                        }
                        .buttonStyle(SoftPressStyle())
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.ipaTitle))
        .searchable(text: $query, prompt: Text(model.t(.commonSearch)))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showImporter = true
                } label: {
                    Label(model.t(.ipaImport), systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [FileTypes.ipa],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await model.importIPA(from: url) }
        }
    }
}

struct IPARow: View {
    @Environment(AppModel.self) private var model
    let package: AppPackage

    var body: some View {
        GlassPanel(cornerRadius: 20, padding: 12) {
            HStack(spacing: 12) {
                LocalIconView(url: model.iconURL(for: package), size: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(package.inspection?.name ?? package.originalName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(package.inspection?.bundleIdentifier ?? package.failure?.message ?? model.t(.ipaCorrupted))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let inspection = package.inspection {
                            Text(inspection.version)
                            Text("·")
                            Text(Format.bytes(package.fileSize))
                            if inspection.isEncrypted {
                                StatusChip(text: model.t(.ipaEncrypted), tone: .warning)
                            }
                        } else {
                            StatusChip(text: model.t(.ipaCorrupted), tone: .negative)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct IPADetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let package: AppPackage

    @State private var showRename = false
    @State private var showDelete = false
    @State private var showInstall = false
    @State private var newName = ""

    private var current: AppPackage {
        model.packages.first { $0.id == package.id } ?? package
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actions
                if let inspection = current.inspection {
                    metadata(inspection)
                    warnings(inspection)
                } else if let failure = current.failure {
                    failurePanel(failure)
                }
                installNotice
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(current.inspection?.name ?? current.originalName)
        .navigationBarTitleDisplayMode(.inline)
        .alert(model.t(.commonEdit), isPresented: $showRename) {
            TextField(model.t(.commonName), text: $newName)
            Button(model.t(.commonCancel), role: .cancel) {}
            Button(model.t(.commonSave)) {
                Task { await model.rename(current, to: newName) }
            }
        }
        .confirmationDialog(
            model.t(.ipaDeleteTitle),
            isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button(model.t(.commonDelete), role: .destructive) {
                Task {
                    await model.delete(current)
                    dismiss()
                }
            }
            Button(model.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(model.t(.ipaDeleteBody))
        }
        .sheet(isPresented: $showInstall) {
            InstallModeSheet(package: current)
        }
    }

    private var header: some View {
        GlassPanel(cornerRadius: 26, padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                LocalIconView(url: model.iconURL(for: current), size: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text(current.inspection?.name ?? current.originalName)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(current.inspection?.bundleIdentifier ?? "—")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let inspection = current.inspection {
                            StatusChip(
                                text: inspection.isEncrypted ? model.t(.ipaEncrypted) : model.t(.ipaNotEncrypted),
                                tone: inspection.isEncrypted ? .warning : .positive,
                                symbol: inspection.isEncrypted ? "lock.fill" : "lock.open"
                            )
                            StatusChip(
                                text: inspection.hasCodeSignature ? model.t(.ipaSigned) : model.t(.ipaUnsigned),
                                tone: inspection.hasCodeSignature ? .positive : .warning,
                                symbol: inspection.hasCodeSignature ? "checkmark.seal.fill" : "exclamationmark.seal"
                            )
                        } else {
                            StatusChip(text: model.t(.ipaCorrupted), tone: .negative)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            ShareLink(item: model.packageFileURL(current)) {
                Label(model.t(.ipaShareIPA), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Task { await model.rescan(current) }
            } label: {
                Label(model.t(.ipaRescan), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Menu {
                Button {
                    newName = current.originalName
                    showRename = true
                } label: {
                    Label(model.t(.commonEdit), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label(model.t(.commonDelete), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel(model.t(.commonActions))
        }
    }

    private func metadata(_ inspection: IPAInspection) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.ipaMetadata))
                InfoRow(label: model.t(.ipaVersionLabel), value: inspection.version)
                InfoRow(label: model.t(.ipaBuild), value: inspection.build)
                InfoRow(label: model.t(.ipaMinOS), value: inspection.minimumOSVersion ?? model.t(.commonUnknown))
                InfoRow(label: model.t(.ipaArchitectures), value: inspection.architectureSummary)
                InfoRow(label: model.t(.ipaExecutable), value: inspection.executableName ?? "—", monospaced: true)
                InfoRow(label: model.t(.ipaFileSize), value: Format.bytes(current.fileSize))
                InfoRow(label: model.t(.ipaOriginalName), value: current.originalName)
                InfoRow(label: model.t(.ipaImportedAt), value: Format.dateTime(current.importedAt, locale: model.locale))
                InfoRow(label: model.t(.ipaSignature), value: inspection.hasCodeSignature ? model.t(.ipaSigned) : model.t(.ipaUnsigned))
                InfoRow(
                    label: model.t(.certsProfileType),
                    value: inspection.hasProvisioningProfile ? model.t(.commonYes) : model.t(.ipaNoProfile)
                )
            }
        }
    }

    private func warnings(_ inspection: IPAInspection) -> some View {
        Group {
            if inspection.warnings.isEmpty {
                GlassPanel(cornerRadius: 20, padding: 14) {
                    Label(model.t(.ipaNoWarnings), systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                GlassPanel(cornerRadius: 22, padding: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: model.t(.ipaWarnings))
                        ForEach(inspection.warnings, id: \.rawValue) { warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .padding(.top, 1)
                                Text(model.warningText(warning))
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func failurePanel(_ failure: PackageFailure) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.ipaInspectionFailed))
                Text(failure.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var installNotice: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label(model.t(.ipaInstallUnavailableTitle), systemImage: "iphone.slash")
                    .font(.footnote.weight(.semibold))
                Text(model.t(.ipaInstallUnavailableBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showInstall = true
                } label: {
                    Label(model.t(.installTitle), systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(current.inspection == nil)
                Text(model.t(.ipaQuarantinedNote))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
