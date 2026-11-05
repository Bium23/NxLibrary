import XCTest
@testable import NXLibraryCore

final class GameOptionsPresentationTests: XCTestCase {
    func testRenderScaleVisibilityFollowsSupport() {
        let p = GameOptionsPresentation(supportsRenderScale: true,
                                        isPlayable: true,
                                        sourcesDetached: false)
        XCTAssertTrue(p.showRenderScale)
        XCTAssertFalse(p.sourcesDetached)
    }

    func testUnsupportedRenderScaleShowsInfo() {
        let p = GameOptionsPresentation(supportsRenderScale: false,
                                        isPlayable: false,
                                        sourcesDetached: true)
        XCTAssertFalse(p.showRenderScale)
        XCTAssertFalse(p.canPlay)
        XCTAssertTrue(p.sourcesDetached)
        XCTAssertTrue(p.resolutionNote.contains("window/display"))
    }

    // MARK: - Layout

    private func presentation(renderScale: Bool = true, playable: Bool = true,
                              detached: Bool = false, blocked: Bool = false,
                              store: Bool = false, bundle: Bool = false) -> GameOptionsPresentation {
        GameOptionsPresentation(supportsRenderScale: renderScale, isPlayable: playable,
                                sourcesDetached: detached, toolchainBlocked: blocked,
                                hasStorePage: store, gameName: "Game",
                                appPath: "/Applications/Game.app", canDeleteBundle: bundle)
    }

    func testMoveRowOnlyFromSpotlight() {
        let p = presentation()
        XCTAssertTrue(p.focusableRows(level: .main, origin: .spotlight).contains(.move))
        XCTAssertFalse(p.focusableRows(level: .main, origin: .collection).contains(.move))
        XCTAssertFalse(p.focusableRows(level: .main, origin: .details).contains(.move))
    }

    func testMainRowsFollowTheSpecOrder() {
        let rows = presentation().focusableRows(level: .main, origin: .spotlight)
        XCTAssertEqual(rows.first, .play)
        XCTAssertEqual(Array(rows.prefix(8)), [.play, .editDetails, .cheats, .mods, .openSaves, .move, .favorite, .hidden])
        XCTAssertEqual(Array(rows.suffix(3)), [.rebuild, .showInFinder, .removeGame])
        XCTAssertEqual(rows.last, .removeGame)
    }

    /// Cheats is the third row, under Edit details, wherever the options open; Rebuild follows Restore defaults.
    func testCheatsRowSitsUnderEditDetails() {
        let p = presentation()
        for origin in [GameOptionsOrigin.spotlight, .collection, .details] {
            let rows = p.focusableRows(level: .main, origin: origin)
            XCTAssertEqual(Array(rows.prefix(3)), [.play, .editDetails, .cheats], "\(origin)")
            XCTAssertEqual(rows.filter { $0 == .cheats }.count, 1)
            XCTAssertEqual(rows.firstIndex(of: .cheats).map { rows[$0 + 1] }, .mods)
            XCTAssertEqual(rows.filter { $0 == .openSaves }.count, 1)
            XCTAssertEqual(rows.firstIndex(of: .restoreDefaults).map { rows[$0 + 1] }, .rebuild)
        }
        XCTAssertEqual(p.cheatsValue, "None")
        XCTAssertEqual(GameOptionsRow.cheats.title, "Cheats")
        XCTAssertEqual(GameOptionsRow.cheats.icon, .casino)
        XCTAssertTrue(GameOptionsRow.cheats.opensSubmenu, "a panel, with the value beside the chevron")
        XCTAssertEqual(p.about(.cheats), "Install and switch this game's cheats.")
        let set = GameOptionsPresentation(supportsRenderScale: true, isPlayable: true, sourcesDetached: false, cheatsValue: "3 on")
        XCTAssertEqual(set.cheatsValue, "3 on")
    }

    /// Mods follows Cheats wherever the options open, then Open saves.
    func testModsRowFollowsCheats() {
        let p = presentation()
        for origin in [GameOptionsOrigin.spotlight, .collection, .details] {
            let rows = p.focusableRows(level: .main, origin: origin)
            XCTAssertEqual(rows.filter { $0 == .mods }.count, 1, "\(origin)")
            XCTAssertEqual(rows.firstIndex(of: .cheats).map { rows[$0 + 1] }, .mods, "\(origin)")
            XCTAssertEqual(rows.firstIndex(of: .mods).map { rows[$0 + 1] }, .openSaves, "\(origin)")
        }
        XCTAssertEqual(GameOptionsRow.mods.title, "Mods")
        XCTAssertEqual(GameOptionsRow.mods.icon, .puzzle)
        XCTAssertTrue(GameOptionsRow.mods.opensSubmenu)
        XCTAssertEqual(p.about(.mods), "Turn this game's file mods on and off, and choose which one wins.")
    }

