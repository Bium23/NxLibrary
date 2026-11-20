import Foundation
import NXLibraryCore

extension DetailsFacts {
    /// A ported game: the Nintendo store's credits, the build's version and size, the app's folder.
    public static func switchGame(_ game: PortedGame, metadata: NintendoStoreMetadata?,
                                  folderName: String?, locale: Locale = L10n.context.formatLocale) -> [DetailsFact] {
        rows([.developer: names(metadata?.developers),
              .publisher: names(metadata?.publishers),
              .version: text(game.versionString),
              .size: size(game.sizeBytes, locale: locale),
              .location: text(folderName)])
    }
}
