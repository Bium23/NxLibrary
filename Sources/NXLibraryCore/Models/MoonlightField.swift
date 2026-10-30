import Foundation

/// One mote of the moonlight backdrop, as the Metal renderer reads it: eight
/// packed floats. Where it is on screen is worked out on the GPU from these and
/// the time, so the array never changes after launch.
public struct MoonlightParticle: Equatable {
    public enum Kind {
        /// Flows along the band from the pool to the right edge.
        public static let stream: Float = 0
        /// Rises off the pool of light and fades.
        public static let pool: Float = 1
        /// Drifts loose across the whole window, dim.
        public static let air: Float = 2
    }

    /// Where along its path it starts (0..<1).
    public var start: Float
    /// Offset across its path, in standard deviations (gaussian, clamped to `laneLimit`).
    public var lane: Float
    /// Distance from the camera, `MoonlightField.focus` sharp; nearer blurs into bokeh.
    public var depth: Float
    /// Share of its path travelled per second.
    public var speed: Float
    /// Radius at depth 1, in window heights.
    public var size: Float
    /// Its own beat for bobbing and twinkling (0..<1).
    public var phase: Float
    public var kind: Float
    /// 0 the theme's accent, 1 its ink.
    public var tint: Float
}

/// The moonlight's particle field: thousands of motes in a volume, mostly far and
/// fine, a few near enough to blur. Seeded, so it is the same every launch.
public enum MoonlightField {
    public static let counts = (stream: 2300, pool: 560, air: 240)
    public static let depth: ClosedRange<Float> = 0.45...3.2
    /// The depth in focus.
    public static let focus: Float = 1.4
    public static let laneLimit: Float = 2.6
    public static let size: ClosedRange<Float> = 0.0012...0.0052
    public static let inkShare = 0.28
    /// Share of the path per second: the stream crosses in about 70–140 s, the pool's motes live 15–30 s.
    static let speeds = (stream: Float(0.007)...0.014, pool: Float(0.033)...0.066, air: Float(0.003)...0.008)

    public static func particles(seed: UInt64 = 0x5E1E4E) -> [MoonlightParticle] {
        var random = SplitMix(seed: seed)
        func pick(_ range: ClosedRange<Float>, _ u: Float) -> Float {
            range.lowerBound + (range.upperBound - range.lowerBound) * u
        }
        func make(_ kind: Float, speed: ClosedRange<Float>) -> MoonlightParticle {
            // Box-Muller: most motes near their path's line, a few further out.
            let gauss = (-2 * log(max(random.unit(), 1e-9))).squareRoot() * cos(2 * .pi * random.unit())
            return MoonlightParticle(
                start: Float(random.unit()),
                lane: max(-laneLimit, min(laneLimit, Float(gauss))),
                // Skewed far: only a few percent come near enough to blur.
                depth: pick(depth, Float(pow(random.unit(), 0.5))),
                speed: pick(speed, Float(random.unit())),
                // Mostly fine points, a few larger.
                size: pick(size, Float(pow(random.unit(), 2))),
                phase: Float(random.unit()),
                kind: kind,
                tint: random.unit() < inkShare ? 1 : 0)
        }
        return (0..<counts.stream).map { _ in make(MoonlightParticle.Kind.stream, speed: speeds.stream) }
            + (0..<counts.pool).map { _ in make(MoonlightParticle.Kind.pool, speed: speeds.pool) }
            + (0..<counts.air).map { _ in make(MoonlightParticle.Kind.air, speed: speeds.air) }
    }
}

/// Deterministic numbers so the particle field is the same every launch.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
