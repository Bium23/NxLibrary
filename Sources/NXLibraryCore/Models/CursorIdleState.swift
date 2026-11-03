import Foundation

/// Idle policy only; the shell owns AppKit cursor effects and window eligibility.
public struct CursorIdleState {
    public private(set) var isHidden = false
    private var idleSince: TimeInterval?
    public init() {}
    public mutating func update(now: TimeInterval, eligible: Bool) -> Bool {
        guard eligible else {
            idleSince = nil
            isHidden = false
            return false
        }
        if idleSince == nil { idleSince = now }
        isHidden = now - (idleSince ?? now) >= 3
        return isHidden
    }
    public mutating func mouseActivity(now: TimeInterval) {
        idleSince = now
        isHidden = false
    }
}
