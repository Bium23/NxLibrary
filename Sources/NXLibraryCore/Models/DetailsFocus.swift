import Foundation

/// Focus on the Details page (spec §5.4). Zone 0 is the top block (Play or
/// Build, then Game options). Zones 1 to 3 are the bands: Screenshots,
/// Build & Sources (a two-column grid of actions, the activity beside it) and
/// More like this. A band with nothing to focus is skipped; Down goes to the
/// next band, Up back to the previous one, and Up from the first returns to
/// the top block.
public struct DetailsFocus: Equatable {
    /// How many items each band holds. A band with 0 items is not navigable.
    public struct Bands: Equatable {
        public var screenshots: Int
        public var actions: Int
        public var more: Int

        public init(screenshots: Int = 0, actions: Int = 0, more: Int = 0) {
            self.screenshots = max(0, screenshots)
            self.actions = max(0, actions)
            self.more = max(0, more)
        }

        func count(_ zone: Int) -> Int {
            switch zone {
            case DetailsFocus.screenshotsZone: return screenshots
            case DetailsFocus.actionsZone: return actions
            case DetailsFocus.moreZone: return more
            default: return 0
            }
        }
    }

    public static let topZone = 0
    public static let screenshotsZone = 1
    public static let actionsZone = 2
    public static let moreZone = 3
    /// Play or Build, then Options, then the Favorite heart.
    public static let pillCount = 3
    /// Build & Sources lays its actions out in rows, as on Spotlight.
    public static let actionColumns = SpotlightState.actionColumns

    public var zone = DetailsFocus.topZone
    public var pill = 0
    /// Pills on screen now: one while the game ports, otherwise `pillCount`.
    public private(set) var pillLimit = DetailsFocus.pillCount
    public var shot = 0
    public var action = 0
    public var more = 0

    public init() {}

    /// The pills changed (a porting started or ended): keep the focus on one that exists.
    public mutating func setPillLimit(_ limit: Int) {
        pillLimit = max(1, limit)
        pill = min(pill, pillLimit - 1)
    }

    /// Down: inside the action grid, the next row; otherwise the next band with items.
    @discardableResult
    public mutating func down(in bands: Bands) -> Bool {
        if zone == Self.actionsZone, let below = SpotlightState.actionBelow(action, count: bands.actions) {
            action = below
            return true
        }
        return moveZone(to: neighbour(of: zone, by: 1, in: bands))
    }

    /// Up: inside the action grid, the previous row; otherwise the previous band.
    @discardableResult
    public mutating func up(in bands: Bands) -> Bool {
        if zone == Self.actionsZone, action - Self.actionColumns >= 0 {
            action -= Self.actionColumns
            return true
        }
        return moveZone(to: neighbour(of: zone, by: -1, in: bands))
    }

    @discardableResult
    public mutating func left(in bands: Bands) -> Bool {
        switch zone {
        case Self.topZone:
            guard let next = Self.moved(pill, by: -1, count: pillLimit) else { return false }
            pill = next
            return true
        case Self.screenshotsZone:
            guard let next = Self.moved(shot, by: -1, count: bands.screenshots) else { return false }
            shot = next
            return true
        case Self.actionsZone:
            guard action % Self.actionColumns > 0 else { return false }
            action -= 1
            return true
        default:
            guard let next = Self.moved(more, by: -1, count: bands.more) else { return false }
            more = next
            return true
        }
    }

    @discardableResult
    public mutating func right(in bands: Bands) -> Bool {
        switch zone {
        case Self.topZone:
            guard let next = Self.moved(pill, by: 1, count: pillLimit) else { return false }
            pill = next
            return true
        case Self.screenshotsZone:
            guard let next = Self.moved(shot, by: 1, count: bands.screenshots) else { return false }
            shot = next
            return true
        case Self.actionsZone:
            guard action % Self.actionColumns < Self.actionColumns - 1, action + 1 < bands.actions else { return false }
            action += 1
            return true
        default:
            guard let next = Self.moved(more, by: 1, count: bands.more) else { return false }
            more = next
            return true
        }
    }

    /// A pointer press on a band item: that band and item, clamped to what it holds.
    public mutating func focus(zone target: Int, index: Int, in bands: Bands) {
        guard target != Self.topZone, bands.count(target) > 0 else { return }
        zone = target
        switch target {
        case Self.screenshotsZone: shot = Self.clamp(index, count: bands.screenshots)
        case Self.actionsZone: action = Self.clamp(index, count: bands.actions)
        default: more = Self.clamp(index, count: bands.more)
        }
    }

    /// Keeps the focus valid when the bands change (metadata arrives, a list shrinks):
    /// indexes are clamped, and a band that vanished gives way to the one above it.
    public mutating func settle(in bands: Bands) {
        if zone != Self.topZone, bands.count(zone) == 0 {
            zone = neighbour(of: zone, by: -1, in: bands) ?? Self.topZone
        }
        shot = Self.clamp(shot, count: bands.screenshots)
        action = Self.clamp(action, count: bands.actions)
        more = Self.clamp(more, count: bands.more)
    }

    // MARK: - Helpers

    private func isNavigable(_ target: Int, in bands: Bands) -> Bool {
        target == Self.topZone || bands.count(target) > 0
    }

    /// The nearest navigable zone from `from` in direction `step`, or nil at the page's end.
    private func neighbour(of from: Int, by stepSize: Int, in bands: Bands) -> Int? {
        var candidate = from + stepSize
        while candidate >= Self.topZone && candidate <= Self.moreZone {
            if isNavigable(candidate, in: bands) { return candidate }
            candidate += stepSize
        }
        return nil
    }

    private mutating func moveZone(to target: Int?) -> Bool {
        guard let target, target != zone else { return false }
        zone = target
        return true
    }

    /// The index after one step, clamped to the items; nil when it does not change.
    private static func moved(_ index: Int, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let next = clamp(index + delta, count: count)
        return next == index ? nil : next
    }

    private static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}
