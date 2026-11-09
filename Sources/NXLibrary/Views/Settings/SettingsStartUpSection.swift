import SwiftUI
import NXLibraryCore

struct SettingsStartUpSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    let onChooseLanguage: () -> Void
    let onChooseRegion: () -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var startOnTitle: String {
        switch settings.settings.startOn {
        case .spotlight: return "Spotlight"
        case .collection: return "Collection"
        case .last: return L10n.text("Where I left")
        }
    }

    private var readiness: Bool {
        viewModel.isProdKeysValid
            && viewModel.isNxnativeValid
            && viewModel.environmentStatus?.canBuild == true
            && viewModel.canPassToolchainGate
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading(L10n.text("Language & region"))
            SeleneButtonRow("App language",
                            subtitle: "Menus, genres and available game descriptions. The games’ own language stays separate.",
                            buttonTitle: settings.settings.appLanguage.nativeName, action: onChooseLanguage)
            SeleneButtonRow("Regional formats", id: "Region",
                            subtitle: "Dates, numbers and sizes only. Game descriptions follow the app language.",
                            buttonTitle: settings.settings.appRegion.flatMap {
                                L10n.context.formatLocale.localizedString(forRegionCode: $0)
                            } ?? L10n.text("Automatic (Mac)"), action: onChooseRegion)

            SeleneCycleRow("Start on",
                           subtitle: "The screen NX Library opens on.",
                           value: startOnTitle) { step in
                settings.settings.startOn = settings.settings.startOn.stepped(step)
            }

            SeleneToggleRow("Restore last selected game",
                            subtitle: "Reopen the game that was selected when you quit.",
                            isOn: $settings.settings.restoreLastGame)

            SeleneToggleRow("Start in fullscreen",
                            subtitle: "Applies at the next launch.",
                            isOn: $settings.settings.startInFullscreen)

            SeleneToggleRow("Check engine at launch",
                            subtitle: "Verify the pinned engine commit and toolchain when the app starts.",
                            info: "Checks the nxnative checkout against the certified engine commit and confirms your installed Metal compiler matches the lock file before builds are attempted.",
                            isOn: $settings.settings.checkEngineAtLaunch)

            SeleneToggleRow("Refresh library at launch",
                            subtitle: "Rescan the app library for new or removed builds.",
                            isOn: $settings.settings.refreshLibraryAtLaunch)

            SeleneToggleRow("Check for app updates",
                            subtitle: "Look for a newer NX Library release at launch, at most once a day.",
                            isOn: $settings.settings.checkAppUpdatesAtLaunch)

            SeleneToggleRow("Intro animation",
                            subtitle: "Plays a short opening with the boot sound when the app opens.",
                            isOn: $settings.settings.introAnimation)

            SettingsSubheading(L10n.text("Setup"))

            SeleneButtonRow("Setup",
                            subtitle: "Open the Setup check: what NX Library needs and what is ready.",
                            buttonTitle: "Open Setup") {
                viewModel.reopenSetup()
            }
            .disabled(viewModel.isBuilding || viewModel.isUpdatingApp)

            SeleneButtonRow("Environment",
                            subtitle: "Re-run the environment and compatibility checks.",
                            buttonTitle: "Re-check") {
                viewModel.detectEnvironment()
            }
            .disabled(viewModel.isBuilding || viewModel.isUpdatingApp)

            SelenePanel(L10n.text("Readiness"),
                        info: L10n.text("Summarizes the 4 essential gates: valid prod.keys, cloned nxnative repository, Python build environment, and certified Metal compiler version.")) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(readiness ? SeleneTheme.success : SeleneTheme.untested)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isCheckingEnvironment ? L10n.text("Checking…")
                         : viewModel.environmentStatus == nil && viewModel.setupCompleted ? L10n.text("Not checked")
                         : readiness ? L10n.text("Ready to build and play") : L10n.text("Setup needed or builds blocked"))
                        .seleneFont(16, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                    Spacer()
                }

                Text(readinessLine)
                    .seleneFont(13, .regular, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.isBuilding) { _ in publishActions() }
        .onChange(of: viewModel.isUpdatingApp) { _ in publishActions() }
        .onChange(of: settings.settings.appLanguage) { _ in publishActions() }
        .onChange(of: settings.settings.appRegion) { _ in publishActions() }
    }

    private var readinessLine: String {
        let engine = seleneShort(viewModel.pinnedEngineCommit)
        let metal = viewModel.installedMetalVersion ?? L10n.text("Metal unknown")
        let xcode = viewModel.environmentStatus?.xcodeVersion ?? L10n.text("Xcode unknown")
        let python = viewModel.environmentStatus?.pythonURL == nil ? L10n.text("Python missing")
            : viewModel.engineToolchain.isBundled ? L10n.text("Python included") : L10n.text("Python venv ready")
        return L10n.format("Engine %@ · %@ · %@ · %@", [String(describing: (engine)), String(describing: (metal)), String(describing: (xcode)), String(describing: (python))])
    }

    private func publishActions() {
        onActions([
            .init(id: "appLanguage", title: "App language", activate: onChooseLanguage),
            .init(id: "appRegion", title: L10n.text("Regional formats"), rowID: "Region", activate: onChooseRegion),
            .value("startOn", "Start on") { step in
                settings.settings.startOn = settings.settings.startOn.stepped(step)
            },
            .init(id: "restore", title: "Restore last selected game") {
                settings.settings.restoreLastGame.toggle()
            },
            .init(id: "startupFullscreen", title: "Start in fullscreen") {
                settings.settings.startInFullscreen.toggle()
            },
            .init(id: "engine", title: "Check engine at launch") {
                settings.settings.checkEngineAtLaunch.toggle()
            },
            .init(id: "refresh", title: "Refresh library at launch") {
                settings.settings.refreshLibraryAtLaunch.toggle()
            },
            .init(id: "appUpdates", title: "Check for app updates") {
                settings.settings.checkAppUpdatesAtLaunch.toggle()
            },
            .init(id: "intro", title: "Intro animation") {
                settings.settings.introAnimation.toggle()
            },
            .init(id: "setup", title: "Setup", isEnabled: !viewModel.isBuilding && !viewModel.isUpdatingApp) {
                viewModel.reopenSetup()
            },
            .init(id: "recheck", title: "Environment", isEnabled: !viewModel.isBuilding && !viewModel.isUpdatingApp) {
                viewModel.detectEnvironment()
            }
        ])
    }
}
