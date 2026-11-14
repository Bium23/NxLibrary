import Foundation
import CryptoKit
import Darwin

public enum CatalogStoreError: Error, Equatable {
    case invalidLegacy, invalidCatalog(backupAvailable: Bool), legacyChanged, staleRevision, busy, unsafeDirectory
    /// Main may already contain the new revision. Reload before deciding whether to retry.
    case commitUncertain
}

/// Versioned persistence for the generalization branch. CatalogRepository owns
/// all app game-record mutations; legacy files remain recovery inputs.
public struct CatalogStore {
    public let directory: URL
    private let publication: CatalogPublication
    private static let maximumBytes = 16 * 1024 * 1024

    public init(directory: URL) { self.init(directory: directory, publication: .atomic) }
    init(directory: URL, publication: CatalogPublication) {
        self.directory = directory.standardizedFileURL
        self.publication = publication
    }
    private func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func decode(_ data: Data) throws -> CatalogDocument {
        // Deferred-to-Date keeps the exact Date value; the legacy decoder below
        // alone uses ISO8601. This is part of catalog schema 1.
        let document = try JSONDecoder().decode(CatalogDocument.self, from: data)
        try document.validate()
        return document
    }
    private static func encode(_ document: CatalogDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(document)
        guard data.count <= maximumBytes else { throw InstallationFileReadError.tooLarge }
        guard try decode(data) == document else { throw CatalogModelError.invalidRecord }
        return data
    }

    public func loadOrMigrate() throws -> CatalogDocument {
        try locked {
            let current = try currentCatalog()
            if let document = current.document {
                try verifyLegacy(document.legacyOrigin)
                return document
            }
            let (document, observations) = try convertedLegacy()
            let data = try Self.encode(document)
            try commit(data, previous: nil, current: current.state) {
                for observation in observations { try observation.verifyUnchanged() }
                try self.verifyLegacy(document.legacyOrigin)
            }
            return document
        }
    }

    public func save(_ draft: CatalogDocument, expectedRevision: UUID) throws -> CatalogDocument {
        try locked {
            let current = try currentCatalog()
            guard let old = current.document, old.revision == expectedRevision, draft.revision == expectedRevision,
                  old.legacyOrigin == draft.legacyOrigin else { throw CatalogStoreError.staleRevision }
            try verifyLegacy(old.legacyOrigin)
            var committed = draft
            committed.revision = UUID()
            let data = try Self.encode(committed)
            try commit(data, previous: current.state.data, current: current.state) { try self.verifyLegacy(old.legacyOrigin) }
            return committed
        }
    }

    private struct FileState {
        let data: Data?
        let observation: InstallationFileObservation
        func verify() throws { try observation.verifyUnchanged() }
    }
    private func read(_ name: String) throws -> FileState {
        let target = file(name)
        do {
            let snapshot = try InstallationFileSnapshot.read(at: target, maximumBytes: Self.maximumBytes)
            return FileState(data: snapshot.data, observation: snapshot.observation)
        } catch let error as POSIXError where error.code == .ENOENT {
            return FileState(data: nil, observation: try .absent(at: target))
        }
    }

