import XCTest
@testable import NXLibraryCore

final class SpotlightRowGeometryTests: XCTestCase {
    private let extra = 174 * 0.3

    /// A tile's place on the screen is the camera plus its place in the row: the same places the row always drew.
    func testScreenPlaceIsTheCameraPlusThePlaceInTheRow() {
        let camera = SpotlightRowGeometry.camera(offset: 3)
        XCTAssertEqual(camera + SpotlightRowGeometry.place(of: 5, selected: 5), 72 + 2 * 178, accuracy: 1e-9)
        XCTAssertEqual(camera + SpotlightRowGeometry.place(of: 7, selected: 5), 72 + 4 * 178 + extra, accuracy: 1e-9)
        XCTAssertEqual(camera + SpotlightRowGeometry.place(of: 2, selected: 5), 72 - 178, accuracy: 1e-9)
        XCTAssertEqual(SpotlightRowGeometry.place(of: 4, selected: nil), 72 + 4 * 178, accuracy: 1e-9)
    }

    /// A tile that comes into the row while it slides has no glide of its own to catch up with: its place in the
    /// row stays put while the selection walks toward it, and the one camera carries it with its neighbours.
    func testATileAheadOfTheSelectionKeepsItsPlaceAsTheRowSlides() {
        let before = SpotlightRowGeometry.place(of: 14, selected: 4)
        for selected in 5...13 {
            XCTAssertEqual(SpotlightRowGeometry.place(of: 14, selected: selected), before, accuracy: 1e-9)
        }
    }

    /// The selection glides as one position (an index; `noSelection` is none). At a whole position the row stands
    /// as it always has: the places, sizes and camera of `place(of:selected:)` and `camera(offset:)`.
    func testAWholePositionIsTheRowAsItStands() {
        for selected in [nil, 0, 1, 2, 3, 7] as [Int?] {
            let position = selected.map { CGFloat($0) } ?? SpotlightRowGeometry.noSelection
            for index in 0..<12 {
                XCTAssertEqual(SpotlightRowGeometry.place(of: CGFloat(index), at: position),
                               SpotlightRowGeometry.place(of: index, selected: selected), accuracy: 1e-9)
                XCTAssertEqual(SpotlightRowGeometry.scale(of: CGFloat(index), at: position),
                               index == selected ? 1.3 : 1, accuracy: 1e-9)
            }
            let offset = selected.map(SpotlightState.scrollOffset(selectedIndex:)) ?? 0
            XCTAssertEqual(SpotlightRowGeometry.camera(at: position), SpotlightRowGeometry.camera(offset: offset),
                           accuracy: 1e-9)
        }
    }

    /// Between two tiles the one the selection leaves shrinks as much as the one it reaches grows, and every tile
    /// after them gives way by as much: neighbours keep their 4u wherever the glide is. With the place and the size
    /// glided apart, the growing tile pulled away from the tile on its right during quick presses.
    func testNeighboursKeepTheirGapAnywhereInTheGlide() {
        for step in 0...220 {
            let position = SpotlightRowGeometry.noSelection + CGFloat(step) * 0.05
            for index in 0..<12 {
                let tile = CGFloat(index)
                let right = SpotlightRowGeometry.place(of: tile, at: position) + 1
                    + 174 * SpotlightRowGeometry.scale(of: tile, at: position)
                let next = SpotlightRowGeometry.place(of: tile + 1, at: position) + 1
                XCTAssertEqual(next - right, 4, accuracy: 1e-9, "position \(position), tiles \(index) and \(index + 1)")
            }
        }
    }

    /// Tiles are made well past each edge, so a row still gliding after quick presses never shows one appear or
    /// vanish: four spare tiles beyond what the screen holds on either side.
    func testTheWindowKeepsFourSpareTilesPastEachEdge() {
        XCTAssertEqual(SpotlightRowGeometry.window(count: 100, offset: 20, tilesLeftOfStage: 1, tilesAcross: 8), 15..<32)
        XCTAssertEqual(SpotlightRowGeometry.window(count: 10, offset: 0, tilesLeftOfStage: 1, tilesAcross: 8), 0..<10)
        XCTAssertEqual(SpotlightRowGeometry.window(count: 0, offset: 0, tilesLeftOfStage: 1, tilesAcross: 8), 0..<0)
    }
}
