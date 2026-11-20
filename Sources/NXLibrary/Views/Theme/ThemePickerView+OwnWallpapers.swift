import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// The player's own wallpapers: adding one from a file and removing it after a confirmation.
extension ThemePickerView {
    /// A plain macOS open panel: picking a file needs the pointer anyway.
    func addOwn() {
        let live = state.tab == .live
        let panel = NSOpenPanel()
        panel.message = live
            ? L10n.text("Choose a video for your live background (MP4, MOV or M4V). Arcane keeps its own copy and plays it muted.")
            : L10n.text("Choose a picture for your background. Arcane keeps its own copy.")
        panel.allowedContentTypes = live
            ? WallpaperCatalog.videoExtensions.compactMap { UTType(filenameExtension: $0) }
            : [.image]
        panel.allowsMultipleSelection = false
        errorTitle = live ? L10n.text("Couldn't add the video") : L10n.text("Couldn't add the picture")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try theme.importWallpaper(from: url)
            state.backgroundIndex = backgrounds.firstIndex(of: .wallpaper(id)) ?? state.backgroundIndex
            SoundEffectService.shared.play(.click)
        } catch {
            viewModel.showSettingsNotice(title: errorTitle, message: error.localizedDescription)
        }
    }

    /// Y on your own wallpaper or a download: asks first.
    func removeFocused() {
        guard state.step == .background, browser.state == nil, case .wallpaper(let id) = focusedBackground,
              ThemeStore.isRemovable(id) else { return }
        removalFocus = .cancel
        removal = id
        SoundEffectService.shared.play(.focus)
    }

    func handleRemoval(_ action: GamepadAction) {
        switch action {
        case .navigateLeft:
            if removalFocus != .cancel { removalFocus = .cancel; SoundEffectService.shared.play(.focus) }
        case .navigateRight:
            if removalFocus != .confirm { removalFocus = .confirm; SoundEffectService.shared.play(.focus) }
        case .confirm:
            removalFocus == .confirm ? confirmRemoval() : keepIt()
        case .cancel:
            keepIt()
        default: break
        }
    }

    private func keepIt() {
        removal = nil
        SoundEffectService.shared.play(.focus)
    }

    private func confirmRemoval() {
        guard let id = removal else { return }
        removal = nil
        do {
            try theme.removeWallpaper(id: id)
            if settings.settings.wallpaperID == id { settings.settings.wallpaperID = nil }
            if settings.settings.settingsWallpaperID == id { settings.settings.settingsWallpaperID = nil }
            state.backgroundIndex = min(state.backgroundIndex, backgrounds.count - 1)
            SoundEffectService.shared.play(.click)
        } catch {
            errorTitle = L10n.text("Couldn't remove it")
            viewModel.showSettingsNotice(title: errorTitle, message: error.localizedDescription)
        }
    }

    /// A calm question: what goes, where it goes, and that it can come back.
    func removalDialog(_ id: String) -> some View {
        let video = theme.wallpaper(for: id)?.kind == .video
        let removalTitle = video ? L10n.text("Remove this video?") : L10n.text("Remove this picture?")
        let downloaded = !id.hasPrefix(WallpaperCatalog.custom + "/")
        let name = theme.credits[id]?.title ?? theme.wallpaperTitle(for: id)
        var message = downloaded
            ? L10n.format("%@ goes to the Trash, so you can bring it back from there, or download it again whenever you like.", [String(describing: name)])
            : L10n.format("Arcane's copy of %@ goes to the Trash, so you can bring it back from there. Your original file stays where it is.", [String(describing: name)])
        if settings.settings.wallpaperID == id { message += L10n.text(" Your theme’s own background takes its place.") }
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { keepIt() }
            SeleneConfirmDialog(title: removalTitle, message: message, confirmTitle: "Remove",
                                cancelTitle: L10n.text("Keep it"), focus: $removalFocus,
                                onCancel: keepIt, onConfirm: confirmRemoval)
        }
    }
}
