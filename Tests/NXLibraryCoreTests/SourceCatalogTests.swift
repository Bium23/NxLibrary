import XCTest
@testable import NXLibraryCore

final class SourceCatalogTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXSources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testClassifyTitleIds() {
        XCTAssertEqual(SourceCatalog.classify(titleId: 0x0100000000010000), .base)
        XCTAssertEqual(SourceCatalog.classify(titleId: 0x0100000000010800), .update)
        XCTAssertEqual(SourceCatalog.classify(titleId: 0x0100000000011001), .dlc)
    }

    func testGroupsBaseUpdateAndDlc() throws {
        let base = dir.appendingPathComponent("Game [0100000000010000][v0].nsp")
        let update = dir.appendingPathComponent("Game [0100000000010800][v65536].nsp")
        let dlc = dir.appendingPathComponent("Game [0100000000011001][v0].nsp")
        try makeNSP(at: base, titleId: 0x0100000000010000, type: "Application", version: 0)
        try makeNSP(at: update, titleId: 0x0100000000010800, type: "Patch", version: 65536)
        try makeNSP(at: dlc, titleId: 0x0100000000011001, type: "AddOnContent", version: 0)
        let games = try SourceCatalog().scan(files: [base, update, dlc])
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].base?.kind, .base)
        XCTAssertEqual(games[0].updates.count, 1)
        XCTAssertEqual(games[0].dlcs.count, 1)
    }

    func testXCIUsesFilenameTitleId() throws {
        let xci = dir.appendingPathComponent("Game [0100000000010000][v0].xci")
        try Data("x".utf8).write(to: xci)
        let games = try SourceCatalog().scan(files: [xci])
        XCTAssertEqual(games.count, 1)
        XCTAssertEqual(games[0].base?.kind, .base)
        XCTAssertEqual(games[0].base?.titleId, 0x0100000000010000)
    }

    func testUpdateOnlyHasNoBase() throws {
        let update = dir.appendingPathComponent("Game [0100000000010800][v65536].nsp")
        try makeNSP(at: update, titleId: 0x0100000000010800, type: "Patch", version: 65536)
        let games = try SourceCatalog().scan(files: [update])
        XCTAssertEqual(games.count, 1)
        XCTAssertNil(games[0].base)
        XCTAssertEqual(games[0].updates.count, 1)
    }

    func testTicketFallback() throws {
        var tik = Data(repeating: 0, count: 0x2A8)
        let tid = UInt64(0x0100000000010000).bigEndian
        withUnsafeBytes(of: tid) { tik.replaceSubrange(0x2A0..<0x2A8, with: $0) }
        let nsp = dir.appendingPathComponent("ticket-only.nsp")
        try PFS0Fixture.write(to: nsp, files: [("ticket.tik", tik)])
        let games = try SourceCatalog().scan(files: [nsp])
        XCTAssertEqual(games.first?.base?.titleId, 0x0100000000010000)
    }

    private func makeNSP(at url: URL, titleId: UInt64, type: String, version: Int) throws {
        let xml = """
        <ContentMeta><Type>\(type)</Type><Id>0x\(String(titleId, radix: 16))</Id>\
        <Version>\(version)</Version><OriginalId>0x0100000000010000</OriginalId></ContentMeta>
        """
        try PFS0Fixture.write(to: url, files: [
            ("meta.cnmt.xml", Data(xml.utf8)),
        ])
    }
}

enum PFS0Fixture {
    static func write(to url: URL, files: [(String, Data)]) throws {
        func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
        func le64(_ v: UInt64) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 8) }
        let strings = files.reduce(Data()) { acc, f in
            var d = acc; d.append(Data(f.0.utf8)); d.append(0); return d
        }
        var out = Data("PFS0".utf8)
        out.append(le32(UInt32(files.count)))
        out.append(le32(UInt32(strings.count)))
        out.append(le32(0))
        var stringOffset = 0
        var dataOffset: UInt64 = 0
        for (name, data) in files {
            out.append(le64(dataOffset))
            out.append(le64(UInt64(data.count)))
            out.append(le32(UInt32(stringOffset)))
            out.append(le32(0))
            stringOffset += name.utf8.count + 1
            dataOffset += UInt64(data.count)
        }
        out.append(strings)
        for (_, data) in files { out.append(data) }
        try out.write(to: url)
    }
}
