import SwiftUI

/// Liquid Glass on iOS 26+, translucent material everywhere else.
///
/// The compiler guard keeps the package buildable with Xcode 16 (Swift 6.0,
/// iOS 18 SDK) where `glassEffect` does not exist yet; Xcode 26+ compiles the
/// real Liquid Glass path.
extension View {
    @ViewBuilder
    func appHubGlass(cornerRadius: CGFloat = 24) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.appHubMaterial(cornerRadius: cornerRadius)
        }
        #else
        self.appHubMaterial(cornerRadius: cornerRadius)
        #endif
    }

    /// Pre-iOS 26 (and non-Apple) fallback.
    func appHubMaterial(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
            }
    }
}

/// Groups neighbouring glass surfaces so they can blend on iOS 26.
struct AdaptiveGlassGroup<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A padded glass surface used by cards and panels.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appHubGlass(cornerRadius: cornerRadius)
    }
}

/// Press feedback that does not rely on iOS 26-only button styles.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
