import CoreGraphics

/// Spotlight's entrance, the app's opening: a breath on the moving moonlight, then the game's background
/// fades in as when moving between games, only slower, while the tiles fly in from the row's centre and
/// grow, then the info rises; the top bar and the button hints come last. Nothing skips it. The shape is Selene's (`HomeNav.PlayIntro`) at a calmer pace.
/// Lengths in stage units, times in seconds.
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

        /// How long this piece runs from its delay: its move or its fade, whichever is longer.
        public var length: Double { max(duration, fadeDuration) }

        /// How far it has moved (0 at the start, 1 in place) `time` seconds after its delay, on a cubic out.
        public func move(at time: Double) -> CGFloat {
            guard duration > 0 else { return 1 }
            let rest = 1 - min(1, max(0, time / duration))
            return CGFloat(1 - rest * rest * rest)
        }

        /// Its opacity `time` seconds after its delay, linear.
        public func opacity(at time: Double) -> Double {
            guard fadeDuration > 0 else { return 1 }
            return min(1, max(0, time / fadeDuration))
        }
    }

    /// The moving moonlight alone before anything else comes in.
    public static let hold = 0.5
    /// The game's art fading in over the moonlight, on the crossfade's own curve (`OpacityFade`).
    public static let backgroundDuration = 1.4
    public static let infoDelay = 1.3
    public static let infoFade = 0.7
    public static let infoLift: CGFloat = 40
    public static let infoLiftDuration = 0.8
    /// The title under the selected tile comes once the tiles are in.
    public static let titleDelay = 2.0
    /// The top bar and the button hints come in last, together, once everything else has landed.
    public static let controlsFade = 0.4
    /// A started flight lands by then whatever happens, so input is never held for long.
    public static let longestWait = 5.0

    /// The game's title and info: they fade in and rise 40 units once the background is up.
    public static let info = Flight(delay: infoDelay, fromX: 0, fromY: infoLift, fromScale: 1,
                                    duration: infoLiftDuration, fadeDuration: infoFade, fadesOnly: false)

    static let firstDelay = 0.6
    static let step = 0.06
    static let flightDuration = 0.9
    static let flightFade = 0.5
    static let lateFade = 0.4
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

    /// An empty tab's message comes in just after the last tile that flies (Selene's `RowEmptyIn`).
    public static func message(after flights: [Flight?]) -> Flight {
        let flown = flights.filter { $0.map { !$0.fadesOnly } ?? false }.count
        return Flight(delay: firstDelay + Double(flown) * step + 0.25, fromX: 0, fromY: 0, fromScale: 1,
                      duration: 0, fadeDuration: lateFade, fadesOnly: true)
    }

    /// When everything is in: the tiles, the info and an empty tab's message.
    public static func end(of flights: [Flight?]) -> Double {
        [duration(of: flights), info.delay + info.length, message(after: flights).delay + lateFade].max() ?? 0
    }

    /// When the last tile has landed (or finished fading).
    public static func duration(of flights: [Flight?]) -> Double {
        flights.compactMap { $0.map { $0.delay + max($0.duration, $0.fadeDuration) } }.max() ?? 0
    }

    /// Once per launch, only when the home opens on Spotlight, with Settings → Start-up → Entrance animation on
    /// (`AppSettings.introAnimation`), never with Reduce motion.
    public static func plays(isFirstHome: Bool, route: AppRoute, reduceMotion: Bool, enabled: Bool) -> Bool {
        enabled && isFirstHome && route == .library && !reduceMotion
    }

    /// Covered by the welcome or Setup, waiting for the visible covers, flying, or done.
    public enum Phase: Equatable, Sendable {
        case covered, waiting, playing, landed

        public mutating func uncover() {
            if self == .covered { self = .waiting }
        }

        public mutating func start() {
            if self == .waiting { self = .playing }
        }

        /// The end of the flight, Reduce motion, a resize or leaving: everything is in its place at once.
        public mutating func land() {
            self = .landed
        }

        /// Row, info and background are held hidden until the flight starts.
        public var holdsHidden: Bool { self == .covered || self == .waiting }

        /// Keys, clicks, the wheel and the controller reach Spotlight only once it has landed: the entrance
        /// always plays to its end.
        public var takesInput: Bool { self == .landed }
    }
}
