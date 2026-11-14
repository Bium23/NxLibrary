import Foundation
import AppKit
import NXLibraryCore

/// One GameBanana client, image cache and match store for the whole app (caches in
/// `~/Library/Caches/NXLibrary/gamebanana`, matches in `~/Library/Application Support/NXLibrary/gamebanana`).
final class GameBananaServices: @unchecked Sendable {
    static let shared = GameBananaServices()

    let userAgent: String
    let client: GameBananaClient
    let images: GameBananaImageCache
    let matches: GameBananaMatchStore

    private init() {
        let fm = FileManager.default
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        userAgent = GameBananaClient.userAgent(version: version)
        let caches = AppData.cacheRoot.appendingPathComponent("gamebanana")
        let support = AppData.supportRoot.appendingPathComponent("gamebanana")
        client = GameBananaClient(cacheFolder: caches.appendingPathComponent("api"), userAgent: userAgent)
        images = GameBananaImageCache(folder: caches.appendingPathComponent("images"), userAgent: userAgent)
        matches = GameBananaMatchStore(file: support.appendingPathComponent("matches.json"))
    }
}

@MainActor
extension GameBananaBandModel {
    /// The band model on the app's shared GameBanana services.
    static func shared() -> GameBananaBandModel {
        let services = GameBananaServices.shared
        let model = GameBananaBandModel(client: services.client, matches: services.matches, userAgent: services.userAgent)
        // A group of mods shows with its art already decoded, at the size the band draws it.
        model.prepareImages = { urls in
            await GameBananaImageView.prepare(urls, maxPixelSize: DetailsModsBand.thumbnailPixels)
        }
        return model
    }
}
