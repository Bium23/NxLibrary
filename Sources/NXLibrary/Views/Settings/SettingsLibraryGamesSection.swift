import SwiftUI
import NXLibraryCore
import ArcanePorting

/// Library → Games: how every game launches and closes, Surprise me and the hidden games.
struct SettingsLibraryGamesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    /// Games hidden from Game options, by name (the library keeps them sorted).
    private var hiddenGames: [PortedGame] {
        viewModel.libraryGames.filter(\.isHidden)
    }

    private func unhide(_ game: PortedGame) {
        SoundEffectService.shared.play(.click)
        viewModel.toggleHidden(game)
    }

    private var surprisePoolTitle: String {
        switch settings.settings.surprisePool {
        case .installed: return "Installed"
        case .notPlayed: return "Not played yet"
        case .all: return "All games"
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading(L10n.text("All games"))

            SeleneCycleRow("Launch screen style",
                           subtitle: "Artwork layout",
                           value: settings.settings.launchStyle.title) { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            }

            SeleneToggleRow("Launch screen motion",
                            subtitle: "Artwork drift",
                            isOn: $settings.settings.launchMotion)

            SeleneCycleRow("Launch screen shade",
                           subtitle: "Launch brightness",
                           value: settings.settings.launchShade.title) { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            }

            SeleneToggleRow("Session card",
                            subtitle: "Your playtime when a game closes",
                            info: "When you close a game, a card shows how long you played this time and in total. Sessions under 10 seconds show none.",
                            isOn: $settings.settings.showsSessionCard)

            SeleneCycleRow("Surprise me pool",
                           subtitle: "Which games Surprise me picks from.",
                           value: surprisePoolTitle) { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            }

            SettingsSubheading(L10n.text("Hidden games"))

            if hiddenGames.isEmpty {
                Text(L10n.text("No hidden games. Hide one from its Game options; it comes back here."))
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, canvas.u(26))
            } else {
                ForEach(hiddenGames) { game in
                    SeleneButtonRow(game.name, id: "hidden-\(game.id)",
                                    subtitle: "Out of Spotlight, Collection, Surprise me and search.", verbatimTitle: true,
                                    buttonTitle: "Show") { unhide(game) }
                }
            }

        }
        .onAppear(perform: publishActions)
        .onChange(of: hiddenGames.map(\.id)) { publishActions() }
    }

    private func publishActions() {
        let hidden = hiddenGames.map { game in
            SettingsRowAction(id: "hidden-\(game.id)", title: game.name, rowID: "hidden-\(game.id)") { unhide(game) }
        }
        onActions(launchActions + hidden)
    }

    private var launchActions: [SettingsRowAction] {
        [
            .value("launchStyle", "Launch screen style") { step in
                settings.settings.launchStyle = settings.settings.launchStyle.stepped(step)
            },
            .init(id: "launchMotion", title: L10n.text("Launch screen motion"), rowID: "Launch screen motion") {
                settings.settings.launchMotion.toggle()
            },
            .value("launchShade", "Launch screen shade") { step in
                settings.settings.launchShade = settings.settings.launchShade.stepped(step)
            },
            .init(id: "showsSessionCard", title: L10n.text("Session card"), rowID: "Session card") {
                settings.settings.showsSessionCard.toggle()
            },
            .value("surprisePool", "Surprise me pool") { step in
                settings.settings.surprisePool = settings.settings.surprisePool.stepped(step)
            }
        ]
    }
}
