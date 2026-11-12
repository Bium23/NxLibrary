import SwiftUI
import NXLibraryCore

struct SettingsSpotlightSection: View {
    @ObservedObject var settings: AppSettingsStore
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas

    private var tabs: [String] { LibraryFilter.allCases.map(\.rawValue) }

    private func cardBinding(_ card: SpotlightCard) -> Binding<Bool> {
        Binding(
            get: { settings.settings.visibleSpotlightCards.contains(card) },
            set: { _ in toggle(card) }
        )
    }

    private func toggle(_ card: SpotlightCard) {
        var cards = settings.settings.visibleSpotlightCards
        if let index = cards.firstIndex(of: card) {
            cards.remove(at: index)
        } else {
            // Keep the canonical order so the row reads the same every time.
            cards = SpotlightCard.allCases.filter { cards.contains($0) || $0 == card }
        }
        settings.settings.visibleSpotlightCards = cards
    }

    private func stepTab(_ step: Int) {
        if let next = tabs.stepped(from: settings.settings.startingTab, step) {
            settings.settings.startingTab = next
        }
    }

    var body: some View {
        VStack(spacing: canvas.u(8)) {
            SettingsSubheading(L10n.text("Cards"))
            ForEach(SpotlightCard.allCases, id: \.self) { card in
                SeleneToggleRow(card.title, isOn: cardBinding(card))
            }

            SettingsSubheading(L10n.text("Row"))
            SeleneCycleRow("Starting tab",
                           subtitle: "The filter Spotlight and Collection open on.",
                           value: settings.settings.startingTab) { stepTab($0) }

            SeleneButtonRow("Tile order",
                            subtitle: settings.settings.spotlightOrder.isEmpty
                                ? "Spotlight uses its own order."
                                : "Your own order of games and cards.",
                            buttonTitle: "Reset") {
                settings.settings.spotlightOrder = []
            }
        }
        .onAppear(perform: publishActions)
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = SpotlightCard.allCases.map { card in
            .init(id: "card-\(card.rawValue)", title: card.title) { toggle(card) }
        }
        actions.append(.value("startingTab", "Starting tab") { stepTab($0) })
        actions.append(.init(id: "order", title: "Tile order") {
            settings.settings.spotlightOrder = []
        })
        onActions(actions)
    }
}
