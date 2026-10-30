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

    private func stepSizing(_ step: Int) {
        settings.settings.backgroundSizing = settings.settings.backgroundSizing.stepped(step)
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

            SeleneCycleRow("Background sizing",
                           subtitle: "Fill crops to cover, Fit shows all of it, Stretch distorts it to fit.",
                           value: settings.settings.backgroundSizing.title) { stepSizing($0) }

            SeleneToggleRow("Animated background",
                            subtitle: "A soft light beam and slow drifting particles over the base gradient.",
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
            .value("sizing", "Background sizing") { stepSizing($0) },
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
