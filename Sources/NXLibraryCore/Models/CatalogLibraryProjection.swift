import Foundation

public enum CatalogLibraryProjection {
    public static func visible(games: [CatalogGame], sources: [CatalogSourceConfiguration]) -> [CatalogGame] {
        let enabled = Set(sources.filter(\.isEnabled).map(\.integration))
        return games.filter { CatalogGamePresentation(game: $0, sourceEnabled: enabled.contains($0.integration)).isListedNormally }
    }
}
