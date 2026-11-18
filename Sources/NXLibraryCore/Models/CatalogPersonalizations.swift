import Foundation

/// Immutable lookup map captured by the presentation. Physical nxnative paths
/// remain compatible; each other integration has its own personal-data root.
public struct CatalogPersonalizations: Equatable, Sendable {
    private let references: [UUID: CatalogPersonalizationReference]
    public static let empty = Self(references: [:])
    private init(references: [UUID: CatalogPersonalizationReference]) { self.references = references }
    public init(document: CatalogDocument) {
        references = Dictionary(document.games.map { ($0.id, $0.personalizationReference) }, uniquingKeysWith: { first, _ in first })
    }
    public func nxnativeKey(for game: PortedGame) -> String {
        guard let reference = references[game.id], reference.namespace == .nxnative else { return game.titleId ?? game.uniqueKey }
        return reference.key
    }
}

extension CatalogPersonalizationReference {
    public func supportRoot(in launcherRoot: URL) -> URL {
        switch namespace {
        case .nxnative: return launcherRoot
        case .steam: return launcherRoot.appendingPathComponent("integrations/steam", isDirectory: true)
        }
    }
}
