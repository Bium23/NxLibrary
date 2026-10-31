import XCTest
@testable import NXLibraryCore

/// The parser mirrors nxnative's dm/host/hle_cheats.c (parse_file, ins_dec, meta_load, pairs_link) at the pin; the
/// cases come from dm/host/tests/t_cheats.c where it has one. Words are made-up stores, never a real game's cheat.
final class CheatFileTests: XCTestCase {
    private func entry(_ file: CheatFile, _ name: String) throws -> CheatEntry {
        try XCTUnwrap(file.entries.first { $0.name == name }, "no entry \(name)")
    }

    // t_cheats.c "labels": credits and section markers are labels; a glued header starts an entry
    func testHeadersWordsAndLabels() throws {
        let file = CheatFile.parse("[A]\n04000000 00001000 00000001\n[Credits]\n{M}\n04000000 00002000 00000002")
        XCTAssertEqual(file.entries.map(\.name), ["A", "Credits", "M"])
        XCTAssertEqual(try entry(file, "A").kind, .cheat)
        XCTAssertEqual(try entry(file, "A").words, [0x0400_0000, 0x0000_1000, 0x0000_0001])
        XCTAssertEqual(try entry(file, "Credits").kind, .label)
        XCTAssertEqual(try entry(file, "M").kind, .master)
        XCTAssertNil(try entry(file, "A").broken)
    }

    // t_cheats.c "glued": a run of hex digits is cut into 8-digit words, glued or not
    func testLongHexRunSplitsIntoWords() throws {
        let file = CheatFile.parse("[G]\n0400000000004420 00000003\n04000000 0000442400000004\n")
        XCTAssertEqual(try entry(file, "G").words.count, 6)
        XCTAssertNil(try entry(file, "G").broken)
    }

    // t_cheats.c "labels" / "labels2": a header glued to a word, code on the header's line, a bracket inside a name
    func testHeaderGluedToWord() throws {
        let file = CheatFile.parse("[a]\n04000000 00004070 00000001[b]\n04000000 00004074 00000002\n"
                                   + "[inline] 04000000 00004078 00000003\n[Max 999[A]]\n04000000 00004080 00000004\n")
        XCTAssertEqual(file.entries.map(\.name), ["a", "b", "inline", "Max 999[A"])
        XCTAssertEqual(try entry(file, "a").words.count, 3)
        XCTAssertEqual(try entry(file, "inline").words.count, 3)
        XCTAssertEqual(try entry(file, "Max 999[A").kind, .cheat)
    }

    // t_cheats.c "dup": the second entry of a name is keyed "X #2"
    func testDuplicateNamesAreNumbered() {
        let file = CheatFile.parse("[X]\n04000000 00004080 00000001\n[X]\n04000000 00004084 00000002\n[X]\n04000000 00004088 00000003\n")
        XCTAssertEqual(file.entries.map(\.name), ["X", "X #2", "X #3"])
    }

    // t_cheats.c "labels": entries between the markers carry the section; the markers are labels
    func testSectionsFromEdiZonMarkers() throws {
        let file = CheatFile.parse("[www.example.com]\n[--SectionStart:Stats--]\n[a]\n04000000 00004070 00000001\n"
                                   + "[--SectionEnd:Stats--]\n[far]\n04000000 00004074 00000001\n")
        XCTAssertEqual(try entry(file, "a").section, "Stats")
        XCTAssertNil(try entry(file, "far").section)
        XCTAssertEqual(try entry(file, "--SectionStart:Stats--").kind, .label)
        XCTAssertEqual(try entry(file, "www.example.com").kind, .label)
    }

    // hle_cheats.c onoff_split / pairs_link: "X - on" / "X - off" form one switch, the on half
    func testOnOffPairIsOneSwitch() throws {
        let file = CheatFile.parse("[Fly - on]\n04000000 00004000 00000001\n[Fly - off]\n04000000 00004000 00000000\n"
                                   + "[Walk]\n04000000 00004004 00000001\n")
        XCTAssertEqual(file.switches.map(\.name), ["Fly - on", "Walk"])
        XCTAssertTrue(try entry(file, "Fly - off").pairOff)
        XCTAssertEqual(try entry(file, "Fly - on").pairName, "Fly - off")
        XCTAssertEqual(try entry(file, "Fly - off").pairName, "Fly - on")
        XCTAssertEqual(file.summary.cheats, 2)
    }

