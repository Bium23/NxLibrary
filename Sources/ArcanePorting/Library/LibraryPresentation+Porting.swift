import Foundation
import NXLibraryCore

extension LibraryPresentation {
    /// A ported game, with the Nintendo store's facts when Arcane has them.
    public init(game: PortedGame, metadata: NintendoStoreMetadata?,
                totalPlaytime: TimeInterval, lastPlayed: Date?, now: Date = Date()) {
        self.init(title: game.name,
                  eyebrow: metadata.map { Self.eyebrow(from: $0.name) } ?? "",
                  genres: Array(GameGenre.list(metadata?.genres ?? []).prefix(3)),
                  publisher: metadata?.publishers.first,
                  releaseYear: metadata?.releaseYear,
                  playtime: Self.duration(totalPlaytime),
                  lastPlayed: Self.relative(lastPlayed, now: now),
                  platform: "nxnative",
                  console: game.consoleName,
                  sourcesDetached: !SourceSelection.hasGame(game.sources),
                  summary: (metadata?.description ?? "")
                      .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                      .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Common display boundary for a catalog game; provider facts never become a fabricated NX game.
    public init(game: CatalogGame, steamMetadata: SteamMetadata?,
                nxnativeMetadata: NintendoStoreMetadata? = nil,
                overrides: [MetadataField: String] = [:], totalPlaytime: TimeInterval,
                lastPlayed: Date?, now: Date = Date()) {
        if let native = game.nxnativeGame {
            self.init(game: native, metadata: nxnativeMetadata, totalPlaytime: totalPlaytime, lastPlayed: lastPlayed, now: now)
            return
        }
        self.init(steamRecord: game, metadata: steamMetadata, overrides: overrides,
                  totalPlaytime: totalPlaytime, lastPlayed: lastPlayed, now: now)
    }
}
