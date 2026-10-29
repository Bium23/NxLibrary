import SwiftUI
import NXLibraryCore

struct SettingsGeneralSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void

    private var readiness: Bool {
        viewModel.isProdKeysValid
            && viewModel.isNxnativeValid
            && viewModel.environmentStatus?.canBuild == true
            && viewModel.canPassToolchainGate
    }

    var body: some View {
        VStack(spacing: 9) {
            SeleneValueRow("Opens on",
                           subtitle: "NX Library always opens on the library.",
                           value: "Library")

            SeleneToggleRow("Restore last selected game",
                            subtitle: "Reopen the game that was selected when you quit.",
                            isOn: $settings.settings.restoreLastGame)

            SeleneToggleRow("Check engine at launch",
                            subtitle: "Verify the pinned engine commit and toolchain when the app starts.",
                            info: "Checks ~/nxnative against the certified engine commit and confirms your installed Metal compiler matches the lock file before builds are attempted.",
                            isOn: $settings.settings.checkEngineAtLaunch)

            SeleneToggleRow("Refresh library at launch",
                            subtitle: "Rescan the app library for new or removed builds.",
                            isOn: $settings.settings.refreshLibraryAtLaunch)

            SeleneButtonRow("Setup",
                            subtitle: "Folders, keys and prerequisites in one guided flow.",
                            buttonTitle: "Open Setup") {
                viewModel.reopenSetup()
            }

            SeleneButtonRow("Environment",
                            subtitle: viewModel.isCheckingPrerequisites
                                ? "Checking Xcode, Metal, Python and the engine..."
                                : "Re-run the environment and compatibility checks.",
                            buttonTitle: "Re-check") {
                viewModel.detectEnvironment()
            }

            SelenePanel("Readiness",
                        info: "Summarizes the 4 essential gates: valid prod.keys, cloned nxnative repository, Python build environment, and certified Metal compiler version.") {
                HStack(spacing: 9) {
                    Circle()
                        .fill(readiness ? SeleneTheme.success : SeleneTheme.untested)
                        .frame(width: 8, height: 8)
                    Text(readiness ? "Ready to build and play"
                                   : "Setup needed or builds blocked")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink)
                    Spacer()
                }

                Text(readinessLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isCheckingPrerequisites) { _ in publishActions() }
    }

    private var readinessLine: String {
        let engine = seleneShort(viewModel.pinnedEngineCommit)
        let metal = viewModel.installedMetalVersion ?? "Metal unknown"
        let xcode = viewModel.environmentStatus?.xcodeVersion ?? "Xcode unknown"
        let python = viewModel.environmentStatus?.pythonURL == nil ? "Python missing" : "Python venv ready"
        return "Engine \(engine) · \(metal) · \(xcode) · \(python)"
    }

    private func publishActions() {
        onActions([
            .init(id: "opensOn", title: "Opens on") {},
            .init(id: "restore", title: "Restore last selected game") {
                settings.settings.restoreLastGame.toggle()
            },
            .init(id: "engine", title: "Check engine at launch") {
                settings.settings.checkEngineAtLaunch.toggle()
            },
            .init(id: "refresh", title: "Refresh library at launch") {
                settings.settings.refreshLibraryAtLaunch.toggle()
            },
            .init(id: "setup", title: "Setup") {
                viewModel.reopenSetup()
            },
            .init(id: "recheck", title: "Environment", isEnabled: !viewModel.isCheckingPrerequisites) {
                viewModel.detectEnvironment()
            }
        ])
    }
}
