import SwiftUI
import AppHubCore

struct RepositoriesView: View {
    @Environment(AppModel.self) private var model
    @State private var showAdd = false
    @State private var pendingRemoval: RepositoryRecord?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.repositories.isEmpty {
                    EmptyStateView(
                        symbol: "square.stack.3d.up",
                        title: model.t(.reposEmptyTitle),
                        message: model.t(.reposEmptyBody),
                        actionTitle: model.t(.reposAddAction),
                        action: { showAdd = true }
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(model.repositories) { record in
                        NavigationLink {
                            RepositoryBrowseView(recordID: record.id)
                        } label: {
                            RepositoryRow(record: record)
                        }
                        .buttonStyle(SoftPressStyle())
                        .contextMenu {
                            Button {
                                Task { await model.refresh(record) }
                            } label: {
                                Label(model.t(.commonRefresh), systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                pendingRemoval = record
                            } label: {
                                Label(model.t(.commonDelete), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.reposTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAdd = true
                } label: {
                    Label(model.t(.reposAddAction), systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    Task { await model.refreshAllRepositories() }
                } label: {
                    if model.isRefreshingRepositories {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(model.t(.reposRefreshAll), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.repositories.isEmpty || model.isRefreshingRepositories)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddRepositoryView()
        }
        .confirmationDialog(
            model.t(.reposDeleteTitle),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t(.commonDelete), role: .destructive) {
                if let record = pendingRemoval {
                    Task { await model.remove(record) }
                }
                pendingRemoval = nil
            }
            Button(model.t(.commonCancel), role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(model.t(.reposDeleteBody))
        }
    }
}

private struct RepositoryRow: View {
    @Environment(AppModel.self) private var model
    let record: RepositoryRecord

    var body: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(model.palette.accent)
                    .frame(width: 40, height: 40)
                    .background(model.palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(URL(string: record.url)?.host ?? record.url)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(record.appCount) \(model.t(.reposAppCount))")
                        if let fetched = record.lastFetchedAt {
                            Text("·")
                            Text(Format.date(fetched, locale: model.locale))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if record.lastError != nil {
                    StatusChip(text: model.t(.reposSourceError), tone: .warning, symbol: "exclamationmark.triangle")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Add repository

struct AddRepositoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var urlString = ""
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !isSaving && !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(model.t(.reposUrlPlaceholder), text: $urlString)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(model.t(.reposRepositoryURL))
                } footer: {
                    Text(model.t(.reposAddBody))
                }

                Section {
                    TextField(model.t(.reposNameOptional), text: $name)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(model.t(.reposAddTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.t(.commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(model.t(.reposAdd))
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func submit() {
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await model.addRepository(
                    urlString: urlString,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
                )
                dismiss()
            } catch {
                errorMessage = model.errorText(error)
            }
            isSaving = false
        }
    }
}

// MARK: - Browse a repository

struct RepositoryBrowseView: View {
    @Environment(AppModel.self) private var model
    let recordID: UUID

    @State private var query = ""

    private var record: RepositoryRecord? {
        model.repositories.first { $0.id == recordID }
    }

    private var apps: [SourceApp] {
        let all = record?.document?.apps ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(trimmed)
                || ($0.developerName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let record {
                    if let error = record.lastError {
                        staleBanner(error)
                    }
                    if apps.isEmpty {
                        EmptyStateView(
                            symbol: "tray",
                            title: model.t(.reposNoApps),
                            message: model.t(.commonRefresh),
                            actionTitle: model.t(.commonRefresh),
                            action: { Task { await model.refresh(record) } }
                        )
                        .padding(.top, 12)
                    } else {
                        ForEach(apps) { app in
                            NavigationLink {
                                RepositoryAppDetailView(app: app, repositoryName: record.displayName)
                            } label: {
                                RepositoryAppRow(app: app)
                            }
                            .buttonStyle(SoftPressStyle())
                        }
                    }
                } else {
                    EmptyStateView(
                        symbol: "questionmark.folder",
                        title: model.t(.reposEmptyTitle),
                        message: model.t(.reposEmptyBody)
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(record?.displayName ?? model.t(.reposTitle))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text(model.t(.reposSearchApps)))
        .refreshable {
            if let record { await model.refresh(record) }
        }
    }

    private func staleBanner(_ message: String) -> some View {
        GlassPanel(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(model.t(.reposStaleNote), systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct RepositoryAppRow: View {
    @Environment(AppModel.self) private var model
    let app: SourceApp

    var body: some View {
        GlassPanel(cornerRadius: 20, padding: 12) {
            HStack(spacing: 12) {
                AppIconView(urlString: app.iconURL, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        if app.beta == true {
                            StatusChip(text: model.t(.reposBeta), tone: .info)
                        }
                    }
                    if let developerName = app.developerName {
                        Text(developerName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(app.bundleIdentifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(app.latestVersion?.version ?? "—")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    Text(app.latestVersion?.size.map(Format.bytes) ?? model.t(.reposUnknownSize))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - App detail

struct RepositoryAppDetailView: View {
    @Environment(AppModel.self) private var model
    let app: SourceApp
    let repositoryName: String

    private var activeJob: DownloadJob? {
        model.downloads.first {
            $0.bundleIdentifier == app.bundleIdentifier && $0.isActive
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let description = app.localizedDescription, !description.isEmpty {
                    GlassPanel(cornerRadius: 22, padding: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: model.t(.commonDetails))
                            Text(description)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                versions
                if let activeJob {
                    activeDownload(activeJob)
                }
                compatibilityNote
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        GlassPanel(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    AppIconView(urlString: app.iconURL, size: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        if let developer = app.developerName {
                            Text(developer).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let subtitle = app.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    InfoRow(label: model.t(.ipaBundleId), value: app.bundleIdentifier, monospaced: true)
                    InfoRow(label: model.t(.librarySource), value: repositoryName)
                    if let latest = app.latestVersion {
                        InfoRow(label: model.t(.reposLatestVersion), value: latest.version)
                        InfoRow(
                            label: model.t(.ipaMinOS),
                            value: latest.minOSVersion ?? model.t(.commonUnknown)
                        )
                        InfoRow(
                            label: model.t(.commonSize),
                            value: latest.size.map(Format.bytes) ?? model.t(.reposUnknownSize)
                        )
                        if let date = latest.date {
                            InfoRow(label: model.t(.commonDate), value: date)
                        }
                    }
                }
            }
        }
    }

    private var versions: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.commonVersion))
                ForEach(app.versions) { version in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(version.version)
                                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                                if !version.isCompatible(
                                    withOSVersion: ProcessInfo.processInfo.operatingSystemVersion
                                ) {
                                    StatusChip(text: model.t(.ipaIncompatible), tone: .warning)
                                }
                            }
                            Text(version.size.map(Format.bytes) ?? model.t(.reposUnknownSize))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            model.download(app: app, version: version, sourceName: repositoryName)
                        } label: {
                            Label(model.t(.reposDownload), systemImage: "arrow.down.circle")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(activeJob != nil)
                    }
                    if version.id != app.versions.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func activeDownload(_ job: DownloadJob) -> some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(job.appName).font(.footnote.weight(.semibold))
                    Spacer()
                    Text(job.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: job.fraction)
                HStack {
                    Text(Format.bytes(job.bytesReceived))
                    Text(model.t(.downloadsBytesOf))
                    Text(Format.bytes(job.totalBytes))
                    Spacer()
                    Button(model.t(.downloadsCancel)) { model.cancel(job) }
                        .font(.caption.weight(.semibold))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var compatibilityNote: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.secondary)
                Text(model.t(.reposCompatibility))
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}
