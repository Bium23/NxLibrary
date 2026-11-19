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
    /// When an AppID last came back without facts: asked again after a minute, not on every draw.
    private var missedAt: [UInt32: Date] = [:]
    private static let retryAfter: TimeInterval = 60

    func metadata(for game: CatalogGame) -> SteamMetadata? {
        game.steamGame.flatMap { facts[$0.appID] }
    }

    func isKnown(_ game: CatalogGame) -> Bool {
        game.steamGame.map { known.contains($0.appID) } ?? true
    }

    func load(_ game: CatalogGame, language app: AppLanguage) async {
        guard let appID = game.steamGame?.appID else { return }
        let language = SteamMetadata.language(app)
        if language != self.language { self.language = language; facts = [:]; known = []; missedAt = [:] }
        // An answer without facts in this language (offline, store busy) is retried later; facts once found are kept.
        let retry = facts[appID]?.language != language && missedAt[appID].map { Date().timeIntervalSince($0) > Self.retryAfter } == true
        guard !known.contains(appID) || retry else { return }
        let result = await SteamMetadataService.shared.metadata(appID: appID, language: language)
        guard !Task.isCancelled, language == self.language else { return }
        if let result { facts[appID] = result; missedAt[appID] = nil } else {
            // Offline in a new language: the last text in another language, with its notice, beats an empty page.
            if facts[appID] == nil { facts[appID] = await SteamMetadataService.shared.cachedInAnyLanguage(appID: appID) }
            guard !Task.isCancelled, language == self.language else { return }
            missedAt[appID] = Date()
        }
        known.insert(appID)
    }
}
