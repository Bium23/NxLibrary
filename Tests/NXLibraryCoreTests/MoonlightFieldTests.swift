import XCTest
@testable import NXLibraryCore

final class MoonlightFieldTests: XCTestCase {
    private let field = MoonlightField.particles()

    func testFieldHoldsEveryGroup() {
        let c = MoonlightField.counts
        XCTAssertEqual(field.count, c.stream + c.pool + c.air)
        XCTAssertEqual(field.filter { $0.kind == MoonlightParticle.Kind.stream }.count, c.stream)
        XCTAssertEqual(field.filter { $0.kind == MoonlightParticle.Kind.pool }.count, c.pool)
        XCTAssertEqual(field.filter { $0.kind == MoonlightParticle.Kind.air }.count, c.air)
        XCTAssertGreaterThanOrEqual(field.count, 3000, "thousands of motes, like Selene's video")
    }

    func testFieldIsTheSameEveryLaunch() {
        XCTAssertEqual(MoonlightField.particles(), field)
        XCTAssertNotEqual(MoonlightField.particles(seed: 7), field)
    }

    func testParticlesStayInTheirRanges() {
        let depth = MoonlightField.depth
        for p in field {
            XCTAssertTrue((0..<1).contains(p.start))
            XCTAssertTrue((0..<1).contains(p.phase))
            XCTAssertTrue(depth.contains(p.depth))
            XCTAssertLessThanOrEqual(abs(p.lane), MoonlightField.laneLimit)
            XCTAssertTrue(MoonlightField.size.contains(p.size))
            XCTAssertGreaterThan(p.speed, 0)
            XCTAssertTrue(p.tint == 0 || p.tint == 1)
        }
    }

    /// Most motes sit far, small and sharp; only a few come close enough to blur into bokeh.
    func testFewMotesComeNearEnoughForBokeh() {
        let near = field.filter { $0.depth < MoonlightField.focus * 0.6 }.count
        XCTAssertGreaterThan(near, 20)
        XCTAssertLessThan(Double(near) / Double(field.count), 0.08)
    }

    func testAboutAQuarterOfTheMotesTakeTheInk() {
        let share = Double(field.filter { $0.tint == 1 }.count) / Double(field.count)
        XCTAssertEqual(share, MoonlightField.inkShare, accuracy: 0.04)
    }

    /// The renderer hands the array to Metal as eight packed floats per mote.
    func testParticleIsEightPackedFloats() {
        XCTAssertEqual(MemoryLayout<MoonlightParticle>.stride, 8 * MemoryLayout<Float>.stride)
    }
}