    private func currentCatalog() throws -> (document: CatalogDocument?, state: FileState) {
        let backup = try? read("catalog.json.bak")
        let backupAvailable = backup?.data.flatMap { try? Self.decode($0) } != nil
        do {
            let main = try read("catalog.json")
            if let data = main.data { return (try Self.decode(data), main) }
            // An existing backup, valid or damaged, is evidence of an older
            // catalog. Never interpret a missing main as a fresh profile.
            guard backup?.data == nil else { throw CatalogStoreError.invalidCatalog(backupAvailable: backupAvailable) }
            // Unsafe/unreadable backups also require explicit recovery.
            if backup == nil { throw CatalogStoreError.invalidCatalog(backupAvailable: false) }
            return (nil, main)
        } catch { throw CatalogStoreError.invalidCatalog(backupAvailable: backupAvailable) }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func convertedLegacy() throws -> (CatalogDocument, [InstallationFileObservation]) {
        do {
            let main = try read("library.json")
            let selected: FileState, origin: CatalogLegacyOrigin
            if let data = main.data {
                selected = main; origin = .init(kind: .primary, sha256: Self.digest(data))
            } else {
                let backup = try read("library.json.bak")
                guard let bytes = backup.data else {
                    return (CatalogDocument(), [main.observation, backup.observation])
                }
                selected = backup; origin = .init(kind: .backup, sha256: Self.digest(bytes))
            }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let legacy = try decoder.decode(LibraryFile.self, from: selected.data!)
            return (try CatalogDocument.converting(legacy, origin: origin), [main.observation, selected.observation])
        } catch { throw CatalogStoreError.invalidLegacy }
    }

    private func verifyLegacy(_ origin: CatalogLegacyOrigin) throws {
        do {
            let main = try read("library.json")
            switch origin.kind {
            case .primary:
                guard let data = main.data, Self.digest(data) == origin.sha256 else { throw CatalogStoreError.legacyChanged }
            case .backup:
                guard main.data == nil, let backup = try read("library.json.bak").data,
                      Self.digest(backup) == origin.sha256 else { throw CatalogStoreError.legacyChanged }
            case .absent:
                guard main.data == nil, try read("library.json.bak").data == nil else { throw CatalogStoreError.legacyChanged }
            }
        } catch { throw CatalogStoreError.legacyChanged }
    }

    private func commit(_ data: Data, previous: Data?, current: FileState, validate: () throws -> Void) throws {
        let candidate = try CatalogPublication.stage(data, in: directory)
        defer { try? FileManager.default.removeItem(at: candidate) }
        // Re-read the actual staged bytes, not just the in-memory draft.
        _ = try Self.decode(InstallationFileSnapshot.read(at: candidate, maximumBytes: Self.maximumBytes).data)
        try current.verify(); try validate()
        let backup = try read("catalog.json.bak")
        let backupStage = try CatalogPublication.stage(previous ?? data, in: directory)
        defer { try? FileManager.default.removeItem(at: backupStage) }
        // A valid old main is the new restore point. Initial create also has a
        // restore point before the main is exposed. Original legacy files stay put.
        try CatalogPublication.atomic.publish(backupStage, file("catalog.json.bak"), backup.data != nil) {
            try backup.verify(); try current.verify(); try validate()
        }
        try publication.publish(candidate, file("catalog.json"), previous != nil) {
            try current.verify(); try validate()
        }
        // Persist directory entries after both renames/links. File data was
        // fsynced before publication; a valid restore point precedes the main.
        do { try publication.syncDirectory(directory) }
        catch { throw CatalogStoreError.commitUncertain }
    }

    private func locked<T>(_ operation: () throws -> T) throws -> T {
        guard directory.isFileURL else { throw CatalogStoreError.unsafeDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var status = stat()
        guard lstat(directory.path, &status) == 0, status.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw CatalogStoreError.unsafeDirectory
        }
        let fd = open(file(".catalog.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        _ = try InstallationFileObservation.capture(fileDescriptor: fd, url: file(".catalog.lock"))
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CatalogStoreError.busy }
        defer { _ = flock(fd, LOCK_UN) }
        return try operation()
    }
}

extension CatalogStore {
    /// Read-only validation used on an import stage, before making it visible.
    func validateImportedOrigin(_ document: CatalogDocument) throws { try verifyLegacy(document.legacyOrigin) }

    public func recoveryCandidate() throws -> CatalogRecoveryCandidate? {
        try locked {
            let main = try read("catalog.json")
            if let bytes = main.data, (try? Self.decode(bytes)) != nil { return nil }
            let backup = try read("catalog.json.bak")
            guard let bytes = backup.data else { return nil }
            let document = try Self.decode(bytes)
            try verifyLegacy(document.legacyOrigin)
            return .init(gameCount: document.games.count, directory: directory,
                         primaryDigest: main.data.map(Self.digest), backupDigest: Self.digest(bytes))
        }
    }

    public func restoreBackup(_ candidate: CatalogRecoveryCandidate) throws -> CatalogDocument {
        try locked {
            guard candidate.directory == directory else { throw CatalogStoreError.staleRevision }
            let main = try read("catalog.json"), backup = try read("catalog.json.bak")
            guard main.data.map(Self.digest) == candidate.primaryDigest,
                  let bytes = backup.data, Self.digest(bytes) == candidate.backupDigest else { throw CatalogStoreError.staleRevision }
            var restored = try Self.decode(bytes)
            try verifyLegacy(restored.legacyOrigin)
            restored.revision = UUID() // A restore never revives an old writer's revision.
            let staged = try CatalogPublication.stage(Self.encode(restored), in: directory)
            defer { try? FileManager.default.removeItem(at: staged) }
            _ = try Self.decode(InstallationFileSnapshot.read(at: staged, maximumBytes: Self.maximumBytes).data)
            func validate() throws {
                try main.verify(); try backup.verify(); try verifyLegacy(restored.legacyOrigin)
            }
            try validate()
            if let damaged = main.data {
                let kept = try CatalogPublication.stage(damaged, in: directory)
                defer { try? FileManager.default.removeItem(at: kept) }
                let archive = file("catalog.json.recovered-" + UUID().uuidString + ".json")
                try CatalogPublication.atomic.publish(kept, archive, false, validate)
            }
            try publication.publish(staged, file("catalog.json"), main.data != nil, validate)
            do { try publication.syncDirectory(directory) }
            catch { throw CatalogStoreError.commitUncertain }
            return restored
        }
    }
}
