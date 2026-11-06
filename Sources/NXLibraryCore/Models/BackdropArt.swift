import Foundation

/// Whether Spotlight's backdrop may keep the previous game's art while the selected game's loads: only when the
/// selection came from another game, never right after a card. It answers from the selection the body sees, so the
/// first render of a new selection (before `onChange` records it) already knows, and the art never drops out for
/// that render and comes straight back.
public struct BackdropArtRule: Equatable, Sendable {
    /// The selection last recorded, whether it is a game, and whether it was reached from a game.
    private var key: String?
    private var isGame = false
    private var fromGame = false

    public init() {}

    public mutating func select(_ key: String?, isGame: Bool) {
        guard key != self.key else { return }
        fromGame = self.isGame && isGame
        self.isGame = isGame
        self.key = key
    }

    public func keepsOtherArt(selection key: String?, isGame: Bool) -> Bool {
        guard isGame else { return false }
        // Not recorded yet: the recorded selection is the one it came from.
        return key == self.key ? fromGame : self.isGame
    }
}

/// One art layer's opacity glide, worked out from the clock. Core Animation has no presentation for a layer added
/// in the pass still open, so reading one back gives the layer's end value and an interrupted fade-in jumps to full;
/// the clock knows where the fade is.
public struct OpacityFade: Equatable, Sendable {
    public var from: Float
    public var to: Float
    /// `CACurrentMediaTime()` when it starts.
    public var start: Double
    public var duration: Double

    /// Core Animation's ease-in-ease-out; the animation takes the same curve.
    public static let controlPoints: (Float, Float, Float, Float) = (0.42, 0, 0.58, 1)

    public init(from: Float, to: Float, start: Double, duration: Double) {
        self.from = from
        self.to = to
        self.start = start
        self.duration = duration
    }

    public func isDone(at time: Double) -> Bool { time >= start + duration }

    public func value(at time: Double) -> Float {
        guard duration > 0, time < start + duration else { return to }
        guard time > start else { return from }
        let eased = Self.ease(Float((time - start) / duration))
        return from + (to - from) * eased
    }

    /// The curve's height where its x is `x`: x(t) is solved by bisection (monotonic), then y(t).
    static func ease(_ x: Float) -> Float {
        let (x1, y1, x2, y2) = controlPoints
        func bezier(_ t: Float, _ a: Float, _ b: Float) -> Float {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        var low: Float = 0, high: Float = 1
        for _ in 0..<32 {
            let mid = (low + high) / 2
            if bezier(mid, x1, x2) < x { low = mid } else { high = mid }
        }
        return bezier((low + high) / 2, y1, y2)
    }
}

/// The art layers under the newest: quick browsing stacks one per game, each frozen part way in. A layer that lets
/// less than half an 8-bit step through above it hides everything below, so those layers go with no visible change,
/// and the stack stays a few layers deep instead of one full-screen image per game passed.
public enum ArtStack {
    /// Half an 8-bit step: below it no pixel changes.
    public static let unseen: Float = 1.0 / 512

    /// How many layers at the bottom of `opacities` (bottom to top) no longer show.
    public static func hiddenCount(_ opacities: [Float]) -> Int {
        var through: Float = 1
        for index in opacities.indices.reversed() {
            through *= 1 - min(max(opacities[index], 0), 1)
            if through < unseen { return index }
        }
        return 0
    }
}
