import Foundation

public struct FocusIndex: Equatable {
    public var index: Int

    public init(index: Int = 0) { self.index = index }

    public mutating func move(by delta: Int, count: Int) {
        guard count > 0 else {
            index = 0
            return
        }
        index = min(max(index + delta, 0), count - 1)
    }
}
