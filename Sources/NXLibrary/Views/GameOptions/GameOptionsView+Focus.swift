import SwiftUI
import AppKit
import NXLibraryCore

/// Focus: setting it, moving it, and entering and leaving Edit details.
extension GameOptionsView {
    // MARK: - Focus

    func setFocus(_ row: GameOptionsRow) {
        if row != focusedRow { infoRow = nil }
        pickedRow = row
    }

    func moveFocus(by delta: Int) {
        let rows = self.rows
        let previous = focusedRow
        var focus = GameOptionsFocus(row: pickedRow, in: rows)
        focus.move(by: delta, count: rows.count)
        pickedRow = focus.row(in: rows)
        if focusedRow != previous {
            infoRow = nil
            SoundEffectService.shared.play(.focus)
        }
    }

    func enterEditDetails() {
        // Pin the focus to the first row now; a Store page that arrives later goes above it without moving it.
        pickedRow = presentation.focusableRows(level: .editDetails, origin: origin).first
        infoRow = nil
        level = .editDetails
        // The store link needs the store metadata; Details asks for it the same way.
        store.loadStoreMetadata(for: current)
    }

    func leaveEditDetails() {
        infoRow = nil
        level = .main
        // Back on the main list, the focus returns to Edit details, where it was left.
        pickedRow = .editDetails
        SoundEffectService.shared.play(.focus)
    }
}
