import SwiftUI
import AppHubCore

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: AppSection = .dashboard
    @State private var sidebarSelection: AppSection? = .dashboard

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground(palette: model.palette)
                .ignoresSafeArea()

            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                tabLayout
            }

            if let banner = model.banner {
                BannerView(banner: banner) {
                    model.dismissBanner()
                }
                .padding(.top, 6)
                .zIndex(2)
            }
        }
        .task {
            await model.bootstrap()
        }
        .onOpenURL { url in
            Task { await model.handleIncomingFile(url) }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .environment(\.locale, model.locale)
        .tint(model.palette.secondary)
        .animation(.snappy(duration: 0.25), value: model.banner?.id)
    }

    private var tabLayout: some View {
        TabView(selection: $selection) {
            ForEach(AppSection.tabs) { section in
                Tab(value: section) {
                    NavigationStack {
                        SectionRoot(section: section)
                    }
                } label: {
                    Label(model.t(section.titleKey), systemImage: section.symbol)
                }
            }
        }
    }

    private var splitLayout: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(model.t(section.titleKey), systemImage: section.symbol)
                            .tag(section)
                    }
                } header: {
                    Text(model.t(.appName))
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                SectionRoot(section: sidebarSelection ?? .dashboard)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// One navigation root per section. Kept separate from the tab/sidebar chrome
/// so both layouts share the exact same screens.
struct SectionRoot: View {
    let section: AppSection

    var body: some View {
        switch section {
        case .dashboard: DashboardView()
        case .ipas: IPALibraryView()
        case .repositories: RepositoriesView()
        case .downloads: DownloadsView()
        case .certificates: CertificatesView()
        case .jit: JITView()
        case .library: LibraryView()
        case .diagnostics: DiagnosticsView()
        case .settings: SettingsView()
        }
    }
}

struct AppBackground: View {
    let palette: BrandPalette

    var body: some View {
        ZStack {
            Color(.systemBackground)
            palette.subtleGradient
                .opacity(0.55)
            LinearGradient(
                colors: [.clear, Color(.systemBackground).opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
