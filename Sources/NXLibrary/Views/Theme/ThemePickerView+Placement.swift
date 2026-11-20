import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// Placement: asking how a chosen wallpaper fills the screen and applying the answer.
extension ThemePickerView {
    // MARK: - Placement

    /// A chosen background; `id` nil is the theme's own.
    struct PendingWallpaper: Equatable {
        let id: String?
    }

    func askPlacement(_ id: String?) {
        placementFocus = WallpaperPlacement.allCases.count - 1
        placing = PendingWallpaper(id: id)
        SoundEffectService.shared.play(.click)
    }

    func handlePlacement(_ action: GamepadAction) {
        let last = WallpaperPlacement.allCases.count - 1
        switch action {
        case .navigateLeft:
            if placementFocus > 0 { placementFocus -= 1; SoundEffectService.shared.play(.focus) }
        case .navigateRight:
            if placementFocus < last { placementFocus += 1; SoundEffectService.shared.play(.focus) }
        case .confirm:
            place(WallpaperPlacement.allCases[placementFocus])
        case .cancel:
            place(.notNow)
        default: break
        }
    }

    /// Everywhere and Settings only apply it and close the menu; Not now keeps the gallery open, nothing changed.
    private func place(_ placement: WallpaperPlacement) {
        guard let pending = placing else { return }
        placing = nil
        placement.apply(pending.id, to: &settings.settings)
        if placement == .notNow {
            SoundEffectService.shared.play(.focus)
            return
        }
        SoundEffectService.shared.play(.click)
        router.closeMenu()
    }

    func placementDialog(_ pending: PendingWallpaper) -> some View {
        let name = pending.id == WallpaperCatalog.none ? L10n.text("No wallpaper")
            : pending.id.flatMap { theme.credits[$0]?.title } ?? theme.wallpaperTitle(for: pending.id)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { place(.notNow) }
            SeleneChoiceDialog(title: WallpaperPlacement.dialogTitle,
                               message: L10n.format("%@. You can change both wallpapers any time in Settings → Look.", [String(describing: name)]),
                               choices: WallpaperPlacement.allCases.map(\.title), focus: $placementFocus) { index in
                place(WallpaperPlacement.allCases[index])
            }
        }
    }
}
