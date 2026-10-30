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
        XCTAssertEqual(Array(rows.prefix(5)), [.play, .editDetails, .move, .favorite, .hidden])
        XCTAssertEqual(Array(rows.suffix(4)), [.rebuild, .showInFinder, .openSaves, .removeGame])
        XCTAssertEqual(rows.last, .removeGame)
    }

    /// Edit details sits under Play wherever the options open.
    func testEditDetailsUnderPlayForEveryOrigin() {
        for origin in [GameOptionsOrigin.spotlight, .collection, .details] {
            let rows = presentation().focusableRows(level: .main, origin: origin)
            XCTAssertEqual(Array(rows.prefix(2)), [.play, .editDetails], "\(origin)")
            XCTAssertEqual(rows.filter { $0 == .editDetails }.count, 1)
        }
    }

    /// On Selene each kind of row has its own icon colour; the dangerous ones keep the danger red.
    func testRowsHaveIconColoursByKind() {
        for row in GameOptionsRow.allCases {
            if row.isDestructive {
                XCTAssertNil(row.iconTint, "\(row)")
            } else {
                XCTAssertEqual(row.iconTint?.count, 7, "\(row) has a #RRGGBB colour")
            }
        }
        XCTAssertGreaterThanOrEqual(Set(GameOptionsRow.allCases.compactMap(\.iconTint)).count, 6)
        XCTAssertNotEqual(GameOptionsRow.play.iconTint, GameOptionsRow.favorite.iconTint)
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

    func testRuntimeHeadingSitsBetweenHiddenAndTheRuntimeRows() {
        let entries = presentation().entries(level: .main, origin: .spotlight)
        guard let heading = entries.firstIndex(of: .heading("Runtime")),
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
                       "A base source is required. Attach sources in Edit details.")
        XCTAssertEqual(presentation(blocked: true).rebuildAbout,
                       "Blocked by the Metal gate. See Settings → Engine.")
        XCTAssertEqual(presentation(detached: true).attachAbout,
                       "Sources are detached. Attach them to rebuild.")
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