    func testModsRowValue() {
        XCTAssertEqual(presentation().modsValue, "None")
        let set = GameOptionsPresentation(supportsRenderScale: true, isPlayable: true, sourcesDetached: false, modsValue: "2 on")
        XCTAssertEqual(set.modsValue, "2 on")
        XCTAssertEqual(ModStore.rowValue(on: 0, total: 0), "None")
        XCTAssertEqual(ModStore.rowValue(on: 0, total: 3), "Off")
        XCTAssertEqual(ModStore.rowValue(on: 2, total: 3), "2 on")
    }

    /// Edit details sits under Play wherever the options open.
    func testEditDetailsUnderPlayForEveryOrigin() {
        for origin in [GameOptionsOrigin.spotlight, .collection, .details] {
            let rows = presentation().focusableRows(level: .main, origin: origin)
            XCTAssertEqual(Array(rows.prefix(2)), [.play, .editDetails], "\(origin)")
            XCTAssertEqual(rows.filter { $0 == .editDetails }.count, 1)
        }
    }

    func testRenderScaleRowOnlyWhenSupportedOtherwiseNote() {
        let supported = presentation(renderScale: true)
        XCTAssertTrue(supported.focusableRows(level: .main, origin: .details).contains(.renderScale))
        XCTAssertFalse(supported.entries(level: .main, origin: .details).contains { entry in
            if case .note = entry { return true }
            return false
        })

        let unsupported = presentation(renderScale: false)
        XCTAssertFalse(unsupported.focusableRows(level: .main, origin: .details).contains(.renderScale))
        XCTAssertTrue(unsupported.entries(level: .main, origin: .details).contains(
            .note(title: "Internal resolution", text: unsupported.resolutionNote)))
    }

    func testNextLaunchHeadingSitsBetweenHiddenAndTheRuntimeRows() {
        let entries = presentation().entries(level: .main, origin: .spotlight)
        guard let heading = entries.firstIndex(of: .heading("Next launch")),
              let hidden = entries.firstIndex(of: .row(.hidden)),
              let fullscreen = entries.firstIndex(of: .row(.fullscreen)) else {
            return XCTFail("Runtime heading or rows missing")
        }
        XCTAssertLessThan(hidden, heading)
        XCTAssertEqual(heading + 1, fullscreen)
    }

    func testEditDetailsStorePageOnlyWhenKnown() {
        XCTAssertFalse(presentation(store: false).focusableRows(level: .editDetails, origin: .details)
            .contains(.storePage))
        XCTAssertEqual(presentation(store: true).focusableRows(level: .editDetails, origin: .details).dropFirst(2).first,
                       .storePage)
    }

    func testEditDetailsEndsWithRemoveSources() {
        let rows = presentation().focusableRows(level: .editDetails, origin: .details)
        XCTAssertEqual(rows, [.changeArtwork, .changeMetadata, .attachSources, .openLog, .removeSources])
        XCTAssertEqual(GameOptionsRow.changeMetadata.title, "Change metadata")
        XCTAssertTrue(GameOptionsRow.changeMetadata.opensSubmenu)
        XCTAssertEqual(GameOptionsRow.changeArtwork.title, "Change artwork")
        XCTAssertTrue(GameOptionsRow.changeArtwork.opensSubmenu)
    }

    func testEveryRowAppearsInSomeLevel() {
        var seen = Set<GameOptionsRow>()
        for origin in [GameOptionsOrigin.spotlight, .collection, .details] {
            for store in [false, true] {
                for renderScale in [false, true] {
                    let p = presentation(renderScale: renderScale, store: store)
                    seen.formUnion(p.focusableRows(level: .main, origin: origin))
                    seen.formUnion(p.focusableRows(level: .editDetails, origin: origin))
                    seen.formUnion(savedChoices(full: true).focusableRows(level: .main, origin: origin))
                }
            }
        }
        XCTAssertEqual(seen, Set(GameOptionsRow.allCases))
    }

