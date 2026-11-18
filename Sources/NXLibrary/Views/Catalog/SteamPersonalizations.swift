import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

@MainActor
final class SteamPersonalizations {
    static let shared = SteamPersonalizations()
    let metadata = SteamPersonalizationStore(directory: AppData.supportRoot.appendingPathComponent("integrations/steam/personal"))
    var artwork: SteamPersonalizationStore { metadata }
}
