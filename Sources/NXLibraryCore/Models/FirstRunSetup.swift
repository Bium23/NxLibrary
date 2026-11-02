import Foundation

/// First launch stays unfinished until the player opens the library, picks sources, or explicitly skips.
public struct FirstRunSetup: Equatable {
    public enum Page: String { case requirements, games }
    public enum LibraryState: Equatable { case scanning, empty, ready }

    public private(set) var page: Page
    public private(set) var isCompleted: Bool

    public init(completed: Bool = false, savedPage: String? = nil) {
        isCompleted = completed
        page = completed ? .requirements : savedPage.flatMap(Page.init(rawValue:)) ?? .requirements
    }

    public var pageToRemember: String? { isCompleted ? nil : page.rawValue }

    public mutating func advance() {
        page = .games
    }

    public mutating func goBack() {
        page = .requirements
    }

    public mutating func finish() {
        isCompleted = true
        page = .requirements
    }

    public static func libraryState(isScanning: Bool, gameCount: Int) -> LibraryState {
        isScanning ? .scanning : gameCount > 0 ? .ready : .empty
    }

    /// An accepted picker arrival is consumed once, independently of whether Add Game changed route.
    public struct ReviewEntry {
        private var reviewedID: UUID?
        public init() {}

        public mutating func consume(_ id: UUID?, isReady: Bool, titleCount: Int) -> Bool {
            guard let id, id != reviewedID, isReady, titleCount == 1 else { return false }
            reviewedID = id
            return true
        }
    }

    public enum Focus: Equatable {
        case apps, file, folder, back, finish

        public func moved(_ direction: MoveDirection) -> Self {
            switch (self, direction) {
            case (.apps, .down): return .file
            case (.file, .up): return .apps
            case (.file, .down): return .folder
            case (.folder, .up): return .file
            case (.folder, .down): return .finish
            case (.finish, .left): return .back
            case (.back, .right): return .finish
            case (.finish, .up), (.back, .up): return .folder
            default: return self
            }
        }
    }
}