    // hle_cheats.c ins_dec: B is not an opcode the host runs; a width outside 1/2/4/8 is refused; a malformed line
    // (t_cheats.c "labels2", "glued") turns the whole cheat off
    func testUnsupportedOpcodeIsBroken() throws {
        let file = CheatFile.parse("[B]\nB0000000\n[W]\n03000000 00004000 00000001\n[C]\n14070000 00004000 00000001\n"
                                   + "[T]\n04000000 00004000\n[typo]\n0400000 0000407C 00000001\n[typo2]\nhello world\n"
                                   + "[Prose]\nby dead beef\n04000000 0000442C 00000005\n[FF0]\nFF000000\n")
        XCTAssertEqual(try entry(file, "B").broken, "unsupported opcode B")
        XCTAssertEqual(try entry(file, "W").broken, "width")
        XCTAssertEqual(try entry(file, "C").broken, "condition")
        XCTAssertEqual(try entry(file, "T").broken, "truncated")
        XCTAssertEqual(try entry(file, "typo").broken, "malformed line 10")
        XCTAssertEqual(try entry(file, "typo2").broken, "no code words: line 12 is not code")
        XCTAssertEqual(try entry(file, "Prose").broken, "malformed line 14")
        XCTAssertEqual(try entry(file, "FF0").broken, "unsupported opcode FF0")
        XCTAssertFalse(file.switches.contains { $0.broken != nil })
    }

    // hle_cheats.c CHEAT_MAX 256 (the rest skipped), INS_MAX 0x2000 (a line past it skipped), FILE_MAX 4 MiB
    func testLimits() {
        let many = (1...257).map { "[c\($0)]\n04000000 00004000 00000001\n" }.joined()
        XCTAssertEqual(CheatFile.parse(many).entries.count, 256)
        let full = "[Big]\n" + String(repeating: "04000000 00004000 00000001\n", count: 0x2000 / 3)
            + "04000000 00004000 00000001\n"
        XCTAssertEqual(CheatFile.parse(full).entries.first?.words.count, 0x2000 / 3 * 3)
        let huge = Data(count: CheatFile.maxBytes + 1)
        XCTAssertTrue(CheatFile.parse(huge).entries.isEmpty)
    }

    // Review Focus 1: the engine reads a UTF-8 BOM as prose and loses the first header; NX Library writes files
    // without it (CheatFile.normalized), and CRLF needs nothing
    func testWindowsFileParsesLikeUnix() {
        let unix = "[A]\n04000000 00001000 00000001\n[B]\n04000000 00001004 00000001\n"
        let windows = Data([0xEF, 0xBB, 0xBF]) + Data(unix.replacingOccurrences(of: "\n", with: "\r\n").utf8) + Data("\r\n".utf8)
        XCTAssertEqual(CheatFile.parse(CheatFile.normalized(windows)), CheatFile.parse(unix))
        XCTAssertEqual(CheatFile.parse(windows).entries.map(\.name), ["B"], "the engine itself drops the header after a BOM")
    }

    // hle_cheats.c meta_load: columns by header name, rows matched by name in order
    func testMetaGivesSectionNoteOncePair() throws {
        var file = CheatFile.parse("[Gold]\n04000000 00004000 00000001\n[Jump]\n04000000 00004004 00000001\n"
                                   + "[Jump restore]\n04000000 00004004 00000000\n")
        file.applyMeta("# cheat_anchor.py: compiled from x for build 1111111111111111\n"
                       + "note\tname\tonce\tsection\tkind\tpair\tresolved\n"
                       + "Pick up\tGold\t1\tItems\tpatch\t\tstrong\n"
                       + "\tJump\t\t\tpatch\tJump restore\t\n"
                       + "\tJump restore\t\t\tpatch-off\tJump\t\n")
        XCTAssertEqual(try entry(file, "Gold").section, "Items")
        XCTAssertEqual(try entry(file, "Gold").note, "strong; Pick up")
        XCTAssertTrue(try entry(file, "Gold").once)
        XCTAssertTrue(try entry(file, "Jump restore").pairOff)
        XCTAssertEqual(try entry(file, "Jump").pairName, "Jump restore")
        XCTAssertEqual(file.switches.map(\.name), ["Jump"])
    }

    func testSummaryText() {
        let cheats = (1...10).map { "[c\($0)]\n04000000 00004000 00000001\n" }.joined()
        let file = CheatFile.parse(cheats + "{M}\n04000000 00004000 00000001\n[b1]\nB0000000\n[b2]\nB0000000\n")
        XCTAssertEqual(file.summary.cheats, 12)
        XCTAssertEqual(file.summary.alwaysOn, 1)
        XCTAssertEqual(file.summary.notSupported, 2)
        XCTAssertEqual(file.summaryText, "12 cheats · 1 always on · 2 not supported")
        XCTAssertEqual(CheatFile.parse("[A]\n04000000 00004000 00000001\n").summaryText, "1 cheat")
    }
}
