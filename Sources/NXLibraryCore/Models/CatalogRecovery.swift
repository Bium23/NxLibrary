import Foundation

/// An offer, not a repair. Re-check both fingerprints when the player accepts.
public struct CatalogRecoveryCandidate: Equatable, Sendable {
    public let gameCount: Int
    let directory: URL
    let primaryDigest: String?
    let backupDigest: String
}