    func testRowKindsAreDisjoint() {
        for row in GameOptionsRow.allCases {
            let kinds = [row.isToggle, row.isChoice, row.opensSubmenu].filter { $0 }.count
            XCTAssertLessThanOrEqual(kinds, 1, "\(row)")
            XCTAssertFalse(row.title.isEmpty, "\(row)")
        }
    }

    func testDestructiveRowsAreTheRemovals() {
        XCTAssertEqual(GameOptionsRow.allCases.filter(\.isDestructive), [.removeGame, .removeSources])
    }

    // MARK: - Dimming and copy

    func testPlayDimsWhenNotPlayable() {
        XCTAssertTrue(presentation(playable: false).isDimmed(.play))
        XCTAssertFalse(presentation(playable: true).isDimmed(.play))
    }

    func testRebuildDimsWhenSourcesDetachedOrGateBlocks() {
        XCTAssertFalse(presentation().isDimmed(.rebuild))
        XCTAssertTrue(presentation(detached: true).isDimmed(.rebuild))
        XCTAssertTrue(presentation(blocked: true).isDimmed(.rebuild))
        XCTAssertFalse(presentation(blocked: true).isDimmed(.play))
    }

    func testRebuildAboutFollowsSources() {
        XCTAssertEqual(presentation().rebuildAbout,
                       "Build a new app; the old app stays if the build fails.")
        XCTAssertEqual(presentation(detached: true).rebuildAbout,
                       "Game files are missing or not attached. Attach sources in Edit details.")
        XCTAssertEqual(presentation(blocked: true).rebuildAbout,
                       "Blocked by the Metal gate. See Settings → Engine.")
        let newer = GameOptionsPresentation(supportsRenderScale: true, isPlayable: true, sourcesDetached: false,
                                            toolchainBlocked: true,
                                            toolchainHint: "Newer Metal: turn on the override in Settings → Engine")
        XCTAssertEqual(newer.rebuildAbout, "Newer Metal: turn on the override in Settings → Engine.")
        XCTAssertEqual(presentation(detached: true).attachAbout,
                       "Game files are missing or not attached. Attach them to rebuild.")
        XCTAssertEqual(presentation().attachAbout,
                       "Sources attached. Rebuild without touching saves.")
    }

    func testRemovalCopyForLibraryOnlyRemoval() {
        let copy = presentation(bundle: false).removal
        XCTAssertEqual(copy.title, "Remove Game?")
        XCTAssertEqual(copy.confirmTitle, "Remove")
        XCTAssertEqual(copy.message,
                       "This removes the library record only; /Applications/Game.app stays on disk.")
    }

    func testRemovalCopyForBundleDeletion() {
        let copy = presentation(bundle: true).removal
        XCTAssertEqual(copy.title, "Delete Game?")
        XCTAssertEqual(copy.confirmTitle, "Delete")
        XCTAssertTrue(copy.message.hasPrefix("This deletes /Applications/Game.app."))
    }

    func testInfoTooltipsExistForLongExplanations() {
        let p = presentation()
        for row: GameOptionsRow in [.fps60, .metalFX, .metalHUD, .consoleMode, .renderScale, .removeSources] {
            XCTAssertNotNil(p.info(row), "\(row)")
        }
        XCTAssertNil(p.info(.fullscreen))
    }

    func testAboutCoversEveryRow() {
        let p = presentation()
        for row in GameOptionsRow.allCases {
            XCTAssertNotNil(p.about(row), "\(row)")
        }
    }


    // MARK: - Settings from the build's list

    private func setting(_ env: String, _ kind: String, _ def: String, extra: String = "") -> LauncherSetting {
        let json = #"{"env":"\#(env)","kind":"\#(kind)","section":"Game","label":"\#(env)","default":"\#(def)"\#(extra)}"#
        return try! JSONDecoder().decode(LauncherSetting.self, from: Data(json.utf8))
    }

