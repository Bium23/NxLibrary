import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// Input: opening, tabs, the gamepad, moving the focus, taps, accepting and going back.
extension ThemePickerView {
    // MARK: - Input

    func open() {
        guard !opened else { return }
        opened = true
        let themeIndex = palettes.firstIndex { $0.id == settings.settings.colorThemeID } ?? 0
        state = ThemePickerState(themeIndex: themeIndex, backgroundIndex: 0)
        focusSetting(themeID: theme.palette.id)
    }

    /// Opens the tab that holds the current setting, on its tile.
    private func focusSetting(themeID: String) {
        let id = settings.settings.wallpaperID
        state.tab = ThemeBackgrounds.tab(for: id, wallpapers: theme.wallpapers)
        state.backgroundIndex = ThemeBackgrounds.index(
            of: id, in: ThemeBackgrounds.list(state.tab, themeID: themeID, wallpapers: theme.wallpapers, current: id))
    }

    func switchTab(to tab: BackgroundTab) {
        if state.switchTab(to: tab) { SoundEffectService.shared.play(.focus) }
    }

    private func stepTab(_ offset: Int) {
        let tabs = BackgroundTab.allCases
        guard let current = tabs.firstIndex(of: state.tab) else { return }
        let next = current + offset
        guard tabs.indices.contains(next) else { return }
        switchTab(to: tabs[next])
    }

    func handle(_ action: GamepadAction) {
        if removal != nil { return handleRemoval(action) }
        if placing != nil { return handlePlacement(action) }
        if state.step == .background, browser.state != nil { return handleBrowse(action) }
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .confirm: accept()
        case .cancel: back()
        case .contextAction: removeFocused()
        case .secondaryAction:
            if case .wallpaper(let id) = focusedBackground, let credit = theme.credits[id] {
                NSWorkspace.shared.open(credit.pageURL)
            }
        case .tabPrevious: stepTab(-1)
        case .tabNext: stepTab(1)
        default: break
        }
    }

    private func move(_ direction: GridDirection) {
        let count = state.step == .theme ? palettes.count : backgrounds.count
        if state.move(direction, count: count) { SoundEffectService.shared.play(.focus) }
    }

    /// A click focuses a tile; a click on the focused one chooses it.
    func tap(_ index: Int) {
        switch state.step {
        case .theme:
            if index == state.themeIndex { return accept() }
            state.themeIndex = index
        case .background:
            if index == state.backgroundIndex { return accept() }
            state.backgroundIndex = index
        }
        SoundEffectService.shared.play(.focus)
    }

    func accept() {
        switch state.step {
        case .theme:
            let palette = palettes[min(state.themeIndex, palettes.count - 1)]
            settings.settings.colorThemeID = palette.id
            theme.apply(id: palette.id)
            focusSetting(themeID: palette.id)
            state.step = .background
            SoundEffectService.shared.play(.click)
        case .background:
            if let browse = browser.state {
                if let item = browse.focusedItem {
                    choose(item)
                } else if browse.category.isSearch {
                    searchFocused = true
                }
                return
            }
            switch focusedBackground {
            case .add:
                addOwn()
                return
            case .theme: askPlacement(nil)
            case .none: askPlacement(WallpaperCatalog.none)
            case .wallpaper(let id): askPlacement(id)
            case .online(let source):
                openSource(source)
            }
        }
    }

    func back() {
        SoundEffectService.shared.play(.focus)
        if transfer.itemID != nil { return transfer.cancel() }
        if searchFocused { searchFocused = false; return }
        if state.step == .background, browser.state != nil { return browser.close() }
        switch state.step {
        case .theme: router.isThemePickerOpen = false
        case .background: state.step = .theme
        }
    }
}
