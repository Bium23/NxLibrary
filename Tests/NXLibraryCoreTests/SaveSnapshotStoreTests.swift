import XCTest
import Darwin
@testable import NXLibraryCore

final class SaveSnapshotStoreTests: XCTestCase {
    func testCopyIdentityIsExcludedButGuestNamesAndQuarantineRemainVerified() {
        let metadata = ["com.apple.provenance": Data([1]),
                        "org.d2rmobile.guest-name": Data("Save".utf8),
                        "com.apple.quarantine": Data("quarantine".utf8)]
        XCTAssertEqual(SaveFiles.portableAttributes(metadata), [
            "org.d2rmobile.guest-name": Data("Save".utf8),
            "com.apple.quarantine": Data("quarantine".utf8)])
    }
    func testOlderBackupCopyIdentityDoesNotPreventRestoreVerification() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        try h.write("save", location.directory(.account).appendingPathComponent("data"))
        var snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        for index in snapshot.entries.indices { snapshot.entries[index].attributes["com.apple.provenance"] = Data([1, 2, 3]) }
        let directory = try store.directory(snapshotID: snapshot.id, titleID: h.tid)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("manifest.json"))
        let verified = try store.verify(snapshotID: snapshot.id, titleID: h.tid)
        XCTAssertTrue(verified.entries.allSatisfy { $0.attributes["com.apple.provenance"] == nil })
    }
    func testRoundTripBothSlotsAndAttributes() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location()
        let file = location.directory(.account).appendingPathComponent("slot/progress.bin")
        try h.write("original", file)
        try h.write("device", location.directory(.device).appendingPathComponent("island"))
        let value = Data("GuestName".utf8)
        XCTAssertEqual(value.withUnsafeBytes { setxattr(file.path, "org.d2rmobile.guest-name", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }, 0)
        let store = SaveSnapshotStore(root: h.backups)
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertEqual(snapshot.presentSlots, [.account, .device])
        XCTAssertNoThrow(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
        let copied = try store.directory(snapshotID: snapshot.id, titleID: h.tid).appendingPathComponent("save/slot/progress.bin")
        XCTAssertEqual(try String(contentsOf: copied), "original")
        XCTAssertEqual(try SaveFiles.attributes(copied)["org.d2rmobile.guest-name"], value)
        try h.write("tampered", copied)
        XCTAssertThrowsError(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
        XCTAssertEqual(try String(contentsOf: file), "original")
    }
    func testAbsentAndEmptyDirectoriesAreRecorded() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let absent = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertTrue(absent.presentSlots.isEmpty)
        try FileManager.default.createDirectory(at: location.directory(.account).appendingPathComponent("empty"), withIntermediateDirectories: true)
        let empty = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertEqual(empty.presentSlots, [.account])
        XCTAssertTrue(empty.entries.contains { $0.path == "empty" && $0.isDirectory })
        XCTAssertEqual(try store.list(titleID: h.tid).count, 2)
    }
    func testPreviewDoesNotChangeSaveAndRefusesChangedSource() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let source = h.base.appendingPathComponent("0")
        try h.write("new", source.appendingPathComponent("data"))
        try h.write("old", location.directory(.account).appendingPathComponent("data"))
        let preview = try store.stageImport(source: source, slot: .account, location: location)
        XCTAssertEqual(preview.fileCount, 1)
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), "old")
        try h.write("changed", source.appendingPathComponent("data"))
        XCTAssertThrowsError(try store.validate(preview, location: location))
        try store.discard(preview, location: location)
    }
    func testLinksEmptyAndOverlapsRefused() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let source = h.base.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.stageImport(source: source, slot: .account, location: location))
        try h.write("file", h.base.appendingPathComponent("outside"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("link"), withDestinationURL: h.base.appendingPathComponent("outside"))
        XCTAssertThrowsError(try store.stageImport(source: source, slot: .account, location: location))
        XCTAssertThrowsError(try store.stageImport(source: location.root, slot: .account, location: location))
    }
    func testUnknownManifestAndChangedMetadataAreRefused() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location(); let store = SaveSnapshotStore(root: h.backups)
        let file = location.directory(.account).appendingPathComponent("日本語/large.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 2 * 1024 * 1024).write(to: file)
        let snapshot = try store.create(location: location, identity: h.identity, reason: .manual)
        XCTAssertEqual(snapshot.byteCount, 2 * 1024 * 1024)
        let directory = try store.directory(snapshotID: snapshot.id, titleID: h.tid)
        let manifest = directory.appendingPathComponent("manifest.json")
        let original = try Data(contentsOf: manifest)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        XCTAssertThrowsError(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
        try original.write(to: manifest)
        let copied = directory.appendingPathComponent("save/日本語/large.bin")
        let value = Data("changed".utf8)
        XCTAssertEqual(value.withUnsafeBytes { setxattr(copied.path, "org.d2rmobile.guest-name", $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW) }, 0)
        XCTAssertThrowsError(try store.verify(snapshotID: snapshot.id, titleID: h.tid))
    }
    func testFailedCopyDoesNotPublishBackup() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let location = try h.location()
        try h.write("old", location.directory(.account).appendingPathComponent("data"))
        var io = SaveFileIO()
        io.copy = { _, _ in throw SaveFailure.io("Disk full") }
        let store = SaveSnapshotStore(root: h.backups, io: io)
        XCTAssertThrowsError(try store.create(location: location, identity: h.identity, reason: .manual))
        XCTAssertEqual(try store.list(titleID: h.tid), [])
        XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("data")), "old")
    }
}

extension SaveTestHome {
    var identity: SaveIdentity { SaveIdentity(titleID: tid, gameName: "Synthetic game", version: "1", buildID: nil) }
}
