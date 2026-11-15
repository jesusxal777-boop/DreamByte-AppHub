import SwiftUI
import AppHubCore

struct DownloadsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.downloads.isEmpty {
                    EmptyStateView(
                        symbol: "arrow.down.circle",
                        title: model.t(.downloadsEmptyTitle),
                        message: model.t(.downloadsEmptyBody)
                    )
                    .padding(.top, 24)
                } else {
                    ForEach(model.downloads) { job in
                        DownloadRow(job: job)
                    }
                }
                GlassPanel(cornerRadius: 20, padding: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.secondary)
                        Text(model.t(.downloadsNoAutoInstall))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.downloadsTitle))
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    model.clearCompletedDownloads()
                } label: {
                    Label(model.t(.settingsClearDownloads), systemImage: "trash")
                }
                .disabled(model.downloads.allSatisfy(\.isActive))
            }
        }
    }
}

private struct DownloadRow: View {
    @Environment(AppModel.self) private var model
    let job: DownloadJob

    private var fileExists: Bool {
        FileManager.default.fileExists(atPath: model.downloadFileURL(job).path)
    }

    var body: some View {
        GlassPanel(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.appName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .lineLimit(1)
                        Text("\(job.version) · \(job.sourceName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(job.bundleIdentifier)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    StatusChip(text: stateText, tone: tone, symbol: symbol)
                }

                if job.isActive {
                    ProgressView(value: job.fraction)
                    HStack {
                        Text(Format.bytes(job.bytesReceived))
                        Text(model.t(.downloadsBytesOf))
                        Text(job.totalBytes > 0 ? Format.bytes(job.totalBytes) : "—")
                        Spacer()
                        Text(job.fraction, format: .percent.precision(.fractionLength(0)))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                if let error = job.errorMessage, job.state == .failed {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !job.validationNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(job.validationNotes, id: \.self) { note in
                            HStack(alignment: .top, spacing: 5) {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.green)
                                    .padding(.top, 2)
                                Text(note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    if job.state == .completed, fileExists {
                        ShareLink(item: model.downloadFileURL(job)) {
                            Label(model.t(.downloadsOpen), systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if job.isActive {
                        Button(role: .destructive) {
                            model.cancel(job)
                        } label: {
                            Text(model.t(.downloadsCancel)).font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if job.state == .failed || job.state == .cancelled {
                        Button {
                            model.retry(job)
                        } label: {
                            Label(model.t(.downloadsRetry), systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                    if !job.isActive {
                        Button(role: .destructive) {
                            model.delete(job)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(model.t(.downloadsDelete))
                    }
                }
            }
        }
    }

    private var stateText: String {
        switch job.state {
        case .waiting: model.t(.downloadsWaiting)
        case .downloading: model.t(.reposDownloading)
        case .validating: model.t(.downloadsValidating)
        case .completed: model.t(.downloadsCompleted)
        case .failed: model.t(.downloadsFailed)
        case .cancelled: model.t(.errorCancelled)
        }
    }

    private var symbol: String {
        switch job.state {
        case .waiting: "clock"
        case .downloading: "arrow.down.circle"
        case .validating: "checkmark.shield"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private var tint: Color {
        switch job.state {
        case .completed: .green
        case .failed: .orange
        case .cancelled: .secondary
        default: model.palette.secondary
        }
    }

    private var tone: ChipTone {
        switch job.state {
        case .completed: .positive
        case .failed: .negative
        case .cancelled: .neutral
        default: .info
        }
    }
}
