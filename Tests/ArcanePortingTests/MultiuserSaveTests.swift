import XCTest
@testable import NXLibraryCore
@testable import ArcanePorting

final class MultiuserSaveTests: XCTestCase {
    private func seed(_ prefix: String, _ h: SaveTestHome, _ location: SaveLocation) throws {
        for slot in [SaveSlot.account, .device, .user2, .user8] {
            try h.write(prefix + "-" + slot.rawValue, location.directory(slot).appendingPathComponent("progress"))
        }
        try h.write("nxnative-users-1\n" + prefix, location.directory(.users))
    }

    func testBackupIncludesRegistryAndAllCommittedUsersAndVerifiesTampering() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("saved", h, location)
        try h.write("uncommitted", location.root.appendingPathComponent("save_user3.work/progress"))
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertEqual(snapshot.schemaVersion, 2)
        XCTAssertEqual(snapshot.presentSlots, [.account, .device, .user2, .user8, .users])
        let registry = try XCTUnwrap(snapshot.entries.first { $0.slot == .users })
        XCTAssertEqual(registry.path, "")
        XCTAssertFalse(registry.isDirectory)
        XCTAssertEqual(try store.verify(snapshotID: snapshot.id, titleID: h.tid), snapshot)
        let backup = try store.directory(snapshotID: snapshot.id, titleID: h.tid)
        try h.write("tampered", backup.appendingPathComponent("save.users"))
        XCTAssertThrowsError(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
    }

