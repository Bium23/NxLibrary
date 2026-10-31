import XCTest
@testable import NXLibraryCore

final class KeyCheckTests: XCTestCase {
    /// A random header key, generated per run: no real key material in the repository.
    private let headerKey: [UInt8] = (0..<32).map { _ in UInt8.random(in: 0...255) }

    /// A plain NCA header: magic at 0x200, generation bytes at 0x206/0x220, key area index at 0x207,
    /// rights ID at 0x230.
    private func plainHeader(generation: UInt8, area: UInt8 = 0, rightsID: Bool = false) -> [UInt8] {
        var h = [UInt8](repeating: 0, count: KeyCheck.headerBytes)
        h.replaceSubrange(0x200..<0x204, with: Array("NCA3".utf8))
        h[0x206] = generation > 2 ? 2 : generation
        h[0x207] = area
        h[0x220] = generation
        if rightsID { h[0x230] = 0x01 }
        return h
    }

    private func encrypted(_ plain: [UInt8], key: [UInt8]? = nil) -> [UInt8] {
        KeyCheck.xts(plain, key: key ?? headerKey, encrypt: true)!
    }

    private func keys(_ names: [String]) -> [String: [UInt8]] {
        var keys: [String: [UInt8]] = ["header_key": headerKey]
        for name in names { keys[name] = [UInt8](repeating: 0xAB, count: 16) }
        return keys
    }

    private func nsp(_ name: String, part: KeyCheck.Part, _ headers: [[UInt8]], ncz: Bool = false)
        -> (part: KeyCheck.Part, name: String, container: KeyCheck.Container) {
        (part, name, .pfs0(headers.map { ($0, ncz) }))
    }

    func testXTSRoundTrip() {
        let data = (0..<0x400).map { _ in UInt8.random(in: 0...255) }
        let sealed = KeyCheck.xts(data, key: headerKey, encrypt: true)
        XCTAssertNotNil(sealed)
        XCTAssertNotEqual(sealed, data)
        XCTAssertEqual(KeyCheck.xts(sealed!, key: headerKey, encrypt: false), data)
    }

    func testNeedsKeyAreaKeyForStandardCrypto() {
        let need = KeyCheck.needs(header: plainHeader(generation: 0x0C))
        XCTAssertEqual(need?.revision, 11)
        XCTAssertEqual(need?.key, "key_area_key_application_0b")
    }

    func testNeedsTitlekekForRightsID() {
        XCTAssertEqual(KeyCheck.needs(header: plainHeader(generation: 0x0C, rightsID: true))?.key, "titlekek_0b")
    }

    func testNeedsNilWithoutMagic() {
        XCTAssertNil(KeyCheck.needs(header: [UInt8](repeating: 0, count: KeyCheck.headerBytes)))
    }

    func testFitsWithOnlyMasterKeys() {
        let files = [nsp("base.nsp", part: .base, [encrypted(plainHeader(generation: 0x0C))])]
        var keys: [String: [UInt8]] = ["header_key": headerKey]
        keys["master_key_0b"] = [UInt8](repeating: 1, count: 16)
        XCTAssertEqual(KeyCheck.check(keys: keys, files: files), .fits)
    }

    func testFitsWithDerivedKeys() {
        let files = [nsp("base.nsp", part: .base, [encrypted(plainHeader(generation: 0x05))])]
        XCTAssertEqual(KeyCheck.check(keys: keys(["key_area_key_application_04"]), files: files), .fits)
    }

    func testTooOldNamesNewestMissing() {
        let files = [
            nsp("base.nsp", part: .base, [encrypted(plainHeader(generation: 0x05))]),
            nsp("update.nsp", part: .update, [encrypted(plainHeader(generation: 0x0C))]),
        ]
        let names = (0...0x0A).map { String(format: "key_area_key_application_%02x", $0) }
        XCTAssertEqual(KeyCheck.check(keys: keys(names), files: files),
                       .tooOld(part: .update, generation: 12, missing: "key_area_key_application_0b"))
    }

