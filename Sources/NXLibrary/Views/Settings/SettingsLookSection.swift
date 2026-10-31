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
        viewModel.iconAppearanceMode = viewModel.iconAppearanceMode.stepped(step)
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading("Theme")

            SeleneCycleRow("Color theme",
                           subtitle: "The palette for focus, text and backgrounds.",
                           value: themeName) { stepTheme($0) }

            SeleneCycleRow("Wallpaper",
                           subtitle: "The picture behind the base gradient. Import more under Sound & music.",
                           value: wallpaperTitle) { stepWallpaper($0) }

            SeleneCycleRow("Settings wallpaper",
                           subtitle: "The picture behind Settings: the same as the app's, or one of its own.",
                           value: settingsWallpaperTitle) { stepSettingsWallpaper($0) }

            SeleneToggleRow("Keep wallpaper on games",
                            subtitle: "Spotlight and Collection keep your wallpaper instead of the focused game's art. A game's page still shows its art.",
                            isOn: $settings.settings.keepWallpaperOnGames)

            SeleneCycleRow("Background sizing",
                           subtitle: "Fill crops to cover, Fit shows all of it, Stretch distorts it to fit.",
                           value: settings.settings.backgroundSizing.title) { stepSizing($0) }

            SeleneCycleRow("Wallpaper brightness",
                           subtitle: "Like Selene dims it evenly; Bright on the right keeps the left dim for text.",
                           value: settings.settings.wallpaperBrightness.title) { stepBrightness($0) }

            SeleneToggleRow("Animated background",
                            subtitle: "The moonlight's beam and motes move and a live background plays; off, they hold still.",
                            isOn: $settings.settings.animatedBackground)

            SeleneCycleRow("Background shade",
                           subtitle: "How much the game art is darkened behind text.",
                           value: settings.settings.backgroundShade.label) { stepShade($0) }

            SeleneToggleRow("Text shadow",
                            subtitle: "Adds a soft shadow under text so it reads over bright art.",
                            isOn: $settings.settings.readableText)

            SettingsSubheading("Screen")

            SeleneToggleRow("Clock",
                            subtitle: "Shows the time in the top bar.",
                            isOn: $settings.settings.showClock)

            SeleneToggleRow("Reduce motion",
                            subtitle: "Replaces slides and zooms with fades.",
                            isOn: $settings.settings.reduceMotion)

            SeleneCycleRow("App icon",
                           subtitle: "Changes the Dock icon and the in-app mark.",
                           value: viewModel.iconAppearanceMode.rawValue) { stepIcon($0) }

            SettingsSubheading("Artwork")

            SeleneButtonRow("Box covers",
                            subtitle: "From GameTDB, a community database. A missing cover can be added there.",
                            buttonTitle: "Open GameTDB") {
                NSWorkspace.shared.open(GameTDB.siteURL)
            }
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .value("theme", "Color theme") { stepTheme($0) },
            .value("wallpaper", "Wallpaper") { stepWallpaper($0) },
            .value("settingsWallpaper", "Settings wallpaper") { stepSettingsWallpaper($0) },
            .init(id: "keepWallpaper", title: "Keep wallpaper on games") {
                settings.settings.keepWallpaperOnGames.toggle()
            },
            .value("sizing", "Background sizing") { stepSizing($0) },
            .value("brightness", "Wallpaper brightness") { stepBrightness($0) },
            .init(id: "animated", title: "Animated background") {
                settings.settings.animatedBackground.toggle()
            },
            .value("shade", "Background shade") { stepShade($0) },
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
            }
        ])
    }
}
