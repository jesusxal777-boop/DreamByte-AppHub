import SwiftUI
import AppHubCore
#if canImport(UIKit)
import UIKit
#endif

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var report: DiagnosticReport?
    @State private var showShare = false
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if let report {
                    environment(report)
                    modules(report)
                    counts(report)
                    notes(report)
                }
                privacy
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.diagnosticsTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    report = model.makeDiagnosticReport()
                } label: {
                    Label(model.t(.commonRefresh), systemImage: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            if report == nil {
                report = model.makeDiagnosticReport()
            }
        }
        .sheet(isPresented: $showShare) {
            #if canImport(UIKit)
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
            #endif
        }
    }

    private var summary: some View {
        GlassPanel(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "stethoscope")
                        .font(.title3)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t(.diagnosticsSummary))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(model.t(.diagnosticsPrivacyNote))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = model.diagnosticsText()
                        #endif
                        model.showBanner(model.t(.diagnosticsCopySuccess), style: .success)
                    } label: {
                        Label(model.t(.diagnosticsCopyReport), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        exportURL = model.exportDiagnostics()
                        showShare = exportURL != nil
                    } label: {
                        Label(model.t(.diagnosticsExport), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func environment(_ report: DiagnosticReport) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.diagnosticsEnvironment))
                InfoRow(label: model.t(.appName), value: "\(report.environment.appVersion) (\(report.environment.appBuild))")
                InfoRow(label: model.t(.dashboardDevice), value: report.environment.deviceModel)
                InfoRow(label: model.t(.jitIosVersion), value: report.environment.osVersion)
                InfoRow(label: model.t(.settingsLanguage), value: report.environment.interfaceLanguage)
                InfoRow(label: model.t(.commonDate), value: Format.dateTime(report.generatedAt, locale: model.locale))
                if report.environment.isDevelopmentBuild {
                    StatusChip(text: model.t(.settingsDevelopmentBuild), tone: .info)
                }
            }
        }
    }

    private func modules(_ report: DiagnosticReport) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.diagnosticsModules))
                ForEach(report.modules, id: \.name) { module in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(module.status == model.t(.commonWarning) ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(module.name)
                                .font(.footnote.weight(.medium))
                            Text(module.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(module.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func counts(_ report: DiagnosticReport) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.diagnosticsSummary))
                ForEach(report.counts.keys.sorted(), id: \.self) { key in
                    InfoRow(label: key, value: "\(report.counts[key] ?? 0)", monospaced: true)
                }
            }
        }
    }

    private func notes(_ report: DiagnosticReport) -> some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: model.t(.commonDetails))
                ForEach(report.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacy: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised")
                    .foregroundStyle(.secondary)
                Text(model.t(.diagnosticsPrivacyNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}
