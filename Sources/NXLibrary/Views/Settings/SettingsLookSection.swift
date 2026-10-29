import SwiftUI
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

            SeleneRow("SteamGridDB key",
                      subtitle: "Lets NX Library fetch square tiles, logos and hero art for your games.",
                      info: "SteamGridDB is a free community database of game artwork. Create a free account at steamgriddb.com and generate an API key in Preferences → API.") {
                TextField("Optional API key", text: $settings.settings.steamGridDbApiKey)
                    .textFieldStyle(.plain)
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink)
                    .padding(.horizontal, canvas.u(16))
                    .padding(.vertical, canvas.u(6))
                    .background(Capsule().fill(SeleneTheme.ink.opacity(0.13)))
                    .frame(width: canvas.u(320))
            }
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .value("theme", "Color theme") { stepTheme($0) },
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
            .value("icon", "App icon") { stepIcon($0) }
        ])
    }
}
