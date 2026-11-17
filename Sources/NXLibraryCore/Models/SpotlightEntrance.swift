import CoreGraphics

/// Spotlight's entrance, the first time the home shows after launch: the tiles fly in from the
/// row's centre while they grow, then the game's background and its info come up. The values are
/// Selene's (`HomeNav.PlayIntro`), in stage units.
public enum SpotlightEntrance {
    /// How one tile comes in. A tile that only fades keeps its place and size.
    public struct Flight: Equatable, Sendable {
        public let delay: Double
        public let fromX: CGFloat
        public let fromY: CGFloat
        public let fromScale: CGFloat
        public let duration: Double
        public let fadeDuration: Double
        public let fadesOnly: Bool
    }

    public static let backgroundDuration = 0.9
    public static let infoDelay = 0.9
    public static let infoFade = 0.5
    public static let infoLift: CGFloat = 40
    public static let infoLiftDuration = 0.55

    static let firstDelay = 0.30
    static let step = 0.045
    static let flightDuration = 0.65
    static let flightFade = 0.35
    static let lateFade = 0.3
    static let maxLate = 12

    /// One entry per tile, from each tile's horizontal extent on the stage. Tiles left of the
    /// stage stay as they are (`nil`); tiles past its right edge only fade, on the schedule of the
    /// tiles that fly, and at most twelve of them.
    public static func flights(tiles: [ClosedRange<CGFloat>], rowWidth: CGFloat) -> [Flight?] {
        let center = rowWidth / 2
        var flown = 0
        var late = 0
        return tiles.map { tile in
            guard tile.upperBound >= 0 else { return nil }
            let delay = firstDelay + Double(flown) * step
            if tile.lowerBound > rowWidth {
                guard late < maxLate else { return nil }
                late += 1
                return Flight(delay: delay, fromX: 0, fromY: 0, fromScale: 1,
                              duration: 0, fadeDuration: lateFade, fadesOnly: true)
            }
            flown += 1
            let tileCenter = (tile.lowerBound + tile.upperBound) / 2
            return Flight(delay: delay, fromX: (center - tileCenter) * 0.75, fromY: -18, fromScale: 0.35,
                          duration: flightDuration, fadeDuration: flightFade, fadesOnly: false)
        }
    }

    /// When the last tile has landed (or finished fading).
    public static func duration(of flights: [Flight?]) -> Double {
        flights.compactMap { $0.map { $0.delay + max($0.duration, $0.fadeDuration) } }.max() ?? 0
    }

    /// Once per launch, only when the home opens on Spotlight, never with Reduce motion.
    public static func plays(isFirstHome: Bool, route: AppRoute, reduceMotion: Bool) -> Bool {
        isFirstHome && route == .library && !reduceMotion
    }

    /// Covered by the intro or the welcome, waiting for the visible covers, flying, or done.
    public enum Phase: Equatable, Sendable {
        case covered, waiting, playing, landed

        public mutating func uncover() {
            if self == .covered { self = .waiting }
        }

        public mutating func start() {
            if self == .waiting { self = .playing }
        }

        /// Input, Reduce motion or the end of the flight: everything is in its place at once.
        public mutating func land() {
            self = .landed
        }

        /// Row, info and background are held hidden until the flight starts.
        public var holdsHidden: Bool { self == .covered || self == .waiting }
    }
}
