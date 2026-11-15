import SwiftUI

/// Private DreamByte palette helper. All values come from `BrandTheme`; this
/// file only converts hex strings into SwiftUI colors.
enum BrandColor {
    static func color(hex: String, fallback: Color = .gray) -> Color {
        guard let components = rgba(hex: hex) else { return fallback }
        return Color(.sRGB, red: components.r, green: components.g, blue: components.b, opacity: components.a)
    }

    static func rgba(hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else { return nil }
        if cleaned.count == 6 {
            return (
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255,
                1
            )
        }
        return (
            Double((value >> 24) & 0xFF) / 255,
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

/// Resolved colors for one theme.
struct BrandPalette {
    let primary: Color
    let secondary: Color
    let accent: Color

    init(theme: BrandTheme) {
        primary = BrandColor.color(hex: theme.primaryHex, fallback: .indigo)
        secondary = BrandColor.color(hex: theme.secondaryHex, fallback: .blue)
        accent = BrandColor.color(hex: theme.accentHex, fallback: .cyan)
    }

    var heroGradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary.opacity(0.9), accent.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var subtleGradient: LinearGradient {
        LinearGradient(
            colors: [secondary.opacity(0.22), accent.opacity(0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
