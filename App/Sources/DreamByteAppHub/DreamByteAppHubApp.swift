import SwiftUI
import AppHubCore

@main
struct DreamByteAppHubApp: App {
    @State private var model: AppModel?
    @State private var startupError: String?

    init() {
        do {
            let paths = try AppHubPaths.applicationDefault()
            _model = State(initialValue: try AppModel(paths: paths))
        } catch {
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView()
                    .environment(model)
            } else {
                StartupFailureView(message: startupError ?? "")
            }
        }
    }
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.orange)
            Text("DreamByte AppHub")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
