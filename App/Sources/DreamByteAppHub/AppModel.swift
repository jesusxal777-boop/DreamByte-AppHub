import Foundation
import Observation
import SwiftUI
import AppHubCore

enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var titleKey: L10nKey {
        switch self {
        case .system: .settingsSystem
        case .light: .settingsLight
        case .dark: .settingsDark
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard
    case ipas
    case repositories
    case downloads
    case certificates
    case jit
    case library
    case diagnostics
    case settings

    var id: String { rawValue }

    var titleKey: L10nKey {
        switch self {
        case .dashboard: .tabDashboard
        case .ipas: .tabIpas
        case .repositories: .tabRepositories
        case .downloads: .tabDownloads
        case .certificates: .tabCertificates
        case .jit: .tabJit
        case .library: .tabLibrary
        case .diagnostics: .tabDiagnostics
        case .settings: .tabSettings
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .ipas: "shippingbox"
        case .repositories: "square.stack.3d.up"
        case .downloads: "arrow.down.circle"
        case .certificates: "checkmark.seal"
        case .jit: "bolt.horizontal.circle"
        case .library: "books.vertical"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape"
        }
    }

    static let tabs: [AppSection] = [.dashboard, .ipas, .repositories, .downloads, .settings]
  }

/// Everything the UI needs to know about what this build can actually do.
struct CapabilitySnapshot: Sendable {
    var canImportP12: Bool
    var canOpenStikDebug: Bool
    var canInstallApps = false
    var canEnumerateSystemApps = false
    var hasPairingFile = false
    var developerModeState: DeveloperModeState = .unknown
}

enum DeveloperModeState: Sendable {
    case enabled
    case disabled
    case unknown
}

@MainActor
@Observable
final class AppModel {
    // MARK: Stored state

    let paths: AppHubPaths
    let catalog: LocalizationCatalog
    let theme: BrandTheme
    let palette: BrandPalette
    let repositoryService: RepositoryService
    let downloadService: DownloadService
    let packageStore: AppPackageStore
    let signingStore: SigningStore

    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
        }
    }

    var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }

    var jitMethod: JITMethod {
        didSet {
            UserDefaults.standard.set(jitMethod.rawValue, forKey: Keys.jitMethod)
        }
    }

    var installMode: InstallMode {
        didSet {
            UserDefaults.standard.set(installMode.rawValue, forKey: Keys.installMode)
        }
    }

    var repositories: [RepositoryRecord] = []
    var packages: [AppPackage] = []
    var downloads: [DownloadJob] = []
    var signingRecords: [SigningRecord] = []
    var capabilities: CapabilitySnapshot
    var banner: BannerMessage?
    var isBootstrapping = true
    var isRefreshingRepositories = false

    let pairingFileURL: URL

    private var started = false
    private var bannerTask: Task<Void, Never>?

    // MARK: Init

    init(paths: AppHubPaths) throws {
        self.paths = paths
        try paths.prepare()

        let catalog = LocalizationCatalog.bundled()
        self.catalog = catalog
        self.theme = AppModel.loadTheme()
        self.palette = BrandPalette(theme: theme)

        self.repositoryService = RepositoryService(paths: paths)
        self.downloadService = DownloadService(paths: paths)
        self.packageStore = AppPackageStore(paths: paths)
        self.signingStore = SigningStore(paths: paths)
        self.pairingFileURL = paths.root.appendingPathComponent("Pairing/pairing.plist")

        let defaults = UserDefaults.standard
        let storedLanguage = defaults.string(forKey: Keys.language).flatMap(AppLanguage.init(rawValue:))
        self.language = LanguageResolver.resolve(
            override: storedLanguage,
            preferred: Locale.preferredLanguages,
            catalog: catalog
        )
        self.appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        self.jitMethod = defaults.string(forKey: Keys.jitMethod)
            .flatMap(JITMethod.init(rawValue:)) ?? .stikDebug
        self.installMode = defaults.string(forKey: Keys.installMode)
            .flatMap(InstallMode.init(rawValue:)) ?? .otaHandoff

        self.capabilities = CapabilitySnapshot(
            canImportP12: AppModel.supportsP12Import,
            canOpenStikDebug: false,
            hasPairingFile: FileManager.default.fileExists(atPath: pairingFileURL.path)
        )
    }

    static func loadTheme() -> BrandTheme {
        if let url = Bundle.main.url(forResource: "branding", withExtension: "json") {
            return BrandLoader.load(from: url)
        }
        return BrandLoader.loadFromBundle()
    }

    private static var supportsP12Import: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    // MARK: Localization

    var localizer: Localizer {
        Localizer(language: language, catalog: catalog)
    }

    var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    func t(_ key: L10nKey) -> String {
        localizer.text(key)
    }

    func errorText(_ error: Error) -> String {
        if let error = error as? AppHubError {
            return t(error.localizationKey)
        }
        return error.localizedDescription
    }

    // MARK: Bootstrap

    func bootstrap() async {
        guard !started else { return }
        started = true
        defer { isBootstrapping = false }

        do {
            repositories = try await repositoryService.list()
        } catch {
            showBanner(errorText(error), style: .error)
        }
        do {
            packages = try await packageStore.all()
        } catch {
            showBanner(errorText(error), style: .error)
        }
        do {
            downloads = try await downloadService.list()
        } catch {
            showBanner(errorText(error), style: .error)
        }
        do {
            signingRecords = try await signingStore.list()
        } catch {
            showBanner(errorText(error), style: .error)
        }

        capabilities.hasPairingFile = FileManager.default.fileExists(atPath: pairingFileURL.path)
        capabilities.canOpenStikDebug = StikDebugLauncher.isInstalled
    }

    // MARK: Banner

    func showBanner(_ text: String, style: BannerMessage.Style) {        let message = BannerMessage(text: text, style: style)
        banner = message
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if self?.banner?.id == message.id {
                self?.banner = nil
            }
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    /// Re-reads every store without re-running first-launch bootstrap logic.
    func reload() async {
        repositories = (try? await repositoryService.list()) ?? repositories
        packages = (try? await packageStore.all()) ?? packages
        downloads = (try? await downloadService.list()) ?? downloads
        signingRecords = (try? await signingStore.list()) ?? signingRecords
        refreshJITCapabilities()
    }

    // MARK: IPA library

    func importIPA(from url: URL) async {
        #if os(iOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let package = try await packageStore.importPackage(from: url)
            packages = try await packageStore.all()
            if package.failure == nil {
                showBanner(t(.ipaImportSuccess), style: .success)
            } else {
                showBanner(t(.ipaInspectionFailed), style: .error)
            }
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    func rescan(_ package: AppPackage) async {
        do {
            let url = await packageStore.packageURL(for: package)
            let result = try IPAInspector(url: url).inspect()
            var updated = package
            updated.inspection = result.inspection
            updated.failure = nil
            try? await packageStore.replace(updated)
            packages = try await packageStore.all()
            showBanner(t(.commonSuccess), style: .success)
        } catch let error as AppHubError {
            var updated = package
            updated.failure = PackageFailure(error: error)
            try? await packageStore.replace(updated)
            packages = try await packageStore.all()
            showBanner(errorText(error), style: .error)
        } catch {
            showBanner(error.localizedDescription, style: .error)
        }
    }

    func rename(_ package: AppPackage, to name: String) async {
        do {
            try await packageStore.rename(package, to: name)
            packages = try await packageStore.all()
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    func delete(_ package: AppPackage) async {
        do {
            try await packageStore.delete(package)
            packages = try await packageStore.all()
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    // MARK: Repositories

    @discardableResult
    func addRepository(urlString: String, name: String?) async throws -> RepositoryRecord {
        let record = try await repositoryService.add(urlString: urlString, name: name)
        repositories = try await repositoryService.list()
        showBanner(t(.reposAddSuccess), style: .success)
        return record
    }

    func refresh(_ record: RepositoryRecord) async {
        do {
            _ = try await repositoryService.refresh(id: record.id)
            repositories = try await repositoryService.list()
            showBanner(t(.reposRefreshSuccess), style: .success)
        } catch {
            repositories = (try? await repositoryService.list()) ?? repositories
            showBanner(errorText(error), style: .error)
        }
    }

    func refreshAllRepositories() async {
        guard !isRefreshingRepositories else { return }
        isRefreshingRepositories = true
        defer { isRefreshingRepositories = false }
        for record in repositories {
            _ = try? await repositoryService.refresh(id: record.id)
        }
        repositories = (try? await repositoryService.list()) ?? repositories
        if repositories.contains(where: { $0.lastError != nil }) {
            showBanner(t(.reposSourceError), style: .error)
        } else {
            showBanner(t(.reposRefreshSuccess), style: .success)
        }
    }

    func remove(_ record: RepositoryRecord) async {
        do {
            try await repositoryService.remove(id: record.id)
            repositories = try await repositoryService.list()
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    // MARK: Downloads

    func download(app: SourceApp, version: SourceVersion, sourceName: String) {
        Task {
            do {
                let job = try await downloadService.start(
                    app: app,
                    version: version,
                    sourceName: sourceName,
                    progress: { [weak self] updated in
                        Task { @MainActor in self?.merge(updated) }
                    },
                    completion: { [weak self] finished in
                        Task { @MainActor in
                            self?.merge(finished)
                            switch finished.state {
                            case .completed:
                                self?.showBanner(self?.t(.downloadsValidationPassed) ?? "", style: .success)
                            case .failed:
                                self?.showBanner(self?.t(.downloadsValidationFailed) ?? "", style: .error)
                            default:
                                break
                            }
                        }
                    }
                )
                merge(job)
            } catch {
                showBanner(errorText(error), style: .error)
            }
        }
    }

    func retry(_ job: DownloadJob) {
        var version = SourceVersion(version: job.version, downloadURL: job.downloadURL, size: job.totalBytes > 0 ? job.totalBytes : nil, sha256: job.sha256)
        version.version = job.version
        let app = SourceApp(
            name: job.appName,
            bundleIdentifier: job.bundleIdentifier,
            versions: [version]
        )
        download(app: app, version: version, sourceName: job.sourceName)
    }

    func cancel(_ job: DownloadJob) {
        Task {
            do {
                try await downloadService.cancel(id: job.id)
                downloads = try await downloadService.list()
            } catch {
                showBanner(errorText(error), style: .error)
            }
        }
    }

    func delete(_ job: DownloadJob) {
        Task {
            do {
                try await downloadService.remove(id: job.id)
                downloads = try await downloadService.list()
            } catch {
                showBanner(errorText(error), style: .error)
            }
        }
    }

    func clearCompletedDownloads() {
        Task {
            do {
                try await downloadService.clearCompleted()
                downloads = try await downloadService.list()
                showBanner(t(.settingsClearSuccess), style: .success)
            } catch {
                showBanner(errorText(error), style: .error)
            }
        }
    }

    func downloadFileURL(_ job: DownloadJob) -> URL {
        paths.downloads.appendingPathComponent(job.fileName)
    }

    func iconURL(for package: AppPackage) -> URL? {
        guard let name = package.iconFileName else { return nil }
        let url = paths.icons.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func packageFileURL(_ package: AppPackage) -> URL {
        paths.ipas.appendingPathComponent(package.storedFileName)
    }

    func warningText(_ warning: InspectionWarning) -> String {
        switch warning {
        case .unsigned: t(.ipaUnsigned)
        case .encrypted: t(.ipaEncrypted)
        case .missingProvisioningProfile: t(.ipaNoProfile)
        case .noArm64Slice, .unknownArchitecture: t(.ipaIncompatible)
        case .missingIcon: t(.ipaMissingIcon)
        case .missingMinimumOS: t(.ipaMissingMinOS)
        }
    }

    private func merge(_ job: DownloadJob) {
        if let index = downloads.firstIndex(where: { $0.id == job.id }) {
            downloads[index] = job
        } else {
            downloads.append(job)
        }
        downloads.sort { $0.createdAt > $1.createdAt }
    }

    // MARK: Signing

    func importProfile(from url: URL) async {
        #if os(iOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            _ = try await signingStore.importProfile(from: url)
            signingRecords = try await signingStore.list()
            showBanner(t(.certsImportSuccess), style: .success)
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    func importIdentity(from url: URL, password: String) async {
        #if os(iOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let identity = try P12Importer.importIdentity(from: url, password: password)
            try await signingStore.add(identity)
            signingRecords = try await signingStore.list()
            showBanner(t(.certsIdentityImportSuccess), style: .success)
        } catch {
            showBanner(errorText(error), style: .error)
        }
        #else
        showBanner(t(.certsP12Unavailable), style: .error)
        #endif
    }

    func delete(_ record: SigningRecord) async {
        do {
            try await signingStore.remove(id: record.id)
            signingRecords = try await signingStore.list()
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    // MARK: JIT

    var hasPairingFile: Bool {
        FileManager.default.fileExists(atPath: pairingFileURL.path)
    }

    func importPairingFile(from url: URL) async {
        #if os(iOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try FileStore.read(url)
            guard PairingFileImporter.validate(data: data) else {
                showBanner(t(.jitPairingInvalid), style: .error)
                return
            }
            try FileStore.writeAtomically(data, to: pairingFileURL)
            capabilities.hasPairingFile = true
            showBanner(t(.jitPairingImported), style: .success)
        } catch {
            showBanner(errorText(error), style: .error)
        }
    }

    func removePairingFile() {
        try? FileStore.removeIfExists(pairingFileURL)
        capabilities.hasPairingFile = false
    }

    func refreshJITCapabilities() {
        capabilities.hasPairingFile = hasPairingFile
        capabilities.canOpenStikDebug = StikDebugLauncher.isInstalled
    }

    func useSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: Keys.language)
        language = LanguageResolver.resolve(
            override: nil,
            preferred: Locale.preferredLanguages,
            catalog: catalog
        )
    }

    @discardableResult
    func openStikDebug(bundleIdentifier: String, pid: Int32) -> Bool {
        guard let url = StikDebugHandoff.enableJITURL(bundleIdentifier: bundleIdentifier, processIdentifier: pid) else {
            return false
        }
        return StikDebugLauncher.open(url)
    }

    func openStikDebugApp() {
        if !StikDebugLauncher.openApp() {
            showBanner(t(.jitStikDebugMissing), style: .error)
        }
    }

    // MARK: Storage & maintenance

    /// Current device facts for the installation-mode planner. Kept in the app
    /// layer because it depends on imported records and device state.
    var installCapabilities: InstallCapabilities {
        #if os(iOS)
        let applePlatform = true
        #else
        let applePlatform = false
        #endif
        let developerMode: Bool?
        switch capabilities.developerModeState {
        case .enabled: developerMode = true
        case .disabled: developerMode = false
        case .unknown: developerMode = nil
        }
        return InstallCapabilities(
            isOnApplePlatform: applePlatform,
            hasSigningIdentity: signingRecords.contains { $0.kind == .certificate },
            hasPairingFile: capabilities.hasPairingFile,
            hasDeveloperMode: developerMode,
            iosMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            signingPipelineReady: false
        )
    }

    func installAvailability(for mode: InstallMode) -> InstallModeAvailability {
        InstallModePlanner.availability(of: mode, capabilities: installCapabilities)
    }

    func storageUsed() -> Int64 {
        packages.reduce(0) { $0 + $1.fileSize } + downloads.reduce(0) { total, job in
            total + ((try? FileStore.size(of: downloadFileURL(job))) ?? 0)
        }
    }

    func clearCaches() async {
        try? FileStore.removeIfExists(paths.caches)
        try? paths.prepare()
        for record in repositories {
            var cleared = record
            cleared.document = nil
            try? await repositoryService.replace(cleared)
        }
        repositories = (try? await repositoryService.list()) ?? repositories
        showBanner(t(.settingsClearSuccess), style: .success)
    }

    func resetLibrary() async {
        for package in packages {
            try? await packageStore.delete(package)
        }
        packages = (try? await packageStore.all()) ?? []
        showBanner(t(.settingsClearSuccess), style: .success)
    }

    // MARK: Diagnostics

    func makeDiagnosticReport() -> DiagnosticReport {
        let environment = PlatformInfo.environment(
            interfaceLanguage: language,
            localeIdentifier: Locale.current.identifier,
            deviceModel: DeviceInfo.modelIdentifier
        )
        let modules: [DiagnosticModule] = [
            DiagnosticModule(
                name: t(.diagnosticsModuleIPA),
                status: t(.commonSuccess),
                detail: "\(packages.count) · \(Format.bytes(packages.reduce(0) { $0 + $1.fileSize }))"
            ),
            DiagnosticModule(
                name: t(.diagnosticsModuleRepo),
                status: repositories.contains(where: { $0.lastError != nil }) ? t(.commonWarning) : t(.commonSuccess),
                detail: "\(repositories.count) · \(repositories.reduce(0) { $0 + $1.appCount }) \(t(.reposAppCount))"
            ),
            DiagnosticModule(
                name: t(.diagnosticsModuleDownloads),
                status: downloads.contains(where: { $0.state == .failed }) ? t(.commonWarning) : t(.commonSuccess),
                detail: "\(downloads.count)"
            ),
            DiagnosticModule(
                name: t(.diagnosticsModuleCerts),
                status: signingRecords.contains(where: { $0.isExpired() }) ? t(.commonWarning) : t(.commonSuccess),
                detail: "\(signingRecords.count)"
            ),
            DiagnosticModule(
                name: t(.diagnosticsModuleJIT),
                status: capabilities.hasPairingFile ? t(.commonSuccess) : t(.requiresSetup),
                detail: capabilities.canOpenStikDebug ? t(.jitInstalled) : t(.jitNotInstalled)
            ),
            DiagnosticModule(
                name: t(.diagnosticsModuleStorage),
                status: t(.commonSuccess),
                detail: Format.bytes(storageUsed())
            )
        ]
        return DiagnosticReport(
            environment: environment,
            modules: modules,
            counts: [
                "ipas": packages.count,
                "repositories": repositories.count,
                "repositoryApps": repositories.reduce(0) { $0 + $1.appCount },
                "downloads": downloads.count,
                "signingRecords": signingRecords.count
            ],
            notes: [
                t(.settingsBrandingPlaceholder),
                t(.diagnosticsPrivacyNote)
            ]
        )
    }

    func diagnosticsText() -> String {
        (try? DiagnosticBuilder.shareText(makeDiagnosticReport())) ?? ""
    }

    func exportDiagnostics() -> URL? {
        do {
            let data = try DiagnosticBuilder.encode(makeDiagnosticReport())
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("AppHub-Diagnostics-\(Int(Date().timeIntervalSince1970)).json")
            try FileStore.writeAtomically(data, to: url)
            return url
        } catch {
            showBanner(errorText(error), style: .error)
            return nil
        }
    }

    // MARK: Keys

    private enum Keys {
        static let language = "apphub.language"
        static let appearance = "apphub.appearance"
        static let jitMethod = "apphub.jitMethod"
        static let installMode = "apphub.installMode"
    }
}

extension InstallMode {
    var titleKey: L10nKey {
        switch self {
        case .otaHandoff: .installModeOta
        case .onDeviceSigning: .installModeSigning
        case .deviceBridge: .installModeBridge
        case .externalTool: .installModeExternal
        }
    }

    var detailKey: L10nKey {
        switch self {
        case .otaHandoff: .installModeOtaDetail
        case .onDeviceSigning: .installModeSigningDetail
        case .deviceBridge: .installModeBridgeDetail
        case .externalTool: .installModeExternalDetail
        }
    }

    var symbol: String {
        switch self {
        case .otaHandoff: "safari"
        case .onDeviceSigning: "signature"
        case .deviceBridge: "cable.connector"
        case .externalTool: "square.and.arrow.up"
        }
    }
}

extension InstallModeAvailability {
    var statusKey: L10nKey {
        switch self {
        case .available: .installStatusAvailable
        case .needsSigningIdentity: .installStatusNeedsIdentity
        case .needsPairingFile: .installStatusNeedsPairing
        case .needsDeveloperMode: .installStatusNeedsDeveloperMode
        case .requiresApplePlatform: .installStatusAppleOnly
        case .notImplemented: .installStatusNotImplemented
        }
    }
}
