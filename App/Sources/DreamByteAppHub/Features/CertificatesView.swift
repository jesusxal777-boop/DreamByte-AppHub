import SwiftUI
import AppHubCore

struct CertificatesView: View {
    @Environment(AppModel.self) private var model
    @State private var showProfileImporter = false
    @State private var showP12Importer = false
    @State private var pendingP12: PendingP12?
    @State private var pendingRemoval: SigningRecord?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.signingRecords.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.seal",
                        title: model.t(.certsEmptyTitle),
                        message: model.t(.certsEmptyBody),
                        actionTitle: model.t(.certsImportProfile),
                        action: { showProfileImporter = true }
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(model.signingRecords) { record in
                        NavigationLink {
                            SigningRecordDetailView(recordID: record.id)
                        } label: {
                            SigningRecordRow(record: record)
                        }
                        .buttonStyle(SoftPressStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingRemoval = record
                            } label: {
                                Label(model.t(.commonDelete), systemImage: "trash")
                            }
                        }
                    }
                }

                securityNote
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.certsTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showProfileImporter = true
                    } label: {
                        Label(model.t(.certsImportProfile), systemImage: "doc.badge.plus")
                    }
                    Button {
                        showP12Importer = true
                    } label: {
                        Label(model.t(.certsImportP12), systemImage: "key")
                    }
                    .disabled(!model.capabilities.canImportP12)
                } label: {
                    Label(model.t(.commonImportAction), systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $showProfileImporter,
            allowedContentTypes: FileTypes.provisioningImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await model.importProfile(from: url) }
            case let .failure(error):
                model.reportImportPickerFailure(error)
            }
        }
        .fileImporter(
            isPresented: $showP12Importer,
            allowedContentTypes: FileTypes.pkcs12ImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                pendingP12 = PendingP12(url: url)
            case let .failure(error):
                model.reportImportPickerFailure(error)
            }
        }
        .sheet(item: $pendingP12) { selection in
            P12PasswordView(fileURL: selection.url)
        }
        .confirmationDialog(
            model.t(.certsRemoveTitle),
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.t(.commonDelete), role: .destructive) {
                if let record = pendingRemoval {
                    Task { await model.delete(record) }
                }
                pendingRemoval = nil
            }
            Button(model.t(.commonCancel), role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(model.t(.certsRemoveBody))
        }
        .onAppear { model.refreshJITCapabilities() }
    }

    private var securityNote: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t(.certsSecurityNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.capabilities.canImportP12 {
                        Text(model.t(.certsP12Unavailable))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Row

struct PendingP12: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SigningRecordRow: View {
    @Environment(AppModel.self) private var model
    let record: SigningRecord

    var body: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: record.kind == .provisioningProfile ? "checkmark.seal.fill" : "key.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(record.isExpired() ? .orange : .green)
                    .frame(width: 40, height: 40)
                    .background(
                        (record.isExpired() ? Color.orange : Color.green).opacity(0.13),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(record.teamName ?? record.teamIdentifiers.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let kind = record.profileKind {
                            Text(kindText(kind))
                        }
                        if let expires = record.expiresAt {
                            Text("·")
                            Text(Format.date(expires, locale: model.locale))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)

                if record.isExpired() {
                    StatusChip(text: model.t(.certsExpired), tone: .warning, symbol: "clock.badge.exclamationmark")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func kindText(_ kind: ProfileKind) -> String {
        switch kind {
        case .development: model.t(.certsDevelopment)
        case .adHoc: model.t(.certsDistribution)
        case .appStore: model.t(.certsDistribution)
        case .enterprise: model.t(.certsEnterprise)
        case .unknown: model.t(.certsUnknownType)
        }
    }
}

// MARK: - Detail

struct SigningRecordDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID

    @State private var showDelete = false

    private var record: SigningRecord? {
        model.signingRecords.first { $0.id == recordID }
    }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 16) {
                    header(record)
                    details(record)
                    if !record.certificates.isEmpty {
                        certificates(record)
                    }
                    if !record.entitlements.isEmpty {
                        entitlements(record)
                    }
                    security(record)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: model.t(.certsEmptyTitle),
                    message: model.t(.certsEmptyBody)
                )
                .padding(18)
            }
        }
        .navigationTitle(record?.displayName ?? model.t(.certsTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDelete = true
                } label: {
                    Label(model.t(.commonDelete), systemImage: "trash")
                }
            }
        }
        .confirmationDialog(
            model.t(.certsRemoveTitle),
            isPresented: $showDelete,
            titleVisibility: .visible
        ) {
            Button(model.t(.commonDelete), role: .destructive) {
                if let record {
                    Task {
                        await model.delete(record)
                        dismiss()
                    }
                }
            }
            Button(model.t(.commonCancel), role: .cancel) {}
        } message: {
            Text(model.t(.certsRemoveBody))
        }
    }

    private func header(_ record: SigningRecord) -> some View {
        GlassPanel(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: record.kind == .provisioningProfile ? "checkmark.seal.fill" : "key.fill")
                        .font(.title2)
                        .foregroundStyle(record.isExpired() ? .orange : .green)
                    Text(record.displayName)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    StatusChip(
                        text: record.kind == .provisioningProfile ? model.t(.certsCertificate) : model.t(.certsIdentityKeychain),
                        tone: .info
                    )
                    if record.isExpired() {
                        StatusChip(text: model.t(.certsExpired), tone: .warning, symbol: "clock.badge.exclamationmark")
                    } else if let expires = record.expiresAt {
                        StatusChip(
                            text: "\(model.t(.certsValidUntil)) \(Format.date(expires, locale: model.locale))",
                            tone: .positive,
                            symbol: "checkmark"
                        )
                    }
                    if !record.signatureVerified {
                        StatusChip(text: model.t(.certsNotChecked), tone: .neutral)
                    }
                }
            }
        }
    }

    private func details(_ record: SigningRecord) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.commonDetails))
                if let team = record.teamName {
                    InfoRow(label: model.t(.certsTeam), value: team)
                }
                if !record.teamIdentifiers.isEmpty {
                    InfoRow(label: model.t(.certsTeam), value: record.teamIdentifiers.joined(separator: ", "), monospaced: true)
                }
                if let appID = record.applicationIdentifier {
                    InfoRow(label: model.t(.certsAppID), value: appID, monospaced: true, copyable: true)
                }
                if let kind = record.profileKind {
                    InfoRow(label: model.t(.certsProfileType), value: kindText(kind))
                }
                if let deviceCount = record.deviceCount {
                    InfoRow(label: model.t(.certsDevices), value: "\(deviceCount)")
                }
                if let created = record.createdAt {
                    InfoRow(label: model.t(.certsImportedAt), value: Format.date(created, locale: model.locale))
                }
                if let expires = record.expiresAt {
                    InfoRow(label: model.t(.certsExpires), value: Format.date(expires, locale: model.locale))
                }
                InfoRow(label: model.t(.certsImportedAt), value: Format.dateTime(record.importedAt, locale: model.locale))
                if let source = record.sourceFileName {
                    InfoRow(label: model.t(.ipaOriginalName), value: source)
                }
            }
        }
    }

    private func certificates(_ record: SigningRecord) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.certsCertCount))
                ForEach(record.certificates, id: \.sha256Fingerprint) { certificate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(certificate.commonName ?? model.t(.commonUnknown))
                            .font(.footnote.weight(.semibold))
                        if let issuer = certificate.issuerCommonName {
                            Text("\(model.t(.certsIssuer)): \(issuer)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let notAfter = certificate.notAfter {
                            Text("\(model.t(.certsValidUntil)): \(Format.date(notAfter, locale: model.locale))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(certificate.sha256Fingerprint)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func entitlements(_ record: SigningRecord) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: model.t(.certsEntitlements))
                ForEach(record.entitlements.keys.sorted(), id: \.self) { key in
                    HStack(alignment: .top, spacing: 8) {
                        Text(key)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 6)
                        Text(record.entitlements[key] ?? "")
                            .font(.system(size: 10, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }

    private func security(_ record: SigningRecord) -> some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.t(.certsSecurityNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !record.signatureVerified {
                    Text(model.t(.certsRevocationUnchecked))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func kindText(_ kind: ProfileKind) -> String {
        switch kind {
        case .development: model.t(.certsDevelopment)
        case .adHoc, .appStore: model.t(.certsDistribution)
        case .enterprise: model.t(.certsEnterprise)
        case .unknown: model.t(.certsUnknownType)
        }
    }
}

// MARK: - PKCS#12 password

struct P12PasswordView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fileURL: URL

    @State private var password = ""
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(model.t(.certsP12PasswordPrompt), text: $password)
                        .textContentType(.password)
                } footer: {
                    Text(model.t(.certsP12PasswordBody))
                }

                Section {
                    Text(fileURL.lastPathComponent)
                        .font(.footnote.monospaced())
                }
            }
            .navigationTitle(model.t(.certsImportP12))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.t(.commonCancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isImporting = true
                        Task {
                            await model.importIdentity(from: fileURL, password: password)
                            isImporting = false
                            dismiss()
                        }
                    } label: {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(model.t(.commonImportAction))
                        }
                    }
                    .disabled(isImporting)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
