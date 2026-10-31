import SwiftUI
import NXLibraryCore

/// The rows of each Add game step. The first rows are the step's next move (as
/// Play leads Game options); details and settings follow under small headings.
extension AddGameView {
    func rows(for step: Int) -> [AddGameRow] {
        switch step {
        case 1: return chooseRows
        case 2: return reviewRows
        default: return portingRows
        }
    }

    /// The row a step opens on.
    func defaultRowID(for step: Int) -> String {
        switch step {
        case 1: return viewModel.canAddSelectedGame ? "continue" : "choose"
        case 2: return viewModel.canStartBuild ? "build" : "library"
        default: return portingRows.first(where: \.focusable)?.id ?? ""
        }
    }

    // MARK: - Choose

    private var chooseRows: [AddGameRow] {
        var rows: [AddGameRow] = []
        let folder = viewModel.selectedGameFolder
        rows.append(AddGameRow(id: "choose", kind: .action { viewModel.selectGameFolder() },
                               icon: .folder, title: folder == nil ? "Choose folder" : "Change folder",
                               about: folder.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                                   ?? "A folder with your NSP, XCI or NSZ files. You can also drop them here."))
        if let game = viewModel.selectedGame {
            rows.append(AddGameRow(id: "continue", kind: .action(goToReview), icon: .chevron,
                                   title: "Continue",
                                   about: "\(game.name) · \(sourceCountText) · \(viewModel.formattedSelectedSourcesSize)",
                                   enabled: viewModel.canAddSelectedGame))
        }
        if viewModel.isScanningGameFolder {
            rows.append(AddGameRow(id: "scanning", kind: .note, title: "Reading the folder…"))
        }
        if let error = viewModel.scanError {
            rows.append(AddGameRow(id: "scanError", kind: .warning(action: nil),
                                   title: "Could not read this folder", about: error))
        }
        if let error = viewModel.dropErrorMessage {
            rows.append(AddGameRow(id: "dropError", kind: .warning(action: nil), title: error))
        }
        if folder != nil, !viewModel.isScanningGameFolder, viewModel.detectedGames.isEmpty, viewModel.scanError == nil {
            rows.append(AddGameRow(id: "empty", kind: .note, title: "No games were found in this folder."))
        }
        if viewModel.detectedGames.count > 1 {
            rows.append(AddGameRow(id: "gamesHeading", kind: .heading, title: "Games in this folder"))
            for game in viewModel.detectedGames {
                rows.append(AddGameRow(id: "game:\(game.id)", kind: .action { viewModel.selectedGame = game },
                                       title: game.name, about: game.summaryText, compact: true,
                                       checked: viewModel.selectedGame?.id == game.id))
            }
        }
        if let game = viewModel.selectedGame {
            rows.append(AddGameRow(id: "sourcesHeading", kind: .heading, title: "Sources"))
            if !game.hasBase {
                rows.append(AddGameRow(id: "noBase", kind: .warning(action: nil), title: "Base game required",
                                       about: "This folder has an update or DLC but no base game."))
            }
            for item in game.files {
                let isBase = item.type == .base
                rows.append(AddGameRow(
                    id: "source:\(item.id)",
                    kind: .toggle(Binding(get: { viewModel.selectedSourceIDs.contains(item.id) },
                                          set: { on in
                                              if on != viewModel.selectedSourceIDs.contains(item.id) {
                                                  viewModel.toggleSource(item)
                                              }
                                          })),
                    title: item.name, about: sourceAbout(item), compact: true))
                if isBase { rows[rows.count - 1].enabled = false }
            }
            rows.append(AddGameRow(id: "sourcesNote", kind: .note,
                                   title: "The base game stays in. One update at a time; DLC one by one."))
        }
        rows += readinessRows(includeBuildError: false)
        rows.append(AddGameRow(id: "destination", kind: .note, title: destinationNote))
        return rows
    }

    private var sourceCountText: String {
        let count = viewModel.selectedSources.count
        return count == 1 ? "1 source" : "\(count) sources"
    }

