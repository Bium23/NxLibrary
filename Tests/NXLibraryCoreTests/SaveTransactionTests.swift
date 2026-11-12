import XCTest
@testable import NXLibraryCore

final class SaveTransactionTests: XCTestCase {
    func testImportReplacesOnlyChosenSlotAndKeepsSafetyBackup() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        try h.write("old", location.directory(.account).appendingPathComponent("obsolete"))
        try h.write("island", location.directory(.device).appendingPathComponent("data"))
        try h.write("sentinel", location.root.appendingPathComponent("save.work/data"))
        try h.write("sync", location.root.appendingPathComponent("save.sync"))
        let source = h.base.appendingPathComponent("export")
        try h.write("new", source.appendingPathComponent("data"))
        let preview = try store.stageImport(source: source, slot: .account, location: location)
        let tx = SaveTransaction(store: store, isRunning: { false })
        let backup = try tx.importSave(preview, location: location, identity: h.identity)
        XCTAssertEqual(backup.reason, .beforeImport)
        XCTAssertFalse(SaveFiles.exists(location.directory(.account).appendingPathComponent("obsolete")))
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), "new")
        XCTAssertEqual(try String(contentsOf: location.directory(.device).appendingPathComponent("data")), "island")
        XCTAssertEqual(try String(contentsOf: location.root.appendingPathComponent("save.work/data")), "sentinel")
        XCTAssertEqual(try String(contentsOf: location.root.appendingPathComponent("save.sync")), "sync")
        try tx.restore(backup, location: location, identity: h.identity)
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("obsolete")), "old")
        XCTAssertNoThrow(try tx.recover(location: location))
    }
    /// nxnative e6048dea: a cut-short cloud pull leaves `save.pull`; the game's next start puts this Mac's save back,
    /// so an import or restore before then is refused and changes nothing.
    func testCloudPullJournalRefusesImportAndRestore() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        try h.write("mine", location.directory(.account).appendingPathComponent("data"))
        let backup = try store.create(location: location, identity: h.identity, reason: .manual)
        let source = h.base.appendingPathComponent("export")
        try h.write("new", source.appendingPathComponent("data"))
        let preview = try store.stageImport(source: source, slot: .account, location: location)
        try h.write("journal", location.cloudPullJournal)
        let tx = SaveTransaction(store: store, isRunning: { false })
        XCTAssertThrowsError(try tx.importSave(preview, location: location, identity: h.identity)) {
            XCTAssertEqual($0 as? SaveFailure, .cloudPullPending)
        }
        XCTAssertThrowsError(try tx.restore(backup, location: location, identity: h.identity)) {
            XCTAssertEqual($0 as? SaveFailure, .cloudPullPending)
        }
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), "mine")
        XCTAssertEqual(try String(contentsOf: location.cloudPullJournal), "journal")
    }
    func testRestoreRemovesSlotAbsentInSnapshot() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let empty = try store.create(location: location, identity: h.identity, reason: .manual)
        try h.write("new", location.directory(.device).appendingPathComponent("island"))
        let tx = SaveTransaction(store: store, isRunning: { false })
        try tx.restore(empty, location: location, identity: h.identity)
        XCTAssertFalse(SaveFiles.exists(location.directory(.device)))
    }
    func testRestartRollsBackInterruptedTwoSlotRestore() throws {
        for checkpoint in ["journal", "account", "device", "committed"] {
            let h = try SaveTestHome(); defer { h.remove() }
            let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
            try h.write("target-account", location.directory(.account).appendingPathComponent("data"))
            try h.write("target-device", location.directory(.device).appendingPathComponent("data"))
            let target = try store.create(location: location, identity: h.identity, reason: .manual)
            try h.write("original-account", location.directory(.account).appendingPathComponent("data"))
            try h.write("original-device", location.directory(.device).appendingPathComponent("data"))
            var io = SaveFileIO()
            io.afterMutation = { stage in if stage == checkpoint { throw SaveFailure.io("Simulated interruption") } }
            let tx = SaveTransaction(store: store, isRunning: { false }, io: io)
            XCTAssertThrowsError(try tx.restore(target, location: location, identity: h.identity))
            let restarted = SaveTransaction(store: store, isRunning: { false })
            try restarted.recover(location: location)
            try restarted.recover(location: location)
            let prefix = checkpoint == "committed" ? "target" : "original"
            XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), prefix + "-account")
            XCTAssertEqual(try String(contentsOf: location.directory(.device).appendingPathComponent("data")), prefix + "-device")
        }
    }
    func testRestorePreviewRejectsChangedCurrentSave() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        try h.write("target", location.directory(.account).appendingPathComponent("data"))
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        try h.write("current", location.directory(.account).appendingPathComponent("data"))
        let preview = try store.stageRestore(snapshot, location: location)
        try h.write("changed while confirming", location.directory(.account).appendingPathComponent("data"))
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).restore(preview, location: location, identity: h.identity))
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), "changed while confirming")
        try store.discardRestore(preview, location: location)
    }
    func testRecoveryKeepsUnexpectedExternalChangesAndItsJournal() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let file = location.directory(.account).appendingPathComponent("data")
        try h.write("target", file)
        let target = try store.create(location: location, identity: h.identity, reason: .manual)
        try h.write("original", file)
        var io = SaveFileIO()
        io.afterMutation = { if $0 == "account" { throw SaveFailure.io("Interrupted") } }
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io).restore(target, location: location, identity: h.identity))
        try h.write("external change", file)
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).recover(location: location))
        XCTAssertEqual(try String(contentsOf: file), "external change")
        XCTAssertTrue(SaveTransaction.needsRecovery(location: location))
        XCTAssertEqual(try store.list(titleID: h.tid).count, 2)
    }
    func testRecoveryReadsOlderBackupsAndJournalsWithSystemAccessLabels() throws {
        for checkpoint in ["account", "committed"] {
            let h = try SaveTestHome(); defer { h.remove() }
            let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
            let file = location.directory(.account).appendingPathComponent("data")
            try h.write("original", file)
            let source = h.base.appendingPathComponent("export")
            try h.write("imported", source.appendingPathComponent("data"))
            let preview = try store.stageImport(source: source, slot: .account, location: location)
            var io = SaveFileIO()
            io.afterMutation = { if $0 == checkpoint { throw SaveFailure.io("Interrupted") } }
            XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }, io: io)
                .importSave(preview, location: location, identity: h.identity))

            // Earlier versions recorded macOS access labels, which may disappear on rename.
            let backup = try XCTUnwrap(store.list(titleID: h.tid).first)
            var recordedBackup = backup
            recordedBackup.entries[0].attributes["com.apple.macl"] = Data([1, 2, 3])
            let backupFolder = try store.directory(snapshotID: backup.id, titleID: h.tid)
            try JSONEncoder().encode(recordedBackup).write(to: backupFolder.appendingPathComponent("manifest.json"))
            let journalURL = location.root.appendingPathComponent(".nxlibrary-save-transaction.json")
            var journal = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any])
            var after = try XCTUnwrap(journal["after"] as? [[String: Any]])
            var attributes = try XCTUnwrap(after[0]["attributes"] as? [String: String])
            attributes["com.apple.macl"] = Data([4, 5, 6]).base64EncodedString()
            after[0]["attributes"] = attributes
            journal["after"] = after
            try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)

            let restarted = SaveTransaction(store: store, isRunning: { false })
            try restarted.recover(location: location)
            try restarted.recover(location: location)
            XCTAssertEqual(try String(contentsOf: file), checkpoint == "committed" ? "imported" : "original")
            XCTAssertFalse(SaveTransaction.needsRecovery(location: location))
            XCTAssertNoThrow(try store.verify(snapshotID: backup.id, titleID: h.tid))
        }
    }
    func testRunningStaleAndWrongTitleRefused() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        try h.write("old", location.directory(.account).appendingPathComponent("data"))
        let source = h.base.appendingPathComponent("export")
        try h.write("new", source.appendingPathComponent("data"))
        let preview = try store.stageImport(source: source, slot: .account, location: location)
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { true }).importSave(preview, location: location, identity: h.identity))
        try h.write("changed", location.directory(.account).appendingPathComponent("data"))
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).importSave(preview, location: location, identity: h.identity))
        let backup = try store.create(location: location, identity: h.identity, reason: .manual)
        let other = SaveIdentity(titleID: "0100000000000002", gameName: "Other", version: nil, buildID: nil)
        XCTAssertThrowsError(try SaveTransaction(store: store, isRunning: { false }).restore(backup, location: location, identity: other))
    }
}
