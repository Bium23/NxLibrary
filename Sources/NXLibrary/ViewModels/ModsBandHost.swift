import SwiftUI
import Combine
import NXLibraryCore

/// One game page's Mods band (Spotlight's page and Details share it, so they behave the same): the installed mods,
/// the GameBanana part, and the mod detail and Find the game panels over the page. The installed mods are read when
/// the game is shown; GameBanana is asked only once the page itself is open (`startOnline`).
@MainActor
final class ModsBandHost: ObservableObject {
    /// The game's mods; nil without a title ID (no Mods band).
    @Published private(set) var localMods: [LocalMod]?
    /// GameBanana records of the installed mods, by GameBanana mod id.
    @Published private(set) var records: [Int: ModRecord] = [:]
    /// The open mod detail panel.
    @Published var detail: AvailableMod?
    @Published var detailFocus = 0
    @Published var detailExpanded = false

    let gameBanana = GameBananaBandModel.shared()
    let find = GameBananaFindModel()
    private(set) var game: PortedGame?
    private var forwards: Set<AnyCancellable> = []

    init() {
        // The band's tile count (focus, scrolling) follows the mods found and the status tiles; download progress
        // is drawn by the band itself and is not forwarded.
        let changed = { [weak self] in self?.objectWillChange.send() }
        gameBanana.$available.sink { _ in changed() }.store(in: &forwards)
        gameBanana.$phase.sink { _ in changed() }.store(in: &forwards)
        gameBanana.$match.sink { _ in changed() }.store(in: &forwards)
        find.$isOpen.sink { _ in changed() }.store(in: &forwards)
    }

    var isPanelOpen: Bool { detail != nil || find.isOpen }

    /// Installed mods, Manage mods, the GameBanana mods and the status tiles, left to right.
    var tiles: [ModsBandTile] {
        localMods.map { DetailsModsBand.tiles(mods: $0, gameBanana: gameBanana) } ?? []
    }

    // MARK: - Lifecycle

    /// Re-reads the mods folder; a mod deleted in Finder also leaves the overlay (the store does nothing while the
    /// game runs, and a refusal here shows in the Mods panel instead). Another game stops the previous one's band.
    func reload(_ game: PortedGame, viewModel: AppViewModel) {
        if self.game?.id != game.id { stop() }
        self.game = game
        let store = viewModel.modStore(for: game)
        if let store { _ = viewModel.performModChange { try store.sync() } }
        localMods = store?.mods()
        records = store?.gameBananaRecords() ?? [:]
    }

    /// GameBanana's mods for this game, by its name and its official store name.
    func startOnline(_ game: PortedGame, viewModel: AppViewModel) {
        if self.game?.id != game.id { reload(game, viewModel: viewModel) }
        gameBanana.onInstalled = { [weak self, weak viewModel] in
            guard let self, let viewModel, let game = self.game else { return }
            self.reload(game, viewModel: viewModel)
        }
        let names = [game.name, viewModel.storeMetadata[game.id]?.name].compactMap { $0 }
        gameBanana.start(names: names, store: viewModel.modStore(for: game))
    }

    /// Leaving the page: requests and downloads stop, the panels close.
    func stop() {
        gameBanana.stop()
        find.close()
        detail = nil
    }

    // MARK: - Tiles and panels

    /// A tile: installed mods and Manage open Game options → Mods (`openMods`); a GameBanana mod opens its detail;
    /// a status tile does what it says.
    func activate(_ index: Int, viewModel: AppViewModel, openMods: () -> Void) {
        let tiles = self.tiles
        guard let game, tiles.indices.contains(index) else { return }
        switch tiles[index] {
        case .installed, .manage:
            openMods()
        case .available(let id):
            guard let mod = gameBanana.available.first(where: { $0.id == id }) else { return }
            SoundEffectService.shared.play(.click)
            detailFocus = ModDetailPanel.rows(for: mod).firstIndex { if case .file = $0 { return true } else { return false } } ?? 0
            detailExpanded = false
            detail = mod
        case .status(let action):
            SoundEffectService.shared.play(.click)
            switch action {
            case .retry: gameBanana.retry()
            case .openPage(let url): viewModel.openURL(url)
            case .candidate(let id): if let match = gameBanana.candidate(id) { gameBanana.confirm(match) }
            case .noneOfThese: gameBanana.noneOfThese()
            case .findGame, .wrongGame: find.open(name: game.name, using: gameBanana)
            }
        }
    }

    /// The store's mod panel for one of your games: installs go into that game's folder.
    func openStoreDetail(_ mod: AvailableMod, game: PortedGame, viewModel: AppViewModel) {
        guard let store = viewModel.modStore(for: game) else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        self.game = game
        records = store.gameBananaRecords()
        gameBanana.attach(store: store)
        detailFocus = ModDetailPanel.rows(for: mod).firstIndex { if case .file = $0 { return true } else { return false } } ?? 0
        detailExpanded = false
        detail = mod
    }

    /// After an install from the store, the game's records (Installed, Update) are read again.
    func reloadRecords(viewModel: AppViewModel) {
        guard let game else { return }
        records = viewModel.modStore(for: game)?.gameBananaRecords() ?? [:]
    }

    func closeDetail() {
        SoundEffectService.shared.play(.focus)
        detail = nil
    }

    /// An open panel owns the controller: Up/Down move, A activates, B (or Menu) closes.
    func handlePanel(_ action: GamepadAction) {
        if let mod = detail {
            let rows = ModDetailPanel.rows(for: mod)
            switch action {
            case .navigateUp, .navigateDown:
                let next = min(max(detailFocus + (action == .navigateUp ? -1 : 1), 0), rows.count - 1)
                if next != detailFocus {
                    detailFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm:
                guard rows.indices.contains(detailFocus) else { return }
                let expanded = Binding(get: { self.detailExpanded }, set: { self.detailExpanded = $0 })
                ModDetailPanel.activate(rows[detailFocus], mod: mod, installed: records[mod.id], model: gameBanana,
                                        expanded: expanded)
            case .cancel, .menu:
                closeDetail()
            default: break
            }
        } else if find.isOpen {
            switch action {
            case .navigateUp: if find.move(by: -1) { SoundEffectService.shared.play(.focus) }
            case .navigateDown: if find.move(by: 1) { SoundEffectService.shared.play(.focus) }
            case .confirm:
                SoundEffectService.shared.play(.click)
                find.confirm(using: gameBanana)
            case .cancel, .menu:
                SoundEffectService.shared.play(.focus)
                find.close()
            default: break
            }
        }
    }

    /// The keys an open panel takes (arrows, Return/Space, Esc); nil for keys it leaves to the app.
    static func panelAction(keyCode: UInt16) -> GamepadAction? {
        switch keyCode {
        case 125: return .navigateDown
        case 126: return .navigateUp
        case 36, 49: return .confirm
        case 53: return .cancel
        default: return nil
        }
    }
}

/// The mod detail or Find the game panel over a game page.
struct ModsBandOverlay: View {
    @ObservedObject var host: ModsBandHost
    @ObservedObject var find: GameBananaFindModel
    let game: PortedGame

    var body: some View {
        Group {
            if let mod = host.detail {
                ModDetailPanel(model: host.gameBanana, mod: mod, game: game, installed: host.records[mod.id],
                               focus: $host.detailFocus, expanded: $host.detailExpanded, onClose: host.closeDetail)
                    .transition(.opacity)
            } else if find.isOpen {
                GameBananaFindPanel(model: find, band: host.gameBanana, gameName: game.name)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: find.isOpen)
        .animation(.easeOut(duration: 0.2), value: host.detail?.id)
    }
}
