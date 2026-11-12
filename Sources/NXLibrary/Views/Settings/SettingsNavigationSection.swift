import SwiftUI
import NXLibraryCore

struct SettingsNavigationSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var buttonNamesTitle: String {
        switch settings.settings.buttonNames {
        case .automatic: return L10n.text("Automatic")
        case .nintendo: return "Nintendo"
        case .xbox: return "Xbox"
        case .playstation: return "PlayStation"
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SeleneToggleRow("Button hints",
                            subtitle: "Shows the button prompts along the bottom of the screen.",
                            isOn: $settings.settings.showButtonHints)

            SeleneCycleRow("Button names",
                           subtitle: "Automatic follows the connected controller.",
                           value: buttonNamesTitle) { step in
                settings.settings.buttonNames = settings.settings.buttonNames.stepped(step)
            }

            SeleneToggleRow("View button switches screens",
                            subtitle: "View flips between Spotlight and Collection; holding it opens Find a game.",
                            isOn: $settings.settings.viewButtonSwitches)
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        onActions([
            .init(id: "hints", title: "Button hints") {
                settings.settings.showButtonHints.toggle()
            },
            .value("buttonNames", "Button names") { step in
                settings.settings.buttonNames = settings.settings.buttonNames.stepped(step)
            },
            .init(id: "viewSwitches", title: "View button switches screens") {
                settings.settings.viewButtonSwitches.toggle()
            }
        ])
    }
}
