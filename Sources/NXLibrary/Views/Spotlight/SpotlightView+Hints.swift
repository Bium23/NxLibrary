import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// The hints bar: what the buttons do for the focus and state on screen.
extension SpotlightView {
    // MARK: - Hints

    /// The A slot keeps one width per place (row, page), so the prompts hold still
    /// as the focus moves. Y and B sit leftmost, where a longer label shifts nothing.
    func hintReserve(_ state: SpotlightState) -> [[String]] {
        if state.isLifted || cardMenu != nil { return [] }
        switch state.focus {
        case .row: return [[], ["Play", "Build", "Pick", "Open"]]
        case .pills, .strip, .mods, .about, .actions, .more, .achievements: return [[], ["Select", "View", "Show", "Open"]]
        case .store: return [[], ["Sort", "View"]]
        case .topGames: return []
        }
    }

    func contextHints(_ model: Snapshot, _ state: SpotlightState) -> [HintItem] {
        if state.isLifted {
            return [HintItem(nil, L10n.text("◂ ▸  Move")), HintItem(.a, L10n.text("Drop")), HintItem(.b, L10n.text("Cancel"))]
        }
        if cardMenu != nil {
            return [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text("Back"))]
        }
        switch state.focus {
        case .pills:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Select"))]
        case .strip:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))]
        case .mods, .about, .actions:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Select"))]
        case .more:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Show"))]
        case .achievements:
            return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Open"))]
        case .topGames:
            return [HintItem(.a, L10n.text("Show"))]
        case .store:
            // On the sort bar A sorts, and only when the focused order is not the one shown already.
            guard storeHost.focus.kind == .sort else { return [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("View"))] }
            let chosen = ModStoreSort.allCases.firstIndex(of: storeHost.sort) == storeHost.focus.index
            return chosen ? [HintItem(.b, L10n.text("Back"))] : [HintItem(.b, L10n.text("Back")), HintItem(.a, L10n.text("Sort"))]
        case .row:
            switch model.selectedItem {
            case .card(let card):
                let more = [HintItem(.y, L10n.text("Card options"))]
                return card == .activity ? more : more + [HintItem(.a, card == .surprise ? L10n.text("Pick") : card == .mods ? L10n.text("Browse") : L10n.text("Open"))]
            case .game:
                if let steam = model.selectedCatalogGame, steam.integration == .steam {
                    return [HintItem(.y, L10n.text("Options"))] + SteamPlayCoordinator.shared.hint(for: steam)
                }
                guard let game = model.selectedGame else { return [] }
                if viewModel.portingPills(game) == .porting {
                    return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Porting"))]
                }
                if viewModel.portingPills(game).unavailableReason != nil, !runningGames.isRunning(game) {
                    return [HintItem(.y, L10n.text("Options"))]
                }
                if game.isPlayableLocally {
                    return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Play"))]
                }
                return [HintItem(.y, L10n.text("Options")), HintItem(.a, L10n.text("Build"))]
            case nil:
                return []
            }
        }
    }
}