    func testRestoreAllUsersAndRegistryAndRemoveUsersAbsentFromNewBackup() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("target", h, location)
        let target = try store.create(location: location, identity: h.identity, reason: .manual)
        try seed("current", h, location)
        try h.write("new user", location.directory(.user3).appendingPathComponent("progress"))
        let safety = try SaveTransaction(store: store, isRunning: { false }).restore(target, location: location, identity: h.identity)
        XCTAssertEqual(safety.schemaVersion, 2)
        XCTAssertTrue(safety.presentSlots.contains(.user3))
        XCTAssertFalse(SaveFiles.exists(location.directory(.user3)))
        XCTAssertEqual(try String(contentsOf: location.directory(.user2).appendingPathComponent("progress"), encoding: .utf8), "target-user2")
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "nxnative-users-1\ntarget")
    }

    func testLegacyRestorePreservesAdditionalUsersAndRegistry() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try h.write("legacy", location.directory(.account).appendingPathComponent("progress"))
        let legacy = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertEqual(legacy.schemaVersion, 1)
        try seed("current", h, location)
        try SaveTransaction(store: store, isRunning: { false }).restore(legacy, location: location, identity: h.identity)
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("progress"), encoding: .utf8), "legacy")
        XCTAssertFalse(SaveFiles.exists(location.directory(.device)))
        XCTAssertEqual(try String(contentsOf: location.directory(.user8).appendingPathComponent("progress"), encoding: .utf8), "current-user8")
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "nxnative-users-1\ncurrent")
    }

    func testImportPreservesOtherUsersAndRegistryAndRefusesRegistryAsAnImportTarget() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("current", h, location)
        let source = h.base.appendingPathComponent("external")
        try h.write("imported", source.appendingPathComponent("progress"))
        XCTAssertThrowsError(try store.stageImport(source: source, slot: .users, location: location))
        let preview = try store.stageImport(source: source, slot: .account, location: location)
        try SaveTransaction(store: store, isRunning: { false }).importSave(preview, location: location, identity: h.identity)
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("progress"), encoding: .utf8), "imported")
        XCTAssertEqual(try String(contentsOf: location.directory(.user2).appendingPathComponent("progress"), encoding: .utf8), "current-user2")
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "nxnative-users-1\ncurrent")
    }

    func testRegistryMutationInvalidatesRestorePreview() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("before", h, location)
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        let preview = try store.stageRestore(snapshot, location: location)
        try h.write("changed outside Arcane", location.directory(.users))
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).restore(preview, location: location, identity: h.identity))
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "changed outside Arcane")
        try store.discardRestore(preview, location: location)
    }

    func testEveryMultiuserCheckpointRecoversWithoutChangingUncommittedData() throws {
        for checkpoint in ["journal"] + SaveSlot.allCases.map(\.rawValue) + ["committed"] {
            let h = try SaveTestHome(); defer { h.remove() }
            let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
            try seed("target", h, location)
            let target = try store.create(location: location, identity: h.identity, reason: .manual)
            try seed("current", h, location)
            try h.write("working", location.root.appendingPathComponent("save_user2.work/file"))
            var io = SaveFileIO()
            io.afterMutation = { if $0 == checkpoint { throw SaveFailure.io("Interrupted") } }
            XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
                .restore(target, location: location, identity: h.identity), checkpoint)
            let restarted = SaveTransaction(store: store, isRunning: { false })
            try restarted.recover(location: location)
            try restarted.recover(location: location)
            let prefix = checkpoint == "committed" ? "target" : "current"
            XCTAssertEqual(try String(contentsOf: location.directory(.user2).appendingPathComponent("progress"), encoding: .utf8), prefix + "-user2", checkpoint)
            XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "nxnative-users-1\n" + prefix, checkpoint)
            XCTAssertEqual(try String(contentsOf: location.root.appendingPathComponent("save_user2.work/file"), encoding: .utf8), "working")
        }
    }

    func testLegacyRecoveryPreservesUsersCreatedAfterInterruption() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        let account = location.directory(.account).appendingPathComponent("progress")
        try h.write("target", account)
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        try h.write("original", account)
        var io = SaveFileIO()
        io.afterMutation = { if $0 == "account" { throw SaveFailure.io("Interrupted") } }
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
            .restore(snapshot, location: location, identity: h.identity))
        try h.write("external", location.directory(.user2).appendingPathComponent("progress"))
        try h.write("registry", location.directory(.users))
        try SaveTransaction(store: store, isRunning: { false }).recover(location: location)
        XCTAssertEqual(try String(contentsOf: account, encoding: .utf8), "original")
        XCTAssertEqual(try String(contentsOf: location.directory(.user2).appendingPathComponent("progress"), encoding: .utf8), "external")
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "registry")
    }

    func testRegistryDirectoryAndLinkAndOversizedFileAreRefused() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        let registry = location.directory(.users)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.create(location: location, identity: h.identity, reason: .manual))
        try FileManager.default.removeItem(at: registry)
        try FileManager.default.createSymbolicLink(at: registry, withDestinationURL: h.home)
        XCTAssertThrowsError(try store.create(location: location, identity: h.identity, reason: .manual))
        try FileManager.default.removeItem(at: registry)
        try Data(repeating: 0, count: 65537).write(to: registry)
        XCTAssertThrowsError(try store.create(location: location, identity: h.identity, reason: .manual))
    }

    func testSchemaOneCannotClaimOrHideNewComponents() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("original", h, location)
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        let folder = try store.directory(snapshotID: snapshot.id, titleID: h.tid)
        let manifest = folder.appendingPathComponent("manifest.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json["schemaVersion"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        XCTAssertThrowsError(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
    }

    func testLateRegistryEditIsNotOverwrittenAndJournalIsKept() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("target", h, location)
        let target = try store.create(location: location, identity: h.identity, reason: .manual)
        try seed("original", h, location)
        var io = SaveFileIO()
        io.afterMutation = { if $0 == "before-users" { try h.write("external", location.directory(.users)) } }
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
            .restore(target, location: location, identity: h.identity))
        XCTAssertTrue(SaveTransaction.needsRecovery(location: location))
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).recover(location: location))
        XCTAssertEqual(try String(contentsOf: location.directory(.users), encoding: .utf8), "external")
    }

    func testChangedDisplacedRegistryIsNeverDeletedDuringCleanupOrRecovery() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
        try seed("target", h, location)
        let target = try store.create(location: location, identity: h.identity, reason: .manual)
        try seed("original", h, location)
        var displaced: URL?
        var io = SaveFileIO()
        io.afterMutation = { checkpoint in
            guard checkpoint == "users" else { return }
            let journal = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
                location.root.appendingPathComponent(".nxlibrary-save-transaction.json"))) as? [String: Any])
            let id = try XCTUnwrap(journal["id"] as? String)
            let file = location.root.appendingPathComponent(".nxlibrary-save-transaction-" + id).appendingPathComponent("users")
            try h.write("changed open inode", file)
            displaced = file
        }
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
            .restore(target, location: location, identity: h.identity))
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).recover(location: location))
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(displaced), encoding: .utf8), "changed open inode")
        XCTAssertTrue(SaveTransaction.needsRecovery(location: location))
    }

    func testInterruptedPartialCleanupRecoversAfterCommitOrRollback() throws {
        for committed in [true, false] {
            let h = try SaveTestHome(); defer { h.remove() }
            let location = try h.location(), store = SaveSnapshotStore(root: h.backups)
            try seed("target", h, location)
            let target = try store.create(location: location, identity: h.identity, reason: .manual)
            try seed("original", h, location)
            func partlyRemoveStaging() throws {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
                    location.root.appendingPathComponent(".nxlibrary-save-transaction.json"))) as? [String: Any])
                let id = try XCTUnwrap(json["id"] as? String)
                let file = location.root.appendingPathComponent(".nxlibrary-save-transaction-" + id)
                    .appendingPathComponent("account/progress")
                try FileManager.default.removeItem(at: file)
            }
            var io = SaveFileIO()
            io.afterMutation = {
                if $0 == (committed ? "committed" : "users") {
                    if committed { try partlyRemoveStaging() }
                    throw SaveFailure.io("Interrupted")
                }
            }
            XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
                .restore(target, location: location, identity: h.identity))
            if !committed {
                var recoveryIO = SaveFileIO()
                recoveryIO.afterMutation = {
                    if $0 == "recovery-users" { try partlyRemoveStaging(); throw SaveFailure.io("Interrupted rollback cleanup") }
                }
                XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: recoveryIO).recover(location: location))
            }
            let restarted = SaveTransaction(store: store, isRunning: { false })
            try restarted.recover(location: location)
            try restarted.recover(location: location)
            XCTAssertFalse(SaveTransaction.needsRecovery(location: location))
            XCTAssertEqual(try String(contentsOf: location.directory(.user2).appendingPathComponent("progress"), encoding: .utf8),
                           (committed ? "target" : "original") + "-user2")
        }
    }
}
