import Foundation

/// Every visual identity value is data. DreamByte Studios' official assets can
/// replace these without touching view code.
public struct BrandTheme: Codable, Sendable, Equatable {
    public var displayName: String
    public var tagline: String
    public var wordmarkText: String
    public var primaryHex: String
    public var secondaryHex: String
    public var accentHex: String
    public var logoAssetName: String
    public var appIconAssetName: String
    public var cornerRadius: Double
    public var usesLiquidGlass: Bool
    public var isPlaceholder: Bool

    public init(
        displayName: String,
        tagline: String,
        wordmarkText: String,
        primaryHex: String,
        secondaryHex: String,
        accentHex: String,
        logoAssetName: String,
        appIconAssetName: String,
        cornerRadius: Double,
        usesLiquidGlass: Bool,
        isPlaceholder: Bool
    ) {
        self.displayName = displayName
        self.tagline = tagline
        self.wordmarkText = wordmarkText
        self.primaryHex = primaryHex
        self.secondaryHex = secondaryHex
        self.accentHex = accentHex
        self.logoAssetName = logoAssetName
        self.appIconAssetName = appIconAssetName
        self.cornerRadius = cornerRadius
        self.usesLiquidGlass = usesLiquidGlass
        self.isPlaceholder = isPlaceholder
    }

    /// Temporary identity. `isPlaceholder` is surfaced in Settings so nobody
    /// mistakes this for the final DreamByte Studios branding.
    public static let placeholder = BrandTheme(
        displayName: "DreamByte AppHub",
        tagline: "App manager for iOS",
        wordmarkText: "AppHub",
        primaryHex: "#0A1A33",
        secondaryHex: "#2E7DFF",
        accentHex: "#5CC8FF",
        logoAssetName: "BrandMarkPlaceholder",
        appIconAssetName: "AppIconPlaceholder",
        cornerRadius: 24,
        usesLiquidGlass: true,
        isPlaceholder: true
    )

    public static let `default` = BrandTheme.placeholder
}

/// Partial overrides loaded from `branding.json`. Missing fields keep the
/// placeholder values; unknown fields are ignored.
public struct BrandOverrides: Codable, Sendable {
    public var displayName: String?
    public var tagline: String?
    public var wordmarkText: String?
    public var primaryHex: String?
    public var secondaryHex: String?
    public var accentHex: String?
    public var logoAssetName: String?
    public var appIconAssetName: String?
    public var cornerRadius: Double?
    public var usesLiquidGlass: Bool?
    public var isPlaceholder: Bool?

    public init() {}

    public func applied(to base: BrandTheme = .placeholder) -> BrandTheme {
        var theme = base
        if let displayName { theme.displayName = displayName }
        if let tagline { theme.tagline = tagline }
        if let wordmarkText { theme.wordmarkText = wordmarkText }
        if let primaryHex, BrandTheme.isValidHex(primaryHex) { theme.primaryHex = primaryHex }
        if let secondaryHex, BrandTheme.isValidHex(secondaryHex) { theme.secondaryHex = secondaryHex }
        if let accentHex, BrandTheme.isValidHex(accentHex) { theme.accentHex = accentHex }
        if let logoAssetName { theme.logoAssetName = logoAssetName }
        if let appIconAssetName { theme.appIconAssetName = appIconAssetName }
        if let cornerRadius, cornerRadius >= 0, cornerRadius <= 60 { theme.cornerRadius = cornerRadius }
        if let usesLiquidGlass { theme.usesLiquidGlass = usesLiquidGlass }
        if let isPlaceholder { theme.isPlaceholder = isPlaceholder }
        return theme
    }
}

public enum BrandLoader {
    public static func load(from url: URL, base: BrandTheme = .placeholder) -> BrandTheme {
        guard let data = try? Data(contentsOf: url),
              let overrides = try? JSONDecoder().decode(BrandOverrides.self, from: data) else {
            return base
        }
        return overrides.applied(to: base)
    }

    public static func loadFromBundle(base: BrandTheme = .placeholder) -> BrandTheme {
        guard let url = Bundle.module.url(forResource: "branding", withExtension: "json") else {
            return base
        }
        return load(from: url, base: base)
    }
}

public extension BrandTheme {
    static func isValidHex(_ value: String) -> Bool {
        let cleaned = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard cleaned.count == 6 || cleaned.count == 8 else { return false }
        return cleaned.allSatisfy(\.isHexDigit)
    }
}
