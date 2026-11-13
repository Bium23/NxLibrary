import Foundation

public enum CatalogRepositoryError: Error, Equatable { case gameNotFound }

extension CatalogDocument {
    /// A projection for the still-nxnative screens, never another writable store.
    public var nxnativeGames: [PortedGame] { games.compactMap(\.nxnativeGame) }
}

/// Typed transactions against one authoritative catalog. No cached second
/// document and no automatic replay of closures with game-file side effects.
public struct CatalogRepository {
    private let store: CatalogStore
    public init(store: CatalogStore) { self.store = store }
    public func load() throws -> CatalogDocument { try store.loadOrMigrate() }

    @discardableResult
    public func updateNXNative(id: UUID, _ change: (inout PortedGame) throws -> Void) throws -> CatalogDocument {
        try transaction { document in
            guard let index = document.games.firstIndex(where: { $0.id == id }) else { throw CatalogRepositoryError.gameNotFound }
            guard var game = document.games[index].nxnativeGame else { throw CatalogModelError.wrongIntegration }
            try change(&game)
            try document.games[index].updateNXNative(game)
        }
    }

    @discardableResult
    public func updateNXNativeGames(_ change: (inout [PortedGame]) throws -> Void) throws -> CatalogDocument {
        try mutateNXNativeGames(enablingSource: false, requiringEnabledSource: false, change)
    }

    private func mutateNXNativeGames(enablingSource: Bool, requiringEnabledSource: Bool,
                                     _ change: (inout [PortedGame]) throws -> Void) throws -> CatalogDocument {
        try transaction { document in
            if requiringEnabledSource && !enablingSource && document.source(.nxnative)?.isEnabled != true { throw CatalogScanError.sourceDisabled }
            var games = document.nxnativeGames
            try change(&games)
            guard Set(games.map(\.id)).count == games.count else { throw CatalogModelError.duplicateGameID }
            var updates = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0) })
            document.games = try document.games.compactMap { record in
                guard record.integration == .nxnative else { return record }
                guard let updated = updates.removeValue(forKey: record.id) else { return nil }
                var result = record
                try result.updateNXNative(updated)
                return result
            }
            for game in games where updates[game.id] != nil { document.games.append(.init(nxnative: game)) }
            if enablingSource {
                var config = document.source(.nxnative) ?? .init(integration: .nxnative)
                if !config.isEnabled { config.generation = UUID() }
                config.isEnabled = true
                if let index = document.sources.firstIndex(where: { $0.integration == .nxnative }) { document.sources[index] = config }
                else { document.sources.append(config) }
            }
        }
    }

    @discardableResult
    public func mergeNXNative(scanned: [PortedGame], replacingSources: Bool = false, enableSource: Bool = false,
                              observedFrom baseline: [PortedGame]? = nil,
                              reconcile: (inout [PortedGame], Set<UUID>) throws -> Void = { _, _ in }) throws -> CatalogDocument {
        try mutateNXNativeGames(enablingSource: enableSource, requiringEnabledSource: true) { games in
            let baselineByID = baseline.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
            let protected = Set(games.filter { current in
                if current.status == .building { return true }
                guard let baselineByID else { return false }
                guard let earlier = baselineByID[current.id] else { return true }
                return !Self.sameObservationGeneration(earlier, current)
            }.map(\.id))
            let accepted = scanned.filter { observation in
                let current = games.first { candidate in
                    candidate.id == observation.id || (observation.titleId.map {
                        candidate.titleId?.caseInsensitiveCompare($0) == .orderedSame
                    } ?? false)
                }
                return current.map { !protected.contains($0.id) } ?? true
            }
            games = NXNativeLibraryMerge.merge(scanned: accepted, into: games, replacingSources: replacingSources)
            try reconcile(&games, Set(games.map(\.id)).subtracting(protected))
        }
    }

    private static func sameObservationGeneration(_ earlier: PortedGame, _ current: PortedGame) -> Bool {
        earlier.url == current.url && earlier.status == current.status && earlier.modificationDate == current.modificationDate
            && earlier.lastBuild == current.lastBuild && earlier.pendingInstall == current.pendingInstall
            && earlier.toolchain == current.toolchain && earlier.sources == current.sources
            && earlier.workspacePath == current.workspacePath && earlier.buildCachePath == current.buildCachePath
            && earlier.appIconPending == current.appIconPending
    }

    private func transaction(_ change: (inout CatalogDocument) throws -> Void) throws -> CatalogDocument {
        let current = try load()
        var draft = current
        try change(&draft)
        return try store.save(draft, expectedRevision: current.revision)
    }
}

extension CatalogRepository {
    /// Apply only fields owned by the finished build. In-flight personal/runtime
    /// changes must not be replaced by the build's earlier payload snapshot.
    @discardableResult
    public func recordNXNativeBuild(_ outcome: PortedGame) throws -> CatalogDocument {
        try updateNXNative(id: outcome.id) { game in
            try game.applyCatalogBuildOutcome(outcome)
        }
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
