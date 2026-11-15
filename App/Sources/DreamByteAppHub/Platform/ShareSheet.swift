import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// System share sheet for exported files (diagnostics, IPAs, downloads).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
