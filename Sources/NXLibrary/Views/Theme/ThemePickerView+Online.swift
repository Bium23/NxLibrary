import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// Online backgrounds: opening a source, its input, categories, search and using a chosen image.
extension ThemePickerView {
    // MARK: - Online

    func openSource(_ source: BackgroundSourceID) {
        searchText = ""
        browser.open(source)
        SoundEffectService.shared.play(.click)
    }

    func handleBrowse(_ action: GamepadAction) {
        if transfer.itemID != nil {
            if action == .cancel { back() }
            return
        }
        switch action {
        case .navigateUp: browseMove(.up)
        case .navigateDown: browseMove(.down)
        case .navigateLeft: browseMove(.left)
        case .navigateRight: browseMove(.right)
        case .tabPrevious, .jumpToStart: stepCategory(-1)
        case .tabNext, .jumpToEnd: stepCategory(1)
        case .confirm: accept()
        case .cancel: back()
        case .secondaryAction:
            if let item = browser.state?.focusedItem { NSWorkspace.shared.open(item.pageURL) }
        default: break
        }
    }

    private func browseMove(_ direction: GridDirection) {
        if searchFocused { searchFocused = false }
        if browser.update({ $0.move(direction) }) { SoundEffectService.shared.play(.focus) }
    }

    private func stepCategory(_ offset: Int) {
        guard let browse = browser.state else { return }
        tapChip(browse.categoryIndex + offset)
    }

    func tapChip(_ index: Int) {
        guard let browse = browser.state, browse.categories.indices.contains(index) else { return }
        if index == browse.categoryIndex {
            browser.update { $0.focus = .chips; return true }
            if browse.category.isSearch { searchFocused = true }
            return
        }
        browser.update { $0.categoryIndex = index; return true }
        searchFocused = browser.state?.category.isSearch == true
        SoundEffectService.shared.play(.focus)
    }

    func tapTile(_ index: Int) {
        if browser.state?.focus == .tile(index) { return accept() }
        browser.update { $0.focus = .tile(index); return true }
        SoundEffectService.shared.play(.focus)
    }

    func submitSearch() {
        let words = searchText
        browser.update { $0.search(words); return true }
        searchFocused = false
    }

    /// A on an online item: apply it if it is here already, else download it first.
    func choose(_ item: OnlineBackground) {
        let id = OnlineDownload.wallpaperID(for: item)
        if theme.wallpapers.contains(where: { $0.id == id }) { return use(id) }
        SoundEffectService.shared.play(.click)
        transfer.start(item) { result in
            switch result {
            case .success(let id):
                theme.reloadWallpapers()
                use(id)
            case .failure(let error):
                errorTitle = L10n.text("Couldn't download the wallpaper")
                viewModel.showSettingsNotice(title: errorTitle, message: error.localizedDescription)
            }
        }
    }

    private func use(_ id: String) {
        browser.close()
        state.tab = ThemeBackgrounds.tab(for: id, wallpapers: theme.wallpapers)
        state.backgroundIndex = ThemeBackgrounds.index(of: id, in: backgrounds)
        askPlacement(id)
    }
}
