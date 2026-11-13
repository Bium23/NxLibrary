import Foundation

/// Shared library operations are ordered once. Integration handlers still enforce
/// CatalogGamePresentation capabilities before performing an operation.
public enum CatalogGameOptions {
    public static func commonRows(for integration: CatalogIntegration, origin: GameOptionsOrigin) -> [GameOptionsRow] {
        var rows: [GameOptionsRow] = [.play, .editDetails]
        if origin == .spotlight { rows.append(.move) }
        rows += [.favorite, .hidden, .showInFinder, .storePage]
        return rows
    }
    public static func specificRows(for integration: CatalogIntegration) -> [GameOptionsRow] {
        switch integration {
        case .steam: return []
        case .nxnative: return [.cheats, .mods, .openSaves, .rebuild, .attachSources, .openLog, .removeSources]
        }
    }
}
