import SwiftUI
import AppHubCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var showIPAImporter = false
    @State private var showAddRepository = false

    private var activeDownloads: [DownloadJob] {
        model.downloads.filter(\.isActive)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                hero
                metrics
                quickActions
                recentActivity
                capabilityNotice
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.dashboardTitle))
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.reload() }
        .fileImporter(
            isPresented: $showIPAImporter,
            allowedContentTypes: [FileTypes.ipa],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task { await model.importIPA(from: url) }
        }
        .sheet(isPresented: $showAddRepository) {
            AddRepositoryView()
        }
    }

    // MARK: Hero

    private var hero: some View {
        GlassPanel(cornerRadius: 28, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BrandMarkView(theme: model.theme, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t(.appName))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(model.t(.appTagline))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if model.theme.isPlaceholder {
                        StatusChip(text: model.t(.settingsTemporaryBranding), tone: .info, symbol: "sparkles")
                    }
                }

                Text(model.t(.dashboardSubtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(model.t(.dashboardDevice), systemImage: "iphone")
                    Text("·")
                    Text(DeviceInfo.systemVersion)
                    Spacer()
                    Text("v\(DeviceInfo.appVersion)")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Metrics

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            NavigationLink { IPALibraryView() } label: {
                MetricTile(
                    value: "\(model.packages.count)",
                    title: model.t(.dashboardIpasCard),
                    symbol: "shippingbox.fill",
                    tint: model.palette.secondary
                )
            }
            .buttonStyle(SoftPressStyle())

            NavigationLink { RepositoriesView() } label: {
                MetricTile(
                    value: "\(model.repositories.count)",
                    title: model.t(.dashboardReposCard),
                    symbol: "square.stack.3d.up.fill",
                    tint: model.palette.accent
                )
            }
            .buttonStyle(SoftPressStyle())

            NavigationLink { DownloadsView() } label: {
                MetricTile(
                    value: "\(activeDownloads.count)",
                    title: model.t(.dashboardDownloadsCard),
                    symbol: "arrow.down.circle.fill",
                    tint: .orange
                )
            }
            .buttonStyle(SoftPressStyle())

            NavigationLink { CertificatesView() } label: {
                MetricTile(
                    value: "\(model.signingRecords.count)",
                    title: model.t(.dashboardCertsCard),
                    symbol: "checkmark.seal.fill",
                    tint: .green
                )
            }
            .buttonStyle(SoftPressStyle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: model.t(.dashboardQuickActions))
            AdaptiveGlassGroup {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    QuickActionButton(
                        title: model.t(.dashboardImportIPA),
                        symbol: "square.and.arrow.down",
                        tint: model.palette.secondary
                    ) { showIPAImporter = true }

                    QuickActionButton(
                        title: model.t(.dashboardAddRepo),
                        symbol: "plus.rectangle.on.folder",
                        tint: model.palette.accent
                    ) { showAddRepository = true }

                    NavigationLink {
                        JITView()
                    } label: {
                        QuickActionLabel(
                            title: model.t(.tabJit),
                            symbol: "bolt.horizontal",
                            tint: .yellow
                        )
                    }
                    .buttonStyle(SoftPressStyle())

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        QuickActionLabel(
                            title: model.t(.dashboardDiagnosticsAction),
                            symbol: "stethoscope",
                            tint: .purple
                        )
                    }
                    .buttonStyle(SoftPressStyle())
                }
            }
        }
    }

    // MARK: Recent

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: model.t(.dashboardRecent))
            GlassPanel(cornerRadius: 24, padding: 6) {
                if model.packages.isEmpty && model.downloads.isEmpty {
                    Text(model.t(.dashboardNoActivity))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(model.packages.prefix(3))) { package in
                            NavigationLink {
                                IPADetailView(package: package)
                            } label: {
                                recentRow(
                                    symbol: "shippingbox.fill",
                                    title: package.originalName,
                                    detail: package.inspection?.version ?? model.t(.libraryUnknownVersion),
                                    tint: model.palette.secondary
                                )
                            }
                            .buttonStyle(SoftPressStyle())
                            Divider().padding(.leading, 46)
                        }
                        ForEach(Array(model.downloads.prefix(3))) { job in
                            NavigationLink {
                                DownloadsView()
                            } label: {
                                recentRow(
                                    symbol: "arrow.down.circle.fill",
                                    title: job.appName,
                                    detail: downloadStateText(job),
                                    tint: .orange
                                )
                            }
                            .buttonStyle(SoftPressStyle())
                        }
                    }
                }
            }
        }
    }

    private func recentRow(symbol: String, title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func downloadStateText(_ job: DownloadJob) -> String {
        switch job.state {
        case .waiting: model.t(.downloadsWaiting)
        case .downloading: model.t(.reposDownloading)
        case .validating: model.t(.downloadsValidating)
        case .completed: model.t(.downloadsCompleted)
        case .failed: model.t(.downloadsFailed)
        case .cancelled: model.t(.errorCancelled)
        }
    }

    // MARK: Capability notice

    private var capabilityNotice: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.t(.ipaInstallUnavailableTitle))
                        .font(.footnote.weight(.semibold))
                    Text(model.t(.ipaInstallUnavailableBody))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Quick action

private struct QuickActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, symbol: symbol, tint: tint)
        }
        .buttonStyle(SoftPressStyle())
    }
}

private struct QuickActionLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appHubGlass(cornerRadius: 16)
    }
}