    func testWrongHeaderKey() {
        let other = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let files = [nsp("base.nsp", part: .base, [encrypted(plainHeader(generation: 0x05), key: other)])]
        XCTAssertEqual(KeyCheck.check(keys: keys(["master_key_04"]), files: files), .wrongHeaderKey(file: "base.nsp"))
    }

    func testDamagedNCAAmongGoodOnesIsNotTheKeys() {
        let other = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let files = [nsp("base.nsp", part: .base, [
            encrypted(plainHeader(generation: 0x05), key: other),
            encrypted(plainHeader(generation: 0x05)),
        ])]
        XCTAssertEqual(KeyCheck.check(keys: keys(["master_key_04"]), files: files), .fits)
    }

    func testUnopenableNCZIsCannotCheck() {
        let other = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let files = [nsp("base.nsz", part: .base, [encrypted(plainHeader(generation: 0x05), key: other)], ncz: true)]
        XCTAssertEqual(KeyCheck.check(keys: keys(["master_key_04"]), files: files), .cannotCheck(file: "base.nsz"))
    }

    func testXCIIsCannotCheck() {
        let files: [(part: KeyCheck.Part, name: String, container: KeyCheck.Container)] =
            [(.base, "game.xci", .unsupported)]
        XCTAssertEqual(KeyCheck.check(keys: keys([]), files: files), .cannotCheck(file: "game.xci"))
    }

    func testNoHeaderKey() {
        let files = [nsp("base.nsp", part: .base, [encrypted(plainHeader(generation: 0x05))])]
        XCTAssertEqual(KeyCheck.check(keys: ["master_key_04": [UInt8](repeating: 1, count: 16)], files: files),
                       .noHeaderKey)
    }

    func testParseKeysSkipsCommentsAndNonHex() {
        let parsed = KeyCheck.parseKeys("""
        ; comment
        HEADER_KEY = 00ff
        broken = zz
        master_key_00 = 0A0b

        """)
        XCTAssertEqual(parsed["header_key"], [0x00, 0xFF])
        XCTAssertEqual(parsed["master_key_00"], [0x0A, 0x0B])
        XCTAssertNil(parsed["broken"])
    }

    func testFirmwareForGeneration() {
        XCTAssertEqual(KeyCheck.firmware(forGeneration: 1), "1.0.0")
        XCTAssertEqual(KeyCheck.firmware(forGeneration: 12), "12.1.0")
        XCTAssertNil(KeyCheck.firmware(forGeneration: 99))
        XCTAssertNil(KeyCheck.firmware(forGeneration: 0))
    }

    func testReadContainerFindsNCAHeaders() throws {
        let header = encrypted(plainHeader(generation: 0x05))
        let name = Array("a.nca".utf8) + [0, 0, 0]
        var file = Array("PFS0".utf8)
        file += le32(1) + le32(UInt32(name.count)) + le32(0)
        file += le64(0) + le64(UInt64(header.count)) + le32(0) + le32(0)
        file += name + header
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keycheck-\(UUID().uuidString).nsp")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .pfs0(let headers) = KeyCheck.readContainer(url) else { return XCTFail("not a PFS0") }
        XCTAssertEqual(headers.count, 1)
        XCTAssertEqual(headers.first?.header, header)
        XCTAssertEqual(headers.first?.ncz, false)
    }

    func testReadContainerRejectsOtherFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keycheck-\(UUID().uuidString).xci")
        try Data(repeating: 0, count: 64).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .unsupported = KeyCheck.readContainer(url) else { return XCTFail("expected unsupported") }
    }

    func testRunWithUnreadableKeys() {
        let missing = URL(fileURLWithPath: "/nonexistent/prod.keys")
        XCTAssertEqual(KeyCheck.run(keysURL: missing, files: []), .unreadableKeys)
    }

    private func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
    private func le64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
}
