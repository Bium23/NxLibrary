import Foundation

public enum HoldResult: Equatable {
    case tap
    case hold
}

/// Distinguishes a tap from a hold on a single button. Time is supplied by the
/// caller so the logic stays deterministic.
public struct HoldDetector {
    public let threshold: TimeInterval
    private var pressedAt: TimeInterval?
    private var fired = false

    public init(threshold: TimeInterval = 0.5) {
        self.threshold = threshold
    }

    public var isPressed: Bool { pressedAt != nil }

    public mutating func press(at time: TimeInterval) {
        pressedAt = time
        fired = false
    }

    /// Returns `.hold` exactly once when the threshold passes while pressed.
    public mutating func tick(at time: TimeInterval) -> HoldResult? {
        guard let start = pressedAt, !fired, time - start >= threshold else { return nil }
        fired = true
        return .hold
    }

    /// `.tap` for a short press, `.hold` if released at/after the threshold
    /// without a prior tick, `nil` if the hold already fired or nothing was pressed.
    public mutating func release(at time: TimeInterval) -> HoldResult? {
        guard let start = pressedAt else { return nil }
        let wasFired = fired
        pressedAt = nil
        fired = false
        if wasFired { return nil }
        return time - start >= threshold ? .hold : .tap
    }
}
