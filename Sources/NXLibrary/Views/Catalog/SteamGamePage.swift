import SwiftUI
import AppKit
import NXLibraryCore

/// Steam store facts for the games on screen, one copy shared by Spotlight and Collection,
/// so the head, the page and the input counts read the same answer. Facts are per AppID
/// and language; a reply for a game or language no longer asked for is dropped.
@MainActor
final class SteamGameFacts: ObservableObject {
    static let shared = SteamGameFacts()
    @Published private(set) var facts: [UInt32: SteamMetadata] = [:]
    /// AppIDs whose answer (facts or none) is in for the current language.
    @Published private(set) var known: Set<UInt32> = []
    private var language = ""

    func metadata(for game: CatalogGame) -> SteamMetadata? {
        game.steamGame.flatMap { facts[$0.appID] }
    }

    func isKnown(_ game: CatalogGame) -> Bool {
        game.steamGame.map { known.contains($0.appID) } ?? true
    }

    func load(_ game: CatalogGame, language app: AppLanguage) async {
        guard let appID = game.steamGame?.appID else { return }
        let language = SteamMetadata.language(app)
        if language != self.language { self.language = language; facts = [:]; known = [] }
        guard !known.contains(appID) else { return }
        let result = await SteamMetadataService.shared.metadata(appID: appID, language: language)
        guard !Task.isCancelled, language == self.language else { return }
        if let result { facts[appID] = result }
        known.insert(appID)
    }
}

extension BuildSourcesRow {
    /// A Steam game's page actions, in grid order: only what NX Library can do for it today.
    @MainActor
    static func steamRows(for game: CatalogGame, presentation p: GameDetailPresentation,
                          viewModel: AppViewModel) -> [BuildSourcesRow] {
        var rows: [BuildSourcesRow] = []
        if !p.appPath.isEmpty {
            rows.append(BuildSourcesRow(id: "app", title: L10n.text("Reveal app in Finder")) {
                viewModel.revealInFinder(url: URL(fileURLWithPath: p.appPath))
            })
        }
        if let store = p.storeURL {
            rows.append(BuildSourcesRow(id: "store", title: L10n.text("Store page")) { viewModel.openURL(store) })
        }
        if let hltb = p.hltbURL {
            rows.append(BuildSourcesRow(id: "hltb", title: L10n.text("HowLongToBeat")) { viewModel.openURL(hltb) })
        }
        return rows
    }
}

/// The Steam counterpart of Build & Sources in the page's right column: where the game
/// is installed and the same action grid. No engine, build or sources lines.
struct SteamInstallationPanel: View {
    @Environment(\.seleneCanvas) private var canvas
    let presentation: GameDetailPresentation
    let rows: [BuildSourcesRow]
    let focusedRow: Int?
    let onHoverRow: (Int) -> Void
    let onPressRow: (Int) -> Void
    var width: CGFloat = BuildSourcesPanel.narrowWidth

    private var installed: Bool { !presentation.appPath.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("Installation"))
                .seleneFont(21, .semibold).foregroundColor(SeleneTheme.ink)
                .padding(.top, canvas.u(2)).padding(.bottom, canvas.u(14)).padding(.leading, canvas.u(2))
            HStack(spacing: canvas.u(7)) {
                Circle().fill(installed ? SeleneTheme.success : SeleneTheme.untested)
                    .frame(width: canvas.u(9), height: canvas.u(9))
                Text(installed ? "Steam  ·  " + L10n.text("Mac game") : L10n.text("Installation not detected"))
                    .seleneFont(15, .medium)
                    .foregroundColor(installed ? SeleneTheme.success.opacity(0.9) : SeleneTheme.untested.opacity(0.9))
            }
            .padding(.leading, canvas.u(2))
            if installed {
                Text(URL(fileURLWithPath: presentation.appPath).lastPathComponent)
                    .seleneFont(15).foregroundColor(SeleneTheme.ink60)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.top, canvas.u(4)).padding(.leading, canvas.u(2))
            }
            SeleneActionGrid(rows: rows, focusedRow: focusedRow, onHoverRow: onHoverRow, onPressRow: onPressRow)
                .padding(.top, canvas.u(14))
        }
        .frame(width: canvas.u(width), alignment: .topLeading)
    }
}
