import Foundation

public enum BuildState: Equatable {
    case idle
    case running
    case succeeded
    case failed
    case cancelled
}
