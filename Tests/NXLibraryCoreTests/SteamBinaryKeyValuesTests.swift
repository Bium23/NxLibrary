import XCTest
@testable import NXLibraryCore

/// Writes Steam's binary KeyValues for tests: a `[(key, value)]` array is a subtree, a String is type 1, an Int32
/// type 2, a Float type 3, a UInt64 type 7.
enum BinaryKV {
    static func data(_ entries: [(String, Any)], end: Bool = true) -> Data {
        var out = Data()
        write(entries, into: &out)
        if end { out.append(8) }
        return out
    }

    private static func write(_ entries: [(String, Any)], into out: inout Data) {
        for (key, value) in entries {
            switch value {
            case let sub as [(String, Any)]:
                out.append(0); cString(key, &out); write(sub, into: &out); out.append(8)
            case let text as String:
                out.append(1); cString(key, &out); cString(text, &out)
            case let number as Int32:
                out.append(2); cString(key, &out); withUnsafeBytes(of: number.littleEndian) { out.append(contentsOf: $0) }
            case let number as Float:
                out.append(3); cString(key, &out); withUnsafeBytes(of: number.bitPattern.littleEndian) { out.append(contentsOf: $0) }
            case let number as UInt64:
                out.append(7); cString(key, &out); withUnsafeBytes(of: number.littleEndian) { out.append(contentsOf: $0) }
            default:
                preconditionFailure("unsupported test value \(value)")
            }
        }
    }

    private static func cString(_ text: String, _ out: inout Data) {
        out.append(contentsOf: Array(text.utf8)); out.append(0)
    }
}

final class SteamBinaryKeyValuesTests: XCTestCase {
    func testReadsEveryType() throws {
        let data = BinaryKV.data([("root", [
            ("text", "a"), ("int", Int32(-7)), ("float", Float(1.5)), ("big", UInt64(1) << 40),
        ] as [(String, Any)])])
        let entries = try SteamBinaryKeyValues.parse(data)
        XCTAssertEqual(entries, [KeyValuesEntry(key: "root", value: .object([
            KeyValuesEntry(key: "text", value: .string("a")),
            KeyValuesEntry(key: "int", value: .string("-7")),
            KeyValuesEntry(key: "float", value: .string("1.5")),
            KeyValuesEntry(key: "big", value: .string("1099511627776")),
        ]))])
    }

    func testKeepsOrderAndDuplicates() throws {
        let entries = try SteamBinaryKeyValues.parse(BinaryKV.data([("b", "1"), ("a", "2"), ("b", "3")]))
        XCTAssertEqual(entries.map(\.key), ["b", "a", "b"])
    }

    func testTruncatedThrowsMalformed() {
        let data = BinaryKV.data([("root", [("int", Int32(5))] as [(String, Any)])], end: false)
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(data.dropLast(2))) {
            XCTAssertEqual($0 as? KeyValuesError, .malformed)
        }
    }

    func testUnknownTypeThrowsMalformed() {
        var data = Data([5]); data.append(contentsOf: Array("x".utf8)); data.append(0)
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(data)) { XCTAssertEqual($0 as? KeyValuesError, .malformed) }
    }

    func testDepthLimit() {
        var nested: [(String, Any)] = [("leaf", "x")]
        for _ in 0..<33 { nested = [("n", nested)] }
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(BinaryKV.data(nested), maximumDepth: 32)) {
            XCTAssertEqual($0 as? KeyValuesError, .limitExceeded)
        }
    }

    func testTopLevelNeedsItsTerminator() throws {
        XCTAssertEqual(try SteamBinaryKeyValues.parse(BinaryKV.data([("a", "1")], end: true)).count, 1)
        // Cut just before the last byte (Steam writing the file): not a shorter file, a broken one.
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(BinaryKV.data([("a", "1")], end: false))) {
            XCTAssertEqual($0 as? KeyValuesError, .malformed)
        }
    }

    func testEmptyDataThrows() {
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(Data())) { XCTAssertEqual($0 as? KeyValuesError, .malformed) }
    }

    func testAnUnclosedSubtreeThrows() {
        var data = Data([0]); data.append(contentsOf: Array("s".utf8)); data.append(0)
        data.append(1); data.append(contentsOf: Array("k".utf8)); data.append(0); data.append(contentsOf: Array("v".utf8)); data.append(0)
        XCTAssertThrowsError(try SteamBinaryKeyValues.parse(data)) { XCTAssertEqual($0 as? KeyValuesError, .malformed) }
    }
}
