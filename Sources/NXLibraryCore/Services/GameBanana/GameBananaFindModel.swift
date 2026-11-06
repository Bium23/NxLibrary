import Foundation
import Combine

/// "Find the game" / "Wrong game?": search GameBanana by name and pick this game's page. Its state lives here so the
/// page's controller and key handling can drive it.
@MainActor
public final class GameBananaFindModel: ObservableObject {
    @Published public var isOpen = false
    @Published public var query = ""
    @Published public private(set) var results: [GameBananaGame] = []
    @Published public private(set) var searching = false
    @Published public private(set) var searched = false
    /// The focused row: results, then None of these.
    @Published public var focus = 0

    private var task: Task<Void, Never>?

    public init() {}

    /// The name field has the focus: Up from the first row reaches it, Down or A (Return) leaves it.
    @Published public var editing = false

    public var rowCount: Int { results.count + 1 }

    public func open(name: String, using band: GameBananaBandModel) {
        query = name
        results = []
        searched = false
        focus = 0
        editing = false
        isOpen = true
        search(using: band)
    }

    public func close() {
        task?.cancel()
        isOpen = false
    }

    public func search(using band: GameBananaBandModel) {
        task?.cancel()
        let text = query
        searching = true
        task = Task { [weak self] in
            let found = await band.search(text)
            guard !Task.isCancelled, let self else { return }
            self.results = Array(found.prefix(8))
            self.searching = false
            self.searched = true
            self.focus = 0
        }
    }

    public func move(by delta: Int) -> Bool {
        if editing {
            guard delta > 0 else { return false }
            editing = false
            return true
        }
        if delta < 0, focus == 0 {
            editing = true
            return true
        }
        let next = min(max(focus + delta, 0), rowCount - 1)
        guard next != focus else { return false }
        focus = next
        return true
    }

    /// A (Return): searches while the name has the focus, otherwise runs the focused row.
    public func confirm(using band: GameBananaBandModel) {
        if editing {
            editing = false
            search(using: band)
        } else {
            activate(focus, using: band)
        }
    }

    /// Runs a row. None of these waits until a search has answered, so a press while it runs saves nothing.
    public func activate(_ index: Int, using band: GameBananaBandModel) {
        if index < results.count {
            band.confirm(results[index])
        } else {
            guard searched, !searching else { return }
            band.noneOfThese()
        }
        close()
    }
}
