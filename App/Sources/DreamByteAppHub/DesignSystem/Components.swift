import SwiftUI
import AppHubCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Metric

struct MetricTile: View {
    let value: String
    let title: String
    let symbol: String
    var tint: Color = .accentColor
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { content }.buttonStyle(SoftPressStyle())
            } else {
                content
            }
        }
    }

    private var content: some View {
        GlassPanel(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Status chip

enum ChipTone {
    case neutral, positive, warning, negative, info

    var foreground: Color {
        switch self {
        case .neutral: .secondary
        case .positive: .green
        case .warning: .orange
        case .negative: .red
        case .info: .blue
        }
    }
}

struct StatusChip: View {
    let text: String
    var tone: ChipTone = .neutral
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tone.foreground.opacity(0.12), in: Capsule())
        .accessibilityLabel(text)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 76, height: 76)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .appHubGlass(cornerRadius: 28)
    }
}

// MARK: - Detail row

struct InfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false
    var copyable: Bool = false

    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if copyable {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = value
                    #endif
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(label)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Placeholder brand mark

/// Deliberately abstract stand-in. DreamByte Studios' official mark will
/// replace it through `BrandTheme.logoAssetName` without touching this view.
struct BrandMarkView: View {
    let theme: BrandTheme
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let image = UIImage(named: theme.logoAssetName, in: .module, compatibleWith: nil) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholderMark
            }
            #else
            placeholderMark
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholderMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(BrandPalette(theme: theme).heroGradient)
            VStack(spacing: size * 0.09) {
                Capsule().fill(.white.opacity(0.92)).frame(width: size * 0.44, height: size * 0.085)
                Capsule().fill(.white.opacity(0.72)).frame(width: size * 0.32, height: size * 0.085)
                Capsule().fill(.white.opacity(0.52)).frame(width: size * 0.4, height: size * 0.085)
            }
        }
    }
}

// MARK: - Local icon

/// Reads an icon that AppHub extracted from an IPA. `AsyncImage` cannot load
/// `file://` URLs reliably, so this uses UIKit directly.
struct LocalIconView: View {
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.5), .blue.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "shippingbox.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Remote icon

struct AppIconView: View {
    let urlString: String?
    var size: CGFloat = 44
    var fallbackSymbol: String = "app.fill"

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), url.scheme == "https" || url.scheme == "http" {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay(ProgressView().controlSize(.small))
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.55), .blue.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: fallbackSymbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// MARK: - Banner

struct BannerMessage: Identifiable, Equatable, Sendable {
    enum Style: Sendable { case info, success, error }

    let id = UUID()
    var text: String
    var style: Style
}

struct BannerView: View {
    let banner: BannerMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(banner.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .appHubGlass(cornerRadius: 16)
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityAddTraits(.isStaticText)
    }

    private var symbol: String {
        switch banner.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch banner.style {
        case .info: .blue
        case .success: .green
        case .error: .orange
        }
    }
}

// MARK: - Formatting helpers

enum Format {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }

    static func date(_ date: Date?, locale: Locale) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateTime(_ date: Date?, locale: Locale) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
