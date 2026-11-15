import SwiftUI
import AppHubCore

struct JITView: View {
    @Environment(AppModel.self) private var model
    @State private var showPairingImporter = false
    @State private var bundleIdentifier = ""
    @State private var pidText = ""

    private var pid: Int32? {
        guard let value = Int32(pidText.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private var canHandoff: Bool {
        !bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty
            && pid != nil
            && model.capabilities.canOpenStikDebug
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                methodCard
                prerequisites
                instructions
                handoff
                disclaimer
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(model.t(.jitTitle))
        .onAppear { model.refreshJITCapabilities() }
        .fileImporter(
            isPresented: $showPairingImporter,
            allowedContentTypes: FileTypes.pairingImportTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task { await model.importPairingFile(from: url) }
            case let .failure(error):
                model.reportImportPickerFailure(error)
            }
        }
    }

    private var statusCard: some View {
        GlassPanel(cornerRadius: 26, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.t(.jitTitle))
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(model.t(.jitDisclaimer))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    StatusChip(
                        text: model.capabilities.hasPairingFile ? model.t(.jitPairingImported) : model.t(.jitPairingMissing),
                        tone: model.capabilities.hasPairingFile ? .positive : .warning,
                        symbol: model.capabilities.hasPairingFile ? "checkmark" : "exclamationmark"
                    )
                    StatusChip(
                        text: model.capabilities.canOpenStikDebug ? model.t(.jitInstalled) : model.t(.jitNotInstalled),
                        tone: model.capabilities.canOpenStikDebug ? .positive : .neutral,
                        symbol: "app.badge"
                    )
                }
            }
        }
    }

    private var methodCard: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.jitMethod), subtitle: model.t(.jitSettingsMethodNote))
                Picker(model.t(.jitMethod), selection: Binding(
                    get: { model.jitMethod },
                    set: { model.jitMethod = $0 }
                )) {
                    ForEach(JITMethod.allCases.filter(\.isAvailableInThisBuild)) { method in
                        Text(methodTitle(method)).tag(method)
                    }
                    Text(model.t(.jitMethodBuiltin)).tag(JITMethod.builtIn)
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if !model.jitMethod.isAvailableInThisBuild {
                    Text(model.t(.jitBuiltinUnavailable))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func methodTitle(_ method: JITMethod) -> String {
        switch method {
        case .stikDebug: model.t(.jitMethodStikDebug)
        case .waitForDebugger: model.t(.jitMethodWait)
        case .builtIn: model.t(.jitMethodBuiltin)
        }
    }

    private var prerequisites: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.jitAvailability))
                JITStatusRow(
                    label: model.t(.jitIosVersion),
                    value: DeviceInfo.systemVersion,
                    tone: .info,
                    symbol: "iphone"
                )
                JITStatusRow(
                    label: model.t(.jitDeveloperMode),
                    value: model.t(.commonUnknown),
                    tone: .neutral,
                    symbol: "wrench.and.screwdriver"
                )
                JITStatusRow(
                    label: model.t(.jitPairingFile),
                    value: model.capabilities.hasPairingFile ? model.t(.commonYes) : model.t(.commonNo),
                    tone: model.capabilities.hasPairingFile ? .positive : .warning,
                    symbol: "doc.badge.key"
                )
                JITStatusRow(
                    label: model.t(.jitStikDebug),
                    value: model.capabilities.canOpenStikDebug ? model.t(.jitInstalled) : model.t(.jitNotInstalled),
                    tone: model.capabilities.canOpenStikDebug ? .positive : .neutral,
                    symbol: "app.badge"
                )

                HStack(spacing: 10) {
                    Button {
                        showPairingImporter = true
                    } label: {
                        Label(model.t(.jitImportPairing), systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if model.capabilities.hasPairingFile {
                        Button(role: .destructive) {
                            model.removePairingFile()
                        } label: {
                            Text(model.t(.commonRemove))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer(minLength: 0)

                    Button {
                        model.openStikDebugApp()
                    } label: {
                        Label(model.t(.jitOpenStikDebug), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!model.capabilities.canOpenStikDebug)
                }
                .padding(.top, 2)
            }
        }
    }

    private var instructions: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: model.t(.jitInstructions))
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 9) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(model.palette.secondary, in: Circle())
                        Text(step)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if needsComputerForPairing {
                    Text(model.t(.jitPairingNote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// On-device pairing was added in iOS/iPadOS 27. Older versions need a
    /// computer once to create the pairing file, so say it instead of implying
    /// that everything can be done on the device.
    private var needsComputerForPairing: Bool {
        guard let major = Int(DeviceInfo.systemVersion.split(separator: ".").first ?? "") else {
            return false
        }
        return major > 0 && major < 27
    }

    private var steps: [String] {
        [
            model.t(.jitStep1),
            model.t(.jitStep2),
            model.t(.jitStep3),
            model.t(.jitStep4),
            model.t(.jitStep5)
        ]
    }

    private var handoff: some View {
        GlassPanel(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: model.t(.jitTargetApp), subtitle: model.t(.jitHandoffNote))

                TextField(model.t(.jitBundleID), text: $bundleIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField(model.t(.jitPid), text: $pidText)
                    .keyboardType(.numberPad)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(model.t(.jitPidHelp))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    guard let pid else { return }
                    if !model.openStikDebug(bundleIdentifier: bundleIdentifier, pid: pid) {
                        model.showBanner(model.t(.jitStikDebugMissing), style: .error)
                    }
                } label: {
                    Label(model.t(.jitOpenStikDebug), systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canHandoff)
            }
        }
    }

    private var disclaimer: some View {
        GlassPanel(cornerRadius: 20, padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield")
                    .foregroundStyle(.secondary)
                Text(model.t(.jitBuiltinUnavailable))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct JITStatusRow: View {
    let label: String
    let value: String
    let tone: ChipTone
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(label)
                .font(.footnote)
            Spacer(minLength: 8)
            StatusChip(text: value, tone: tone)
        }
    }
}
