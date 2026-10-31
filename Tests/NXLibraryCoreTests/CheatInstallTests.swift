import XCTest
@testable import NXLibraryCore

final class CheatInstallTests: XCTestCase {
    private let tid = "0100000000010000"
    private let build = "B424BE150A8E7D78"
    private let text = Data("[A]\n04000000 00004000 00000001\n".utf8)

    private func decide(_ name: String, _ data: Data? = nil, tree: String? = nil) -> CheatInstall.Decision {
        CheatInstall.decide(fileName: name, data: data ?? text, titleIDInPath: tree, buildID: build, titleID: tid)
    }

    func testMatchingBuildInstalls() {
        guard case .install(let file) = decide("\(build).txt") else { return XCTFail() }
        XCTAssertEqual(file.switches.map(\.name), ["A"])
        guard case .install = decide("\(build.lowercased()).txt") else { return XCTFail("any case, as name_is_build") }
    }

    func testOtherBuildRefusedByName() {
        XCTAssertEqual(decide("0123456789ABCDEF.txt"), .otherBuild("0123456789ABCDEF"))
        XCTAssertEqual(decide("0123456789abcdef.txt"), .otherBuild("0123456789ABCDEF"))
    }

    func testUnnamedAsks() {
        guard case .confirmUnnamed = decide("cheats.txt") else { return XCTFail() }
        guard case .confirmUnnamed = decide("Zelda 1.2 cheats.txt") else { return XCTFail() }
    }

    func testOtherTitleInTree() {
        XCTAssertEqual(decide("\(build).txt", tree: "01007EF00011E000"), .otherTitle("01007EF00011E000"))
        guard case .install = decide("\(build).txt", tree: tid.lowercased()) else { return XCTFail() }
    }

    /// Review Focus 4.
    func testBinaryOrHugeFileIsRefused() {
        guard case .refused = decide("\(build).txt", Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00])) else { return XCTFail("zip bytes") }
        guard case .refused = decide("\(build).txt", Data([0x5B, 0x41, 0x5D, 0x0A, 0xFF, 0xFE, 0x0A])) else { return XCTFail("not UTF-8") }
        guard case .refused = decide("\(build).txt", Data(repeating: 0x30, count: CheatFile.maxBytes + 1)) else { return XCTFail("huge") }
    }

    func testNoCheatRefused() {
        guard case .refused = decide("\(build).txt", Data("[Credits]\n[--SectionStart:x--]\n".utf8)) else { return XCTFail() }
        guard case .refused = decide("\(build).txt", Data()) else { return XCTFail() }
    }

    func testBOMFileInstalls() {
        guard case .install(let file) = decide("\(build).txt", Data([0xEF, 0xBB, 0xBF]) + text) else { return XCTFail() }
        XCTAssertEqual(file.switches.map(\.name), ["A"])
    }

    func testCandidatesInSDTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CheatInstall-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = root.appendingPathComponent("atmosphere/contents/\(tid)/cheats")
        let bare = root.appendingPathComponent("contents/01007EF00011E000/cheats")
        for folder in [tree, bare] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try text.write(to: tree.appendingPathComponent("\(build).txt"))
        try text.write(to: bare.appendingPathComponent("0123456789ABCDEF.TXT"))
        try text.write(to: root.appendingPathComponent("loose.txt"))
        try text.write(to: root.appendingPathComponent("readme.md"))
        let found = CheatInstall.candidates(in: root).map { "\($0.url.lastPathComponent)|\($0.titleIDInPath ?? "-")" }
        XCTAssertEqual(Set(found), ["\(build).txt|\(tid)", "0123456789ABCDEF.TXT|01007EF00011E000", "loose.txt|-"])
        XCTAssertEqual(CheatInstall.titleID(inPath: tree.appendingPathComponent("\(build).txt")), tid)
        XCTAssertNil(CheatInstall.titleID(inPath: root.appendingPathComponent("loose.txt")))
    }
}