    private func sourceAbout(_ item: GameFileItem) -> String {
        var parts = [item.type.title]
        if let raw = item.versionString?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            parts.append(raw.lowercased().hasPrefix("v") ? raw : "v\(raw)")
        }
        parts.append(item.formattedSize)
        return parts.joined(separator: " · ")
    }

    private func goToReview() {
        guard viewModel.canAddSelectedGame else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.standard) { viewModel.goToWizardStep(2) }
    }

    // MARK: - Review

    private var reviewRows: [AddGameRow] {
        var rows: [AddGameRow] = [
            AddGameRow(id: "build", kind: .action { addSelectedGame(buildNow: true) }, icon: .build,
                       title: "Add and port", about: buildHint, enabled: viewModel.canStartBuild),
            AddGameRow(id: "library", kind: .action { addSelectedGame(buildNow: false) }, icon: .add,
                       title: "Add to library only", about: "Port it later from the game's page.",
                       enabled: viewModel.canAddSelectedGame),
            AddGameRow(id: "sources", kind: .action {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) { viewModel.goToWizardStep(1) }
            }, icon: .folder, title: "Change sources",
               about: "\(sourceCountText) · \(viewModel.formattedSelectedSourcesSize)"),
            AddGameRow(id: "runtimeHeading", kind: .heading, title: "Runtime defaults"),
            toggle("fps60", "60 FPS", "Twice the frame rate; some games run too fast.",
                   $viewModel.pendingRuntimeConfig.enable60FPS),
            toggle("docked", "Docked mode", "The docked profile: 1080p and higher clocks.",
                   $viewModel.pendingRuntimeConfig.isDockedMode),
            toggle("metalFX", "MetalFX upscaling", "Sharper picture at your display's resolution.",
                   $viewModel.pendingRuntimeConfig.enableMetalFXUpscale),
            toggle("metalHUD", "Metal HUD", "Frame rate and GPU time over the game.",
                   $viewModel.pendingRuntimeConfig.enableMetalHUD),
            AddGameRow(id: "runtimeNote", kind: .note, title: "Each game can change these later in Game options."),
            AddGameRow(id: "appHeading", kind: .heading, title: "App"),
        ]
        let languages = languageOptions
        let current = languages.firstIndex { $0.code == viewModel.selectedLanguage } ?? 0
        rows.append(AddGameRow(id: "language", kind: .choice(values: languages.map(\.label), index: current) { index in
            guard languages.indices.contains(index) else { return }
            viewModel.selectedLanguage = languages[index].code
            viewModel.pendingRuntimeConfig.language = languages[index].code
        }, title: "Game language", compact: true))
        rows.append(AddGameRow(id: "appName", kind: .field($viewModel.appName, placeholder: viewModel.selectedGame?.name ?? "Name"),
                               title: "App name", compact: true))
        rows.append(AddGameRow(id: "bundleID", kind: .field($viewModel.bundleId, placeholder: "org.nxnative.game"),
                               title: "Bundle identifier", compact: true))
        rows += readinessRows(includeBuildError: true)
        rows.append(AddGameRow(id: "destination", kind: .note, title: destinationNote))
        return rows
    }

    private func toggle(_ id: String, _ title: String, _ about: String, _ isOn: Binding<Bool>) -> AddGameRow {
        AddGameRow(id: id, kind: .toggle(isOn), title: title, about: about, compact: true)
    }

    private var buildHint: String {
        if viewModel.canStartBuild { return "Builds the Mac app now; you can keep using the library meanwhile." }
        if !viewModel.isProdKeysValid { return "Import prod.keys first." }
        if viewModel.keyCheckBlocks, let readiness = viewModel.keyCheck?.readiness { return "\(readiness.title)." }
        if !viewModel.isNxnativeValid { return "The nxnative checkout is missing." }
        if viewModel.environmentStatus?.canBuild != true { return "The build environment is incomplete." }
        if !viewModel.canPassToolchainGate { return "The toolchain is not certified; enable the override in Settings." }
        return "Not available yet."
    }

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages
        let current = viewModel.selectedLanguage
        if !options.contains(where: { $0.code == current }) {
            options.append((current, current.isEmpty ? "Game default" : current))
        }
        return options
    }

    private func addSelectedGame(buildNow: Bool) {
        viewModel.addSelectedGame(buildNow: buildNow)
        guard viewModel.buildError == nil, !viewModel.isBuilding else { return }
        router.showLibrary()
    }

    // MARK: - Readiness

    private func readinessRows(includeBuildError: Bool) -> [AddGameRow] {
        var rows: [AddGameRow] = []
        if includeBuildError, let error = viewModel.buildError {
            rows.append(AddGameRow(id: "buildError", kind: .warning(action: {
                viewModel.buildError = nil
                viewModel.portingFailureReason = nil
            }), title: viewModel.portingFailureReason?.title ?? "The last porting failed", about: error))
        }
        if !viewModel.isProdKeysValid {
            rows.append(AddGameRow(id: "keys", kind: .action { viewModel.selectProdKeysFile() }, icon: .key,
                                   title: "Import prod.keys",
                                   about: "Copied once to Application Support, readable only by you."))
        }
        if viewModel.isProdKeysValid, let readiness = viewModel.keyCheck?.readiness {
            if readiness.warning {
                rows.append(AddGameRow(id: "keyCheck", kind: .warning(action: nil),
                                       title: readiness.title, about: readiness.about))
                rows.append(AddGameRow(id: "keys", kind: .action { viewModel.selectProdKeysFile() }, icon: .key,
                                       title: "Import prod.keys",
                                       about: "Copied once to Application Support, readable only by you."))
            } else {
                rows.append(AddGameRow(id: "keyCheck", kind: .note, title: "\(readiness.title). \(readiness.about)"))
            }
        }
        if let environment = viewModel.environmentStatus, environment.xcodeVersion == nil {
            rows.append(AddGameRow(id: "xcode", kind: .action { viewModel.reopenSetup() }, icon: .checklist,
                                   title: "Open Setup", about: "Xcode is not ready; a porting needs it."))
        }
        if viewModel.isDiskSpaceLow {
            rows.append(AddGameRow(id: "disk", kind: .warning(action: nil), title: "Not enough disk space",
                                   about: viewModel.diskSpaceWarningMessage))
        }
        return rows
    }

    private var destinationNote: String {
        let path = AddGameDestination.path(appName: viewModel.appName, gameName: viewModel.selectedGame?.name)
        return "Installs to \(path). On a failure or a cancel the previous app stays as it was."
    }

    // MARK: - Porting

    /// The porting step's actions (published by `AddGameStepThreeView`) as rows; its log has its own toggle.
    private var portingRows: [AddGameRow] {
        guard actionsStep == 3 else { return [] }
        return actions.filter { $0.id != "log" }.map { action in
            AddGameRow(id: action.id, kind: .action(action.perform), icon: Self.portingIcons[action.id] ?? .chevron,
                       title: action.title, enabled: action.isEnabled, destructive: action.id == "cancel")
        }
    }

    private static let portingIcons: [String: MaterialIcon] = [
        "cancel": .close, "openLog": .history, "console": .terminal, "play": .play,
        "library": .collections, "another": .add, "reveal": .folder, "retry": .restartAlt,
        "options": .tune, "review": .chevronLeft, "portAnyway": .restartAlt, "engine": .settings,
        "setup": .checklist, "keys": .key, "storage": .storage, "diagnostics": .info,
    ]
}