    /// Bananza's list; `full` adds the rows a newer build offers.
    private func savedChoices(full: Bool = false, rumble: String = "1", fixed: Set<String> = []) -> GameOptionsPresentation {
        var settings = [
            setting("DM_OPMODE", "choice", "1", extra: #","options":[["1","Docked"],["0","Handheld"]]"#),
            setting("DM_PRESENT_UPSCALE", "choice", "off", extra: #","options":[["off","Standard"],["metalfx","MetalFX"]]"#),
            setting("DM_FULLSCREEN", "choice", "0", extra: #","options":[["0","Window"],["1","Fullscreen"]]"#),
            setting("DM_RUMBLE", "toggle", "1", extra: #","on":"1","off":"0""#),
            setting("DM_RUMBLE_GAIN", "range", "1.0", extra: #","needs":"DM_RUMBLE=1","min":0,"max":3,"step":0.1"#),
            setting("DM_PSO_MTL4", "toggle", "1", extra: #","on":"1","off":"0""#),
            setting("DM_METAL_HUD", "toggle", "0", extra: #","on":"1","off":"0""#),
        ]
        if full {
            settings += [
                setting("DM_FPS_TARGET", "choice", "60", extra: #","options":[["30","30 fps"],["60","60 fps"],["120","120 fps"]]"#),
                setting("DM_UPSCALER", "choice", "game", extra: #","options":[["game","Game's own"],["metalfx","MetalFX"]]"#),
                setting("DM_LANG", "choice", "en-US", extra: #","options":[["en-US","American English"]]"#),
                setting("DM_RENDER_SCALE", "range", "1.0", extra: #","min":0.5,"max":1,"step":0.05"#),
            ]
        }
        var values = Dictionary(uniqueKeysWithValues: settings.map { ($0.env, $0.defaultValue ?? "") })
        values["DM_RUMBLE"] = rumble
        return GameOptionsPresentation(supportsRenderScale: full, isPlayable: true, sourcesDetached: false,
                                       settings: GameSettingsSnapshot(settings: settings, values: values, fixed: fixed))
    }

    func testSavedChoicesShowOnlyWhatTheBuildOffers() {
        let rows = savedChoices().focusableRows(level: .main, origin: .collection)
        for absent: GameOptionsRow in [.fps60, .frameRate, .language, .renderScale, .gameUpscaler] {
            XCTAssertFalse(rows.contains(absent), "\(absent)")
        }
        for present: GameOptionsRow in [.fullscreen, .metalFX, .metalHUD, .consoleMode, .rumble, .rumbleStrength, .moreSettings] {
            XCTAssertTrue(rows.contains(present), "\(present)")
        }
        XCTAssertEqual(savedChoices().settings?.extraSettings.map(\.env), ["DM_PSO_MTL4"])
    }

    func testNewerBuildGetsFrameRateAndUpscalerRows() {
        let rows = savedChoices(full: true).focusableRows(level: .main, origin: .collection)
        XCTAssertTrue(rows.contains(.frameRate))
        XCTAssertFalse(rows.contains(.fps60), "Frame rate replaces the 60 FPS switch")
        XCTAssertTrue(rows.contains(.gameUpscaler))
        XCTAssertTrue(rows.contains(.renderScale))
        XCTAssertTrue(rows.contains(.language))
    }

    func testRumbleStrengthNeedsRumble() {
        XCTAssertFalse(savedChoices(rumble: "0").focusableRows(level: .main, origin: .collection).contains(.rumbleStrength))
    }

    func testKeySetInEnvIsFixed() {
        let p = savedChoices(fixed: ["DM_OPMODE"])
        XCTAssertTrue(p.isDimmed(.consoleMode))
        XCTAssertEqual(p.about(.consoleMode), "Set in env.txt")
        XCTAssertFalse(p.isDimmed(.rumble))
    }

    func testLegacyBuildKeepsTodaysRows() {
        let rows = presentation().focusableRows(level: .main, origin: .collection)
        XCTAssertTrue(rows.contains(.fps60))
        XCTAssertFalse(rows.contains(.frameRate))
        XCTAssertFalse(rows.contains(.moreSettings))
    }

    func testSettingValuesStepAndLabel() {
        let gain = setting("DM_RUMBLE_GAIN", "range", "1.0", extra: #","min":0,"max":3,"step":0.1"#)
        XCTAssertEqual(GameSettingValues.label(gain, "1"), "100%")
        XCTAssertEqual(GameSettingValues.stepped(gain, from: "1", by: 1), "1.1")
        XCTAssertEqual(GameSettingValues.stepped(gain, from: "3", by: 1), "0", "wraps like the other value rows")
        XCTAssertEqual(GameSettingValues.stepped(gain, from: "0.45", by: -1), "0.4", "an off-step value moves to its neighbour")
        let fps = setting("DM_FPS_TARGET", "choice", "60", extra: #","options":[["30","30 fps"],["60","60 fps"],["120","120 fps"]]"#)
        XCTAssertEqual(GameSettingValues.label(fps, "120"), "120 fps")
        XCTAssertEqual(GameSettingValues.stepped(fps, from: "120", by: 1), "30")
        let toggle = setting("DM_PSO_MTL4", "toggle", "1", extra: #","on":"1","off":"0""#)
        XCTAssertEqual(GameSettingValues.label(toggle, "1"), "On")
        XCTAssertEqual(GameSettingValues.stepped(toggle, from: "1", by: 1), "0")
    }

    // MARK: - Focus

    func testFocusClampsAtBothEnds() {
        var focus = GameOptionsFocus()
        focus.move(by: -1, count: 3)
        XCTAssertEqual(focus.index, 0)
        focus.move(by: 1, count: 3)
        focus.move(by: 1, count: 3)
        focus.move(by: 1, count: 3)
        XCTAssertEqual(focus.index, 2)
    }

    func testFocusKeepsItsRowWhenRowsChange() {
        let after: [GameOptionsRow] = [.storePage, .attachSources, .openLog, .removeSources]
        // The view keeps the row, and re-resolves its place against the rows of each draw.
        let focus = GameOptionsFocus(row: .attachSources, in: after)
        XCTAssertEqual(focus.row(in: after), .attachSources)
    }

    func testFocusFallsBackToTopWhenItsRowIsGone() {
        let focus = GameOptionsFocus(row: .storePage, in: [.attachSources, .openLog])
        XCTAssertEqual(focus.index, 0)
        XCTAssertEqual(GameOptionsFocus(row: nil, in: [.play, .move]).index, 0)
    }

    func testFocusFindsARowAndReportsIt() {
        let rows: [GameOptionsRow] = [.play, .favorite, .hidden]
        var focus = GameOptionsFocus()
        focus.focus(.hidden, in: rows)
        XCTAssertEqual(focus.row(in: rows), .hidden)
        focus.focus(.move, in: rows)
        XCTAssertEqual(focus.row(in: rows), .hidden)
    }

    // MARK: - Values

    func testConsoleModeLabels() {
        XCTAssertEqual(GameOptionsValues.consoleModeLabel(docked: true), "Docked")
        XCTAssertEqual(GameOptionsValues.consoleModeLabel(docked: false), "Handheld")
    }

    func testRenderScaleLabelRoundsToPercent() {
        XCTAssertEqual(GameOptionsValues.renderScaleLabel(1.0), "100%")
        XCTAssertEqual(GameOptionsValues.renderScaleLabel(0.85), "85%")
        XCTAssertEqual(GameOptionsValues.renderScalePercent(0.849), 85)
    }

    func testRenderScaleStepsForwardAndWraps() {
        XCTAssertEqual(GameOptionsValues.steppedRenderScale(0.85, by: 1), 0.90, accuracy: 1e-9)
        XCTAssertEqual(GameOptionsValues.steppedRenderScale(1.0, by: 1), 0.50, accuracy: 1e-9)
        XCTAssertEqual(GameOptionsValues.steppedRenderScale(0.30, by: 1), 0.50, accuracy: 1e-9)
    }

    func testRenderScaleStepsBackwardAndWraps() {
        XCTAssertEqual(GameOptionsValues.steppedRenderScale(0.85, by: -1), 0.80, accuracy: 1e-9)
        XCTAssertEqual(GameOptionsValues.steppedRenderScale(0.50, by: -1), 1.00, accuracy: 1e-9)
    }

    func testRumbleStrengthWrapsBothWays() {
        XCTAssertEqual(GameOptionsValues.steppedRumbleStrength(0, by: -1), 3)
        XCTAssertEqual(GameOptionsValues.steppedRumbleStrength(3, by: 1), 0)
        XCTAssertEqual(GameOptionsValues.steppedRumbleStrength(1, by: 1), 2)
    }

    func testIndexStepWrapsAndStartsAtFirstWhenUnknown() {
        XCTAssertEqual(GameOptionsValues.steppedIndex(nil, by: 1, count: 3), 0)
        XCTAssertEqual(GameOptionsValues.steppedIndex(2, by: 1, count: 3), 0)
        XCTAssertEqual(GameOptionsValues.steppedIndex(0, by: -1, count: 3), 2)
        XCTAssertEqual(GameOptionsValues.steppedIndex(0, by: 1, count: 0), 0)
    }
}
