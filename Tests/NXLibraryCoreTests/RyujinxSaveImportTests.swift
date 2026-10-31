import XCTest
@testable import NXLibraryCore

final class RyujinxSaveImportTests: XCTestCase {
    private func makeContainer(_ h: SaveTestHome) throws -> URL {
        let container = h.base.appendingPathComponent("Ryujinx/bis/user/save/0000000000000008")
        try h.write("settings", container.appendingPathComponent("0/SaveSlot0/settings"))
        try h.write("progress", container.appendingPathComponent("0/SaveSlot1/progress"))
        try h.write("working", container.appendingPathComponent("1/SaveSlot1/progress"))
        var title = try XCTUnwrap(UInt64(h.tid, radix: 16)).littleEndian
        var metadata = withUnsafeBytes(of: &title) { Data($0) }
        metadata.append(Data(count: 512 - metadata.count))
        try metadata.write(to: container.appendingPathComponent("ExtraData0"))
        return container
    }

    func testContainerAndSlotSelectionsImportTheWholeGame() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let container = try makeContainer(h)
        let location = try h.location()
        let store = SaveSnapshotStore(root: h.backups)
        try h.write("old", location.directory(.account).appendingPathComponent("old-progress"))
        for selected in [container, container.appendingPathComponent("0"), container.appendingPathComponent("0/SaveSlot0"),
                         container.appendingPathComponent("1/SaveSlot1")] {
            let preview = try store.stageImport(source: selected, slot: .account, location: location)
            defer { try? store.discard(preview, location: location) }
            XCTAssertEqual(preview.source.path, container.appendingPathComponent("0").path)
            XCTAssertEqual(preview.fileCount, 2)
            let backup = try SaveTransaction(store: store, isRunning: { false }).importSave(preview, location: location, identity: h.identity)
            XCTAssertNoThrow(try store.verify(snapshotID: backup.id, titleID: h.tid))
            XCTAssertEqual(try String(contentsOf: location.directory(.account).appendingPathComponent("SaveSlot1/progress")), "progress")
            XCTAssertFalse(FileManager.default.fileExists(atPath: location.directory(.account).appendingPathComponent("ExtraData0").path))
        }
    }

    func testWrongGameAndWholeEmulatorLibraryAreRefused() throws {
        let h = try SaveTestHome(); defer { h.remove() }
        let container = try makeContainer(h)
        let other = try h.location(id: "0100000000000002")
        let store = SaveSnapshotStore(root: h.backups)
        for selected in [container.appendingPathComponent("0/SaveSlot0"), container.deletingLastPathComponent()] {
            XCTAssertThrowsError(try store.stageImport(source: selected, slot: .account, location: other))
        }
    }

    func testQuarantineCopyAttributionCanChangeButFlagsAndEventStillMatter() {
        func attributes(_ record: String) -> [String: Data] {
            SaveFiles.portableAttributes(["com.apple.quarantine": Data(record.utf8)])
        }
        let original = attributes("0082;1234abcd;Player;event")
        XCTAssertEqual(original, attributes("0082;1234abcd;;event"))
        XCTAssertNotEqual(original, attributes("0080;1234abcd;;event"))
        XCTAssertNotEqual(original, attributes("0082;1234abce;;event"))
        XCTAssertNotEqual(original, attributes("0082;1234abcd;;other"))
        XCTAssertNotEqual(original, [:])
    }
}
