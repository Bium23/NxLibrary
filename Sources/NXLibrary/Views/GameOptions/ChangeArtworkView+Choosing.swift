import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// Choosing a tile, a browsed image or a file, and saving it as the player's pick.
extension ChangeArtworkView {
    // MARK: - Choosing

    func choose(_ tile: Tile) {
        message = nil
        switch tile {
        case .automatic:
            guard hasPick || slot == .icon else { return }
            if hasPick {
                do { try subject.removeArtwork(slot) } catch {
                    message = error.localizedDescription
                    SoundEffectService.shared.play(.error)
                    return
                }
            }
            applied()
            if slot == .icon, let macApp { appIcon.appIconPickChanged(for: macApp, removed: true) }
        case .iconLocation:
            guard let macApp else { return }
            editingIconLocation = true
            appIconFocus = appIcon.usesIconOnMac(for: macApp) ? .confirm : .cancel
            askAppIcon = true
            SoundEffectService.shared.play(.click)
        case .yourPick:
            SoundEffectService.shared.play(.click)
        case .art(let item):
            if browsing != nil { chooseBrowsed(item) } else { save(item.art.data) }
        case .browse(let source):
            SoundEffectService.shared.play(.click)
            mainFocus = focus
            if source.needsKey && !viewModel.hasSteamGridDBKey {
                pendingBrowse = source
                viewModel.isEditingSteamGridDBKey = true
            } else {
                openBrowse(source)
            }
        case .file:
            SoundEffectService.shared.play(.click)
            chooseFile()
        }
    }

    /// Downloads the full image, saves it and returns to the grid with it as Your pick.
    private func chooseBrowsed(_ item: Found) {
        guard !downloading, let source = browsing else { return }
        downloading = true
        SoundEffectService.shared.play(.click)
        Task { @MainActor in
            let data = await ArtworkCandidates.chosenData(item.art)
            downloading = false
            guard browsing == source else { return }
            guard let data else {
                message = L10n.format("The full image could not be downloaded from %@. Try again.", [String(describing: source.title)])
                SoundEffectService.shared.play(.error)
                return
            }
            closeBrowse()
            save(data)
        }
    }

    private func save(_ data: Data) {
        do {
            try subject.saveArtwork(data, slot: slot)
            applied()
            // The check moves to Your pick, second in the grid.
            focus = 1
            iconPicked()
        } catch {
            message = error.localizedDescription
            SoundEffectService.shared.play(.error)
        }
    }

    /// Screens reload their art from the new revision; decoded copies of the old art go.
    private func applied() {
        if let macApp { GameArtLoader.shared.forget(macApp) }
        SoundEffectService.shared.play(.click)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.format("Choose a %@ for %@.", [String(describing: slot.title.lowercased()), String(describing: subject.name)])
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            message = L10n.text("That file could not be read.")
            SoundEffectService.shared.play(.error)
            return
        }
        save(data)
    }
}
