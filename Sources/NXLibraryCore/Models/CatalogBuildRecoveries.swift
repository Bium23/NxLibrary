import Foundation

/// Session-only outcomes whose file effects happened but whose catalog save did
/// not. Never choose an older persisted pending app over a retained generation.
public struct CatalogBuildRecoveries {
    private var records: [UUID: PortedGame] = [:]
    public init() {}
    public subscript(id: UUID) -> PortedGame? { records[id] }
    public var values: [PortedGame] { Array(records.values) }
    public var isEmpty: Bool { records.isEmpty }

    public mutating func retain(_ outcome: PortedGame) { records[outcome.id] = outcome }
    public mutating func acknowledge(id: UUID, matching expected: PortedGame?) {
        if records[id] == expected { records[id] = nil }
    }
    public func pendingCandidate(persisted: PortedGame, explicitRetry: Bool) throws -> PortedGame? {
        guard let retained = records[persisted.id] else { return persisted }
        guard explicitRetry else { return nil }
        var result = persisted
        try result.applyCatalogBuildOutcome(retained)
        return result
    }
}

extension PortedGame {
    public mutating func applyCatalogBuildOutcome(_ outcome: PortedGame) throws {
        guard id == outcome.id else { throw CatalogModelError.identityMismatch }
        url = outcome.url
        sizeBytes = outcome.sizeBytes
        modificationDate = outcome.modificationDate
        bundleId = outcome.bundleId
        versionString = outcome.versionString
        status = outcome.status
        toolchain = outcome.toolchain
        lastBuild = outcome.lastBuild
        portingFailure = outcome.portingFailure
        portingFailureReason = outcome.portingFailureReason
        pendingInstall = outcome.pendingInstall
        appIconPending = outcome.appIconPending
    }
}
