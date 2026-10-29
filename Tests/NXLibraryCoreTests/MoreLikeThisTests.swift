import XCTest
@testable import NXLibraryCore

final class MoreLikeThisTests: XCTestCase {
    private func game(_ name: String, hidden: Bool = false) -> PortedGame {
        var g = PortedGame(name: name, url: URL(fileURLWithPath: "/tmp/\(name).app"),
                           platform: .macApp, sizeBytes: 1,
                           modificationDate: Date(timeIntervalSince1970: 0))
        g.isHidden = hidden
        return g
    }

    private func meta(developers: [String] = [], publishers: [String] = [],
                      genres: [String] = []) -> NintendoStoreMetadata {
        NintendoStoreMetadata(titleId: "0100", name: "X", description: "", developers: developers,
                              publishers: publishers, genres: genres, releaseDate: nil,
                              storeURL: URL(string: "https://example.com")!, imageURL: nil,
                              headerImageURL: nil, nsuid: nil, fetchedAt: Date(timeIntervalSince1970: 0))
    }

    func testMoreLikeThisScoresAndExcludesSelfAndHidden() {
        let me = game("Me"), sameDev = game("Zed"), genre2 = game("Beta"), genre2b = game("Alpha")
        let genre1 = game("Gamma"), hidden = game("Hid", hidden: true), none = game("None")
        let data: [UUID: NintendoStoreMetadata] = [
            me.id: meta(developers: ["Dev"], genres: ["Action", "RPG"]),
            sameDev.id: meta(developers: ["Dev"]),
            genre2.id: meta(genres: ["Action", "RPG"]),
            genre2b.id: meta(publishers: ["Other"], genres: ["RPG", "Action"]),
            genre1.id: meta(genres: ["Action"]),
            hidden.id: meta(developers: ["Dev"], genres: ["Action", "RPG"]),
            none.id: meta(genres: ["Puzzle"]),
        ]
        let picks = MoreLikeThis.pick(for: me, in: [me, sameDev, genre2, genre2b, genre1, hidden, none],
                                      metadata: { data[$0] })
        // Alpha/Beta score 2 (tie by name), Zed scores 2 (developer) -> Alpha, Beta, Zed; Gamma 1.
        XCTAssertEqual(picks, [genre2b.id, genre2.id, sameDev.id, genre1.id])
        XCTAssertEqual(MoreLikeThis.pick(for: me, in: [me, sameDev, genre2, genre2b, genre1], metadata: { data[$0] },
                                         limit: 2), [genre2b.id, genre2.id])
    }

    func testMoreLikeThisEmptyWithoutMetadata() {
        let me = game("Me"), other = game("Other")
        XCTAssertEqual(MoreLikeThis.pick(for: me, in: [me, other], metadata: { _ in nil }), [])
        let data = [other.id: meta(developers: ["Dev"])]
        XCTAssertEqual(MoreLikeThis.pick(for: me, in: [me, other], metadata: { data[$0] }), [])
    }
}
