import SwiftUI
import AppKit
import NXLibraryCore

struct SettingsLookSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var theme = ThemeStore.shared

    private var themeName: String {
        theme.palettes.first { $0.id == settings.settings.colorThemeID }?.name ?? theme.palette.name
    }

    private func stepTheme(_ step: Int) {
        let ids = theme.palettes.map(\.id)
        guard let next = ids.stepped(from: settings.settings.colorThemeID, step) else { return }
        settings.settings.colorThemeID = next
        theme.apply(id: next)
    }

    private var wallpaperTitle: String { theme.wallpaperTitle(for: settings.settings.wallpaperID) }

    private func stepWallpaper(_ step: Int) {
        if let next = theme.wallpaperChoices.stepped(from: settings.settings.wallpaperID, step) {
            settings.settings.wallpaperID = next
        }
    }

    private var settingsWallpaperTitle: String { theme.settingsWallpaperTitle(for: settings.settings.settingsWallpaperID) }

    private func stepSettingsWallpaper(_ step: Int) {
        if let next = theme.settingsWallpaperChoices.stepped(from: settings.settings.settingsWallpaperID, step) {
            settings.settings.settingsWallpaperID = next
        }
    }

    private func stepSizing(_ step: Int) {
        settings.settings.backgroundSizing = settings.settings.backgroundSizing.stepped(step)
    }

    private func stepBrightness(_ step: Int) {
        settings.settings.wallpaperBrightness = settings.settings.wallpaperBrightness.stepped(step)
    }

    private func stepShade(_ step: Int) {
        settings.settings.backgroundShade = settings.settings.backgroundShade.stepped(step)
    }

    private func stepIcon(_ step: Int) {
        viewModel.iconAppearanceMode = AppIconAppearanceMode.selectable.stepped(from: viewModel.iconAppearanceMode, step) ?? .auto
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading("Theme")

            SeleneCycleRow("Color theme",
                           subtitle: "Interface colours",
                           value: themeName) { stepTheme($0) }

            SettingsSubheading("Wallpaper")

            SeleneCycleRow("Wallpaper",
                           subtitle: "App background",
                           value: wallpaperTitle) { stepWallpaper($0) }

            SeleneCycleRow("Settings wallpaper",
                           subtitle: "Settings background",
                           value: settingsWallpaperTitle) { stepSettingsWallpaper($0) }

            SeleneCycleRow("Wallpaper sizing",
                           subtitle: "Image fit",
                           info: "Fill crops to cover, Fit shows all of it, Stretch distorts it to fit. Applies to wallpapers.",
                           value: settings.settings.backgroundSizing.title) { stepSizing($0) }

            SeleneCycleRow("Wallpaper brightness",
                           subtitle: "Wallpaper light",
                           info: "Dim applies an even shade; Bright on the right keeps the left dim for text.",
                           value: settings.settings.wallpaperBrightness.title) { stepBrightness($0) }

            SeleneToggleRow("Background motion",
                            subtitle: "Wallpaper & moonlight",
                            isOn: $settings.settings.animatedBackground)

            SettingsSubheading("Library screens")

            SeleneToggleRow("Game backgrounds",
                            subtitle: "Spotlight & Collection",
                            info: "On shows the selected game's artwork; Off keeps your wallpaper. Details and the launch screen keep their own artwork settings.",
                            isOn: Binding(get: { !settings.settings.keepWallpaperOnGames },
                                          set: { settings.settings.keepWallpaperOnGames = !$0 }))

            SeleneCycleRow("Library shade",
                           subtitle: "Behind library text",
                           value: settings.settings.backgroundShade.label) { stepShade($0) }

            SeleneToggleRow("Text shadow",
                            subtitle: "Text readability",
                            isOn: $settings.settings.readableText)

            SettingsSubheading("Screen")

            SeleneToggleRow("Clock",
                            subtitle: "Top bar",
                            isOn: $settings.settings.showClock)

            SeleneToggleRow("Reduce motion",
                            subtitle: "Reduced transitions",
                            isOn: $settings.settings.reduceMotion)

            SeleneCycleRow("App icon",
                           subtitle: "Dock & app",
                           value: viewModel.iconAppearanceMode.label) { stepIcon($0) }

            SettingsSubheading("Artwork")

            SeleneButtonRow("Box covers",
                            subtitle: "GameTDB covers",
                            buttonTitle: "Open GameTDB") {
                NSWorkspace.shared.open(GameTDB.siteURL)
            }

            SeleneButtonRow("SteamGridDB",
                            subtitle: viewModel.hasSteamGridDBKey
                                ? "Key saved · covers, backgrounds, logos and icons in Change artwork"
                                : "Add your free API key to find art in Change artwork",
                            buttonTitle: viewModel.hasSteamGridDBKey ? "Remove key" : "Add key") {
                steamGridDBAction()
            }
        }
        .onAppear(perform: publishActions)
    }

    private func steamGridDBAction() {
        if viewModel.hasSteamGridDBKey { viewModel.removeSteamGridDBKey() } else { viewModel.isEditingSteamGridDBKey = true }
    }

    private func publishActions() {
        onActions([
            .value("theme", "Color theme") { stepTheme($0) },
            .value("wallpaper", "Wallpaper") { stepWallpaper($0) },
            .value("settingsWallpaper", "Settings wallpaper") { stepSettingsWallpaper($0) },
            .value("sizing", "Wallpaper sizing") { stepSizing($0) },
            .value("brightness", "Wallpaper brightness") { stepBrightness($0) },
            .init(id: "animated", title: "Background motion") {
                settings.settings.animatedBackground.toggle()
            },
            .init(id: "keepWallpaper", title: "Game backgrounds") {
                settings.settings.keepWallpaperOnGames.toggle()
            },
            .value("shade", "Library shade") { stepShade($0) },
            .init(id: "shadow", title: "Text shadow") {
                settings.settings.readableText.toggle()
            },
            .init(id: "clock", title: "Clock") {
                settings.settings.showClock.toggle()
            },
            .init(id: "motion", title: "Reduce motion") {
                settings.settings.reduceMotion.toggle()
            },
            .value("icon", "App icon") { stepIcon($0) },
            .init(id: "covers", title: "Box covers") {
                NSWorkspace.shared.open(GameTDB.siteURL)
            },
            .init(id: "SteamGridDB", title: "SteamGridDB") { steamGridDBAction() }
        ])
    }
}
