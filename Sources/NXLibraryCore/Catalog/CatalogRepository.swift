import Foundation

public enum CatalogRepositoryError: Error, Equatable { case gameNotFound }

/// Typed transactions against one authoritative catalog. No cached second
/// document and no automatic replay of closures with game-file side effects.
public struct CatalogRepository {
    private let store: CatalogStore
    public init(store: CatalogStore) { self.store = store }
    public func load() throws -> CatalogDocument { try store.loadOrMigrate() }

    func transaction(_ change: (inout CatalogDocument) throws -> Void) throws -> CatalogDocument {
        let current = try load()
        var draft = current
        try change(&draft)
        return try store.save(draft, expectedRevision: current.revision)
    }
}

extension CatalogRepository {
    @discardableResult
    public func configureSource(_ integration: CatalogIntegration, enabled: Bool, root: URL?) throws -> CatalogDocument {
        try transaction { document in
            var config = document.source(integration) ?? .init(integration: integration)
            let nextRoot = root.map { $0.resolvingSymlinksInPath().standardizedFileURL } ?? config.rootURL
            if config.isEnabled != enabled || config.rootURL != nextRoot { config.generation = UUID() }
            config.isEnabled = enabled; config.rootURL = nextRoot
            if let index = document.sources.firstIndex(where: { $0.integration == integration }) { document.sources[index] = config }
            else { document.sources.append(config) }
        }
    }

    @discardableResult
    public func toggleFavorite(for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setFavorite(!document.games[index].isFavorite)
        }
    }

    @discardableResult
    public func setFavorite(_ value: Bool, for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setFavorite(value)
        }
    }
    @discardableResult
    public func setHidden(_ value: Bool, for id: UUID) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            document.games[index].setHidden(value)
        }
    }

    @discardableResult
    public func applySteam(_ snapshot: SteamLibrarySnapshot, expectedSource: CatalogSourceConfiguration) throws -> CatalogDocument {
        let current = try load()
        guard expectedSource.integration == .steam, expectedSource.isEnabled,
              current.source(.steam) == expectedSource else { throw CatalogScanError.staleScan }
        let draft = try SteamCatalogReconciler.applying(snapshot, ticket: current.steamScanTicket(), to: current)
        return try store.save(draft, expectedRevision: current.revision)
    }
}
