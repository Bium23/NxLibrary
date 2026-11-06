import CoreGraphics
import Foundation

/// The selected tile's ring and shine as loops: their curves, and the samples Core Animation plays on its own.
/// Played by Core Animation, the loops cost the app nothing between frames; redrawn by SwiftUI at the screen's
/// rate, they kept a quarter of a core busy on a still screen.
public enum TileMotion {
    /// The ring's gradient turns once in this time.
    public static let ringPeriod: Double = 5
    /// The glow rises and falls once in this time (1.8 s each way).
    public static let glowPeriod: Double = 3.6
    /// The shine's cycle: hold 0.6 s, sweep until 2.4 s, wait until 5 s.
    public static let shinePeriod: Double = 5
    /// Half the shine band's width, in diagonal units (0 = top-left corner, 1 = bottom-right).
    public static let shineHalfWidth = 0.3

    /// 0.2 <-> 0.55 over 1.8 s, sine in-out, autoreverse.
    public static func glowOpacity(at t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: glowPeriod) / (glowPeriod / 2)
        let tri = p <= 1 ? p : 2 - p
        return 0.2 + 0.35 * (0.5 - 0.5 * cos(.pi * tri))
    }

    /// The ring gradient's ends in unit space (y down), its axis turned clockwise by t / 5 of a turn.
    public static func ringAxis(at t: Double) -> (start: CGPoint, end: CGPoint) {
        let radians = t.truncatingRemainder(dividingBy: ringPeriod) / ringPeriod * 2 * .pi
        let dx = cos(radians) * 0.5, dy = sin(radians) * 0.5
        return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    /// The shine band's centre along the diagonal `t` seconds after the tile was selected. It enters past one
    /// corner and leaves past the other, so it never pops in or out.
    public static func shineCentre(at t: Double) -> Double {
        let cycle = t.truncatingRemainder(dividingBy: shinePeriod)
        let raw = min(max((cycle - 0.6) / 1.8, 0), 1)
        let eased = 0.5 - 0.5 * cos(.pi * raw)
        return -shineHalfWidth + eased * (1 + 2 * shineHalfWidth)
    }

    /// The shine gradient's ends in unit space: along the top-left → bottom-right diagonal, round its centre.
    public static func shineAxis(at t: Double) -> (start: CGPoint, end: CGPoint) {
        let c = shineCentre(at: t), w = shineHalfWidth
        return (CGPoint(x: c - w, y: c - w), CGPoint(x: c + w, y: c + w))
    }

    /// `steps + 1` evenly spaced samples over one period, with their key times (0…1). Core Animation glides
    /// from each sample to the next, so the last is the period's end as it is approached (a hair before it):
    /// a smooth loop closes on its first value, and the shine, which starts over from the far corner, jumps
    /// back as the loop repeats instead of sweeping back across the tile.
    public static func loop<Value>(period: Double, steps: Int,
                                   _ value: (Double) -> Value) -> (values: [Value], keyTimes: [Double]) {
        let keyTimes = (0...steps).map { Double($0) / Double(steps) }
        let times = keyTimes.dropLast().map { $0 * period } + [period.nextDown]
        return (times.map(value), keyTimes)
    }

    /// How far into its period a loop on the shared clock is at `time`.
    public static func phase(period: Double, at time: Double) -> Double {
        time.truncatingRemainder(dividingBy: period)
    }
}
