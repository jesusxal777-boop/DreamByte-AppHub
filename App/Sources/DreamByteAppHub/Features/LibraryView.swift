import SwiftUI
import AppHubCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingRemoval: AppPackage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                limitationCard

                if model.packages.isEmpty {
                    EmptyStateView(
                        symbol: "books.vertical",
                        title: model.t(.libraryNoManaged),
                        message: model.t(.ipaEmptyBody)
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(
                            title: model.t(.libraryManaged),
                            subtitle: "\(model.packages.count) · \(Format.bytes(model.packages.reduce(0) { $0 + $1.fileSize }))"
                        )
                        ForEach(model.packages) { package in
                            NavigationLink {
                                IPADetailView(package: package)
                            } label: {
                                LibraryRow(package: package)
                            }
                            .buttonStyle(SoftPressStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingRemoval = package
                                } label: {
                                    Label(model.t(.commonRemove), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.libraryTitle))
        .confirmationDialog(
            model.t(.libraryRemoveTitle),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t(.commonRemove), role: .destructive) {
                if let package = pendingRemoval {
                    Task { await model.delete(package) }
                }
                pendingRemoval = nil
            }
            Button(model.t(.commonCancel), role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(model.t(.libraryRemoveBody))
        }
    }

    private var limitationCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.t(.librarySystemUnavailable), systemImage: "eye.slash")
                    .font(.footnote.weight(.semibold))
                Text(model.t(.librarySystemUnavailableBody))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                    Text("\(model.t(.settingsStorageUsed)): \(Format.bytes(model.storageUsed()))")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let package: AppPackage

    var body: some View {
        GlassPanel(cornerRadius: 20, padding: 12) {
            HStack(spacing: 12) {
                LocalIconView(url: model.iconURL(for: package), size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.inspection?.name ?? package.originalName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(model.t(.libraryInstalledVersion))
                        Text(package.inspection?.version ?? model.t(.libraryUnknownVersion))
                        Text("·")
                        Text(Format.bytes(package.fileSize))
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Text(package.inspection?.bundleIdentifier ?? "—")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    StatusChip(text: model.t(.libraryManaged), tone: .info)
                    Text(Format.date(package.importedAt, locale: model.locale))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
