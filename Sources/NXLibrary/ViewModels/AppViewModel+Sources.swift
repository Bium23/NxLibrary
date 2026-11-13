import AppKit
import NXLibraryCore

extension AppViewModel {
    var visibleCatalogGames: [CatalogGame] {
        CatalogLibraryProjection.visible(games: catalogGames, sources: catalogSourceConfigurations)
    }
    func setCatalogFavorite(_ game: CatalogGame) {
        do { applyCatalog(try catalogRepository.toggleFavorite(for: game.id)) }
        catch { reportCatalogFailure(error) }
    }
    @discardableResult
    func setCatalogHidden(_ hidden: Bool, game: CatalogGame) -> Bool {
        do { applyCatalog(try catalogRepository.setHidden(hidden, for: game.id)); return true }
        catch { reportCatalogFailure(error); return false }
    }
    var currentFocusedCatalogGame: CatalogGame? {
        let id: UUID?
        switch router?.route {
        case .detail(let value): id = value
        case .library: id = spotlight.selectedGameID
        case .collection: id = librarySelection.selectedGameID
        default: id = nil
        }
        guard let id else { return nil }
        return visibleCatalogGames.first { $0.id == id }
    }
}
