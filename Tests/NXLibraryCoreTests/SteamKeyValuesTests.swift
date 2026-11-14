import XCTest
@testable import NXLibraryCore

final class SteamKeyValuesTests: XCTestCase {
    func testReadsNestedLibraryWithSpacesAndUnicode() throws {
        let document = try KeyValuesDocument(text: "\"libraryfolders\" { \"0\" { \"path\" \"/Volumes/Giochi è/SteamLibrary\" } }")
        guard case .object(let libraries)? = try document.uniqueValue(for: "libraryfolders"),
              case .object(let first)? = try libraries.uniqueValue(for: "0") else {
            return XCTFail("Missing library")
        }
        XCTAssertEqual(try first.uniqueValue(for: "PATH"), .string("/Volumes/Giochi è/SteamLibrary"))
    }

    func testCommentsDoNotConsumeSlashesInsideStrings() throws {
        let document = try KeyValuesDocument(text: "// heading\nname \"https://example.invalid/game\" // comment\nempty {}")
        XCTAssertEqual(try document.uniqueValue(for: "name"), .string("https://example.invalid/game"))
        XCTAssertEqual(try document.uniqueValue(for: "empty"), .object([]))
    }

    func testQuotedEscapeSequencesAndUnquotedScalars() throws {
        let document = try KeyValuesDocument(text: #"name "A \"quote\" \\ slash\nline\ttab\rend" appid 10"#)
        XCTAssertEqual(try document.uniqueValue(for: "name"), .string("A \"quote\" \\ slash\nline\ttab\rend"))
        XCTAssertEqual(try document.uniqueValue(for: "appid"), .string("10"))
    }

    func testConflictingCaseVariantsAreNotSilentlyOverwritten() throws {
        let document = try KeyValuesDocument(text: "appid 10 APPID 20")
        XCTAssertEqual(document.entries.count, 2)
        XCTAssertThrowsError(try document.uniqueValue(for: "appid"))
    }

    func testUnknownDuplicateFieldsRemainInTheDocument() throws {
        let document = try KeyValuesDocument(text: "unknown first unknown second appid 10")
        XCTAssertEqual(document.entries.map(\.key), ["unknown", "unknown", "appid"])
        XCTAssertEqual(try document.uniqueValue(for: "appid"), .string("10"))
        XCTAssertNil(try document.uniqueValue(for: "absent"))
    }

    func testRejectsMalformedAndTruncatedDocuments() {
        for text in ["key", "{", "key {", "key }", "key { child value", "key value }", "key \"unterminated", #"key "bad\q""#] {
            XCTAssertThrowsError(try KeyValuesDocument(text: text), text)
        }
    }

    func testDoesNotExecuteIncludeOrBaseDirectives() {
        for directive in ["#include", "#base", "#INCLUDE"] {
            XCTAssertThrowsError(try KeyValuesDocument(text: "\(directive) \"/private/should-not-be-read\""))
        }
    }

    func testDepthLimitAllowsBoundaryAndRejectsOneMoreObject() throws {
        XCTAssertNoThrow(try KeyValuesDocument(text: "a { b c }", maximumDepth: 1))
        XCTAssertThrowsError(try KeyValuesDocument(text: "a { b { c d } }", maximumDepth: 1))
    }

    func testEntryLimitCountsNestedEntries() throws {
        XCTAssertNoThrow(try KeyValuesDocument(text: "a { b c }", maximumEntries: 2))
        XCTAssertThrowsError(try KeyValuesDocument(text: "a { b c d e }", maximumEntries: 2))
    }

    func testEmptyDocumentAndUtf8Bom() throws {
        XCTAssertEqual(try KeyValuesDocument(text: " \n// empty").entries, [])
        XCTAssertEqual(try KeyValuesDocument(text: "\u{FEFF}appid 10").uniqueValue(for: "appid"), .string("10"))
    }
}
