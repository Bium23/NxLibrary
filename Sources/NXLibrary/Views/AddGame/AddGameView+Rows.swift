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
        case 1: return viewModel.canAddSelectedGame ? "continue" : "chooseFiles"
        case 2: return viewModel.canStartBuild ? "build" : "library"
        default: return portingRows.first(where: \.focusable)?.id ?? ""
        }
    }

    // MARK: - Choose

    private var chooseRows: [AddGameRow] {
        var rows: [AddGameRow] = []
        let folder = viewModel.selectedGameFolder
        rows.append(AddGameRow(id: "chooseFiles", kind: .action { viewModel.selectGameFiles() },
                               icon: .add, title: "Choose game files", about: "NSP, XCI, NSZ, XCZ or a Switch 2 NUP."))
        rows.append(AddGameRow(id: "choose", kind: .action { viewModel.selectGameFolder() },
                               icon: .folder, title: folder == nil ? "Choose folder" : "Change folder",
                               about: folder.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                                   ?? "Game packages or an extracted game folder. You can also drop them here."))
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
                                   title: viewModel.detectedGames.isEmpty ? "Could not read this folder" : "Some files were skipped", about: error))
        }
        if let error = viewModel.dropErrorMessage {
            rows.append(AddGameRow(id: "dropError", kind: .warning(action: nil), title: error))
        }
        if folder != nil, !viewModel.isScanningGameFolder, viewModel.detectedGames.isEmpty, viewModel.scanError == nil {
            rows.append(AddGameRow(id: "empty", kind: .note, title: "No games were found in this folder."))
        }
        if viewModel.detectedGames.count > 1 {
            rows.append(AddGameRow(id: "gamesHeading", kind: .heading, title: "Choose a game"))
            for game in viewModel.detectedGames {
                rows.append(AddGameRow(id: "game:\(game.id)", kind: .action { viewModel.selectedGame = game },
                                       title: game.name, about: "\(game.summaryText) · \(game.titleId ?? game.id)", compact: true,
                                       checked: viewModel.selectedGame?.id == game.id))
            }
        }
        if let game = viewModel.selectedGame {
            rows.append(AddGameRow(id: "sourcesHeading", kind: .heading, title: "Sources"))
            if !game.hasGame {
                rows.append(AddGameRow(id: "noBase", kind: .warning(action: nil), title: "Base game required",
                                       about: "This folder has an update or DLC but no base game."))
            } else if game.isUpdateOnly {
                // The engine's NO_BASE note (nxnative 777a5f6c): nothing in the file proves the update is complete.
                let folder = game.files.contains { $0.layout == .extracted }
                rows.append(AddGameRow(id: "updateOnlyNUP", kind: .warning(action: nil),
                                       title: folder ? "No base game in this folder" : "No base game in this NUP",
                                       about: "The selected update is played as the whole game. If the game stops on "
                                           + (folder ? "missing files, add the base game's dump (base/exefs and base/romfs)."
                                                     : "missing files, use a NUP that includes the base game.")))
            }
            // The same note for an NSP, a NUP or a folder: the engine makes a provisional profile for each.
            if !viewModel.hasVerifiedEngineProfile(titleId: game.titleId) {
                rows.append(AddGameRow(id: "noProfile", kind: .warning(action: nil), title: "Not tested with this engine yet",
                                       about: "The engine has no profile for this game, so it makes a provisional one. "
                                           + "The porting may stop, or the game may not start."))
            }
            for item in game.files {
                let locked = SourceSelection.isLocked(item, in: game.files, selected: viewModel.selectedSourceIDs)
                rows.append(AddGameRow(
                    id: "source:\(item.id)",
                    kind: .toggle(Binding(get: { viewModel.selectedSourceIDs.contains(item.id) },
                                          set: { on in
                                              if on != viewModel.selectedSourceIDs.contains(item.id) {
                                                  viewModel.toggleSource(item)
                                              }
                                          })),
                    title: item.name, about: sourceAbout(item), compact: true))
                if locked { rows[rows.count - 1].enabled = false }
            }
            rows.append(AddGameRow(id: "sourcesNote", kind: .note,
                                   title: game.isUpdateOnly
                                       ? "One update at a time; bundled DLC stay together."
                                       : "The base stays in. One update at a time; bundled DLC stay together."))
        }
        rows += readinessRows(includeBuildError: false)
        rows.append(destinationRow)
        return rows
    }

    private var sourceCountText: String {
        let count = Set(viewModel.selectedSources.map { $0.url.resolvingSymlinksInPath().path }).count
        return count == 1 ? "1 source" : "\(count) sources"
    }

    private func sourceAbout(_ item: GameFileItem) -> String {
        var parts = [item.type.title]
        if let raw = item.versionString?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            parts.append(raw.lowercased().hasPrefix("v") ? raw : "v\(raw)")
        }
        let bundled = viewModel.selectedGame?.files.contains { $0.id != item.id && $0.url == item.url } == true
        if bundled && item.type != .base { parts.append(item.layout == .container ? "In the NUP file" : "In package") }
        else { parts.append(item.layout == .extracted ? "Extracted folder" : item.formattedSize) }
        return parts.joined(separator: " · ")
    }

    func goToReview() {
        guard viewModel.canAddSelectedGame else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.standard) { viewModel.goToWizardStep(2) }
    }

    // MARK: - Review

    private var reviewRows: [AddGameRow] {
        var rows: [AddGameRow] = [
            AddGameRow(id: "build", kind: .action { addSelectedGame(buildNow: true) }, icon: .build,
                       title: viewModel.selectedLibraryGame == nil ? "Add and port" : "Rebuild", about: buildHint, enabled: viewModel.canStartBuild),
            AddGameRow(id: "library", kind: .action { addSelectedGame(buildNow: false) }, icon: .add,
                       title: viewModel.selectedLibraryGame == nil ? "Add to library only" : "Save changes",
                       about: viewModel.selectedLibraryGame == nil ? "Port later" : "Next launch",
                       enabled: viewModel.canAddSelectedGame),
            AddGameRow(id: "sources", kind: .action {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) { viewModel.goToWizardStep(1) }
            }, icon: .folder, title: "Change sources",
               about: "\(sourceCountText) · \(viewModel.formattedSelectedSourcesSize)"),
            AddGameRow(id: "runtimeHeading", kind: .heading, title: "Next launch"),
            toggle("fps60", "60 FPS", "Frame-rate target",
                   $viewModel.pendingRuntimeConfig.enable60FPS),
            toggle("docked", "Docked mode", "Console profile",
                   $viewModel.pendingRuntimeConfig.isDockedMode),
            toggle("metalFX", "MetalFX upscaling", "Sharper scaling of the whole picture to your screen",
                   $viewModel.pendingRuntimeConfig.enableMetalFXUpscale),
            toggle("metalHUD", "Metal HUD", "Performance overlay",
                   $viewModel.pendingRuntimeConfig.enableMetalHUD),
            AddGameRow(id: "appHeading", kind: .heading, title: "App"),
        ]
        let languages = languageOptions
        let current = languages.firstIndex { $0.code == viewModel.pendingRuntimeConfig.language } ?? 0
        rows.append(AddGameRow(id: "language", kind: .choice(values: languages.map(\.label), index: current) { index in
            guard languages.indices.contains(index) else { return }
            viewModel.pendingRuntimeConfig.language = languages[index].code
        }, title: "Game language", compact: true))
        rows.append(AddGameRow(id: "appName", kind: .field($viewModel.appName, placeholder: viewModel.selectedGame?.name ?? "Name"),
                               title: "App name", compact: true))
        if viewModel.selectedLibraryGame == nil {
            rows.append(AddGameRow(id: "bundleID", kind: .field($viewModel.bundleId, placeholder: "org.nxnative.game"),
                                   title: "Bundle identifier", compact: true))
        }
        rows += readinessRows(includeBuildError: true)
        rows.append(destinationRow)
        return rows
    }

    private func toggle(_ id: String, _ title: String, _ about: String, _ isOn: Binding<Bool>) -> AddGameRow {
        AddGameRow(id: id, kind: .toggle(isOn), title: title, about: about, compact: true)
    }

    private var buildHint: String {
        if viewModel.canStartBuild { return "Builds the Mac app now; you can keep using the library meanwhile." }
        if !viewModel.supportsSources(viewModel.selectedSources) { return "These sources need a newer engine." }
        if viewModel.selectedSourcesRequireKeys && !viewModel.isProdKeysValid { return "Import prod.keys first." }
        if viewModel.keyCheckBlocks, let readiness = viewModel.keyCheck?.readiness { return "\(readiness.title)." }
        if !viewModel.isNxnativeValid { return "The nxnative checkout is missing." }
        if viewModel.environmentStatus?.canBuild != true { return "The build environment is incomplete." }
        if !viewModel.canPassToolchainGate { return "The toolchain is not certified; enable the override in Settings." }
        return "Not available yet."
    }

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages
        let current = viewModel.pendingRuntimeConfig.language
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
        if viewModel.selectedSourcesRequireKeys && !viewModel.isProdKeysValid {
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

    private var destinationRow: AddGameRow {
        if let problem = viewModel.buildDestinationProblem {
            return AddGameRow(id: "destination", kind: .warning(action: nil), title: "App folder unavailable", about: problem)
        }
        return AddGameRow(id: "destination", kind: .note,
                          title: "Installs to \(viewModel.selectedBuildAppURL.path). On a failure or a cancel the previous app stays as it was.")
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
