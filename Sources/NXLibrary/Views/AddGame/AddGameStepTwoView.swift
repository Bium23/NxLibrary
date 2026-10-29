import SwiftUI
import AppKit
import NXLibraryCore

struct AddGameStepTwoView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @Environment(\.seleneReduceMotion) private var reduceMotion

    let focusedAction: Int
    let onActions: ([AddGameAction]) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 18) {
                summaryPanel
                sourcesPanel
                runtimePanel
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 16) {
                destinationPanel
                advancedPanel
                warnings
                footer
                actionRow
            }
            .frame(width: 380)
        }
        .onAppear(perform: publishActions)
        .onChange(of: viewModel.canAddSelectedGame) { _ in publishActions() }
        .onChange(of: viewModel.canStartBuild) { _ in publishActions() }
        .onChange(of: viewModel.selectedLanguage) { language in
            if viewModel.pendingRuntimeConfig.language != language {
                viewModel.pendingRuntimeConfig.language = language
            }
        }
    }

    // MARK: - Summary

    private var summaryPanel: some View {
        SelenePanel {
            HStack(spacing: 16) {
                gameIcon
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.selectedGame?.name ?? "No game selected")
                        .seleneFont(34, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                    Text(versionText)
                        .seleneFont(14, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                    Text("Ready to add to your library.")
                        .seleneFont(14)
                        .foregroundColor(SeleneTheme.ink90)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var gameIcon: some View {
        if let match = libraryMatch {
            Image(nsImage: GameIconProvider.icon(for: match))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SeleneTheme.ink.opacity(0.06))
                Image(systemName: "gamecontroller.fill")
                    .seleneFont(34, .medium)
                    .foregroundColor(SeleneTheme.glyph.opacity(0.75))
            }
            .frame(width: 64, height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
            )
        }
    }

    private var libraryMatch: PortedGame? {
        guard let titleId = viewModel.selectedGame?.titleId, !titleId.isEmpty else { return nil }
        return viewModel.libraryGames.first {
            $0.titleId?.caseInsensitiveCompare(titleId) == .orderedSame
        }
    }

    private var versionText: String {
        var parts: [String] = []
        if let version = versionLabel(viewModel.selectedGame?.newestUpdate) {
            parts.append(version)
        }
        if let titleId = viewModel.selectedGame?.titleId, !titleId.isEmpty {
            parts.append(titleId)
        }
        if parts.isEmpty { parts.append("No title ID") }
        return parts.joined(separator: " · ")
    }

    private func versionLabel(_ item: GameFileItem?) -> String? {
        guard let raw = item?.versionString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw.lowercased().hasPrefix("v") ? raw : "v\(raw)"
    }

    // MARK: - Sources

    private var sourcesPanel: some View {
        SelenePanel("Sources") {
            HStack {
                Text(viewModel.selectedGame?.name ?? "No game selected")
                    .seleneFont(19, .semibold)
                    .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    .lineLimit(1)
                Spacer()
                Button("Change selection") {
                    withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                        viewModel.goToWizardStep(1)
                    }
                }
                .buttonStyle(.plain)
                .seleneFont(13, .semibold)
                .foregroundColor(SeleneTheme.glyph)
            }

            HStack(spacing: 8) {
                sourcePill("Base", count: selectedCount(.base))
                sourcePill("Updates", count: selectedCount(.update))
                sourcePill("DLC", count: selectedCount(.dlc))
                Spacer()
                Text(viewModel.formattedSelectedSourcesSize)
                    .seleneFont(13, .semibold, design: .monospaced)
                    .foregroundColor(SeleneTheme.ink60)
            }

            if let game = viewModel.selectedGame, !game.hasBase {
                warning("Base required: this folder has an update or DLC without the base game.")
            } else if !viewModel.selectedSources.contains(where: { $0.type == .base }) {
                warning("The base game must stay selected.")
            }

            Text("The base game, newest update and all non-empty DLC are selected by default.")
                .seleneFont(13)
                .foregroundColor(SeleneTheme.ink60)
        }
    }

    private func selectedCount(_ kind: SourceKind) -> Int {
        viewModel.selectedSources.filter { $0.type == kind }.count
    }

    private func sourcePill(_ title: String, count: Int) -> some View {
        Text("\(title) \(count)")
            .seleneFont(12, .bold, design: .monospaced)
            .foregroundColor(count > 0 ? SeleneTheme.ink : SeleneTheme.ink60)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SeleneTheme.ink.opacity(count > 0 ? 0.07 : 0.03))
            .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
            .clipShape(Capsule())
    }

    // MARK: - Runtime defaults

    private var runtimePanel: some View {
        SelenePanel("Runtime defaults",
                    info: "Default runtime flags passed to this game. You can customize them at any time from Game options.") {
            VStack(spacing: 9) {
                SeleneToggleRow("60 FPS",
                                subtitle: "Target 60 frames per second instead of 30.",
                                info: "Sets frame pacing target to 60 FPS (DM_PRESENT_HZ=60). Titles with physics tied to 30 FPS may run twice as fast.",
                                isOn: $viewModel.pendingRuntimeConfig.enable60FPS)
                SeleneToggleRow("Docked mode",
                                subtitle: "Use the docked performance profile for this build.",
                                info: "Emulates Nintendo Switch docked profile (1080p target with higher clock rates). Disabling uses handheld profile (720p target).",
                                isOn: $viewModel.pendingRuntimeConfig.isDockedMode)
                SeleneToggleRow("MetalFX spatial upscaling",
                                subtitle: "Enable the engine's MetalFX present upscale.",
                                info: "Uses Apple MetalFX spatial upscaling to sharpen the viewport to your display resolution without increasing internal render workload.",
                                isOn: $viewModel.pendingRuntimeConfig.enableMetalFXUpscale)
                SeleneToggleRow("Metal HUD",
                                subtitle: "Show the Metal performance overlay while playing.",
                                info: "Displays Apple's real-time Metal developer HUD overlay showing FPS, frame pacing graphs, and GPU render time.",
                                isOn: $viewModel.pendingRuntimeConfig.enableMetalHUD)
            }

            Text("Saved with the new game. Each game can override these later in Game options. Use the pointer for these toggles.")
                .seleneFont(13)
                .foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Destination and advanced

    private var destinationPanel: some View {
        SelenePanel("Destination",
                    info: "Compiles a standalone native Apple Silicon .app bundle installed atomically into ~/Applications. No emulator wrapper is used.") {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(SeleneTheme.ink.opacity(0.06))
                        .frame(width: 38, height: 38)
                    Image(systemName: "macbook.gen2")
                        .seleneFont(19, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("macOS app · Apple Silicon")
                        .seleneFont(16, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.94))
                    Text(destinationPath)
                        .seleneFont(13, .regular, design: .monospaced)
                        .foregroundColor(SeleneTheme.ink60)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("No DMG")
                    .seleneFont(11, .bold)
                    .tracking(0.6)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SeleneTheme.ink.opacity(0.05))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink15, lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
    }

    private var destinationPath: String {
        AddGameDestination.path(appName: viewModel.appName,
                                gameName: viewModel.selectedGame?.name)
    }

    private var advancedPanel: some View {
        SelenePanel("Advanced") {
            VStack(spacing: 9) {
                SeleneRow("Application name") {
                    field("Name shown in macOS",
                          text: $viewModel.appName)
                }
                SeleneRow("Bundle identifier",
                          info: "Unique reverse-domain identifier (e.g. org.nxnative.game) used by macOS to store app preferences, game saves, and window states.") {
                    field("org.nxnative.game",
                          text: $viewModel.bundleId)
                }
                SeleneRow("Game language") {
                    Picker("Game language", selection: $viewModel.selectedLanguage) {
                        ForEach(languageOptions, id: \.code) { option in
                            Text(option.label).tag(option.code)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190)
                    .accessibilityLabel("Game language")
                }
            }

            Text("Extracted files are always kept for fast rebuilds on macOS.")
                .seleneFont(13)
                .foregroundColor(SeleneTheme.ink60)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .seleneFont(14, .regular, design: .monospaced)
            .foregroundColor(SeleneTheme.ink.opacity(0.94))
            .padding(.horizontal, 9)
            .frame(width: 190, height: 28)
            .background(SeleneTheme.glass)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages
        let current = viewModel.selectedLanguage
        if !options.contains(where: { $0.code == current }) {
            options.append((current, current.isEmpty ? "Game Default" : current))
        }
        return options
    }

    // MARK: - Warnings and actions

    @ViewBuilder
    private var warnings: some View {
        if let error = viewModel.buildError {
            warning("Build failed: \(error)", actionTitle: "Dismiss") {
                viewModel.buildError = nil
            }
        }
        if viewModel.environmentStatus != nil, !viewModel.prerequisites.xcode.isAvailable {
            warning("Apple Command Line Tools are missing. A build needs them.",
                    actionTitle: "Install…") {
                viewModel.installAppleCommandLineTools()
            }
        }
        if !viewModel.isProdKeysValid {
            warning("prod.keys is missing. You can add the game now; import the key before building.",
                    actionTitle: "Import key…") {
                viewModel.selectProdKeysFile()
            }
        }
        if viewModel.isDiskSpaceLow {
            warning(viewModel.diskSpaceWarningMessage ?? "Not enough free disk space for this build.")
        }
    }

    private func warning(_ text: String,
                         actionTitle: String? = nil,
                         action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .seleneFont(15)
                .foregroundColor(SeleneTheme.untested)
            VStack(alignment: .leading, spacing: 3) {
                Text(text)
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .seleneFont(13, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.untested.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous)
                .strokeBorder(SeleneTheme.untested.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.rowRadius, style: .continuous))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(footerHint)
                .seleneFont(13)
                .foregroundColor(viewModel.canAddSelectedGame ? SeleneTheme.ink60 : SeleneTheme.untested)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footerHint: String {
        if viewModel.isScanningGameFolder { return "Scanning sources…" }
        guard let selected = viewModel.selectedGame else { return "Select a game in step 1." }
        guard selected.hasBase else {
            return "Base required: add the base game NSP/XCI before adding it."
        }
        guard !viewModel.selectedSources.isEmpty else { return "Select at least the base game." }
        if viewModel.isDiskSpaceLow {
            return viewModel.diskSpaceWarningMessage ?? "Not enough free disk space."
        }
        if viewModel.canStartBuild { return "Ready to add and build." }
        if !viewModel.isProdKeysValid { return "You can add it now; import prod.keys to build it." }
        if !viewModel.isNxnativeValid { return "You can add it now; the nxnative checkout is missing." }
        if viewModel.environmentStatus?.canBuild != true {
            return "You can add it now; the build environment is incomplete."
        }
        if !viewModel.canPassToolchainGate {
            return "You can add it now; the toolchain is not certified, so building is blocked until you enable the override in Settings."
        }
        return "You can add it now."
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            SeleneActionButton(title: "Back", kind: .secondary,
                               isFocused: focusedAction == 2) {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                    viewModel.goToWizardStep(1)
                }
            }
            Spacer()
            SeleneActionButton(title: "Add to Library",
                               kind: viewModel.canStartBuild ? .secondary : .primary,
                               isEnabled: viewModel.canAddSelectedGame,
                               isFocused: focusedAction == 0) {
                addSelectedGame(buildNow: false)
            }
            SeleneActionButton(title: "Add & Build",
                               kind: .primary,
                               isEnabled: viewModel.canStartBuild,
                               isFocused: focusedAction == 1) {
                addSelectedGame(buildNow: true)
            }
        }
    }

    private func addSelectedGame(buildNow: Bool) {
        viewModel.addSelectedGame(buildNow: buildNow)
        guard viewModel.buildError == nil, !viewModel.isBuilding else { return }
        router.showLibrary()
    }

    private func publishActions() {
        onActions([
            .init(id: "library", title: "Add to Library",
                  isEnabled: viewModel.canAddSelectedGame,
                  perform: { addSelectedGame(buildNow: false) }),
            .init(id: "build", title: "Add & Build",
                  isEnabled: viewModel.canStartBuild,
                  perform: { addSelectedGame(buildNow: true) }),
            .init(id: "back", title: "Back") {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                    viewModel.goToWizardStep(1)
                }
            }
        ])
    }
}
