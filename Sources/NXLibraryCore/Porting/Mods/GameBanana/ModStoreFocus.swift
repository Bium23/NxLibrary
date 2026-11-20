import Foundation

/// Focus on the mod store page. It is anchored on a section's kind, not its position, so rows that arrive above (a
/// game's mods found in the background) never move the focus to another row. Down goes to the next section, Up to
/// the previous one, and Up from the first leaves the store; Left/Right move inside a section, which remembers its
/// tile. Featured wraps around like a carousel; the other rows stop at their ends.
public struct ModStoreFocus: Equatable {
    public struct Section: Equatable {
        public let kind: ModStoreSectionKind
        public let count: Int

        public init(kind: ModStoreSectionKind, count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    public private(set) var kind: ModStoreSectionKind = .sort
    private var indexes: [ModStoreSectionKind: Int] = [:]
    /// The sections as last seen, to find the one above a section that vanished.
    private var seen: [ModStoreSectionKind] = []

    public init() {}

    /// The focused tile (or sort choice) in the focused section.
    public var index: Int { indexes[kind] ?? 0 }

    /// The tile a section shows as last focused.
    public func index(of kind: ModStoreSectionKind) -> Int { indexes[kind] ?? 0 }

    public func position(in sections: [Section]) -> Int {
        sections.firstIndex { $0.kind == kind } ?? 0
    }

    @discardableResult
    public mutating func down(in sections: [Section]) -> Bool {
        seen = sections.map(\.kind)
        let at = position(in: sections)
        guard at + 1 < sections.count else { return false }
        kind = sections[at + 1].kind
        return true
    }

    /// False at the top: the store gives the focus back to the row.
    @discardableResult
    public mutating func up(in sections: [Section]) -> Bool {
        seen = sections.map(\.kind)
        let at = position(in: sections)
        guard at > 0, at < sections.count else { return false }
        kind = sections[at - 1].kind
        return true
    }

    @discardableResult
    public mutating func left(in sections: [Section]) -> Bool { move(by: -1, in: sections) }

    @discardableResult
    public mutating func right(in sections: [Section]) -> Bool { move(by: 1, in: sections) }

    /// A pointer press on a tile.
    public mutating func focus(_ target: ModStoreSectionKind, index: Int, in sections: [Section]) {
        guard let section = sections.first(where: { $0.kind == target }), section.count > 0 else { return }
        kind = target
        indexes[target] = min(max(index, 0), section.count - 1)
    }

    /// Keeps the focus valid when the sections change: a vanished section gives way to the nearest one above it
    /// (by the order it had), and every index is clamped to what its section holds.
    public mutating func settle(in sections: [Section]) {
        if !sections.contains(where: { $0.kind == kind }) {
            let above = seen.firstIndex(of: kind).map { Array(seen.prefix($0).reversed()) } ?? []
            kind = above.first { old in sections.contains { $0.kind == old } } ?? sections.first?.kind ?? .sort
        }
        seen = sections.map(\.kind)
        for section in sections {
            if let index = indexes[section.kind] { indexes[section.kind] = min(index, max(section.count - 1, 0)) }
        }
    }

    private mutating func move(by delta: Int, in sections: [Section]) -> Bool {
        guard let section = sections.first(where: { $0.kind == kind }), section.count > 0 else { return false }
        let current = min(index, section.count - 1)
        var next = current + delta
        if kind == .featured {
            guard section.count > 1 else { return false }
            next = (next + section.count) % section.count
        }
        guard next >= 0, next < section.count, next != current else { return false }
        indexes[kind] = next
        return true
    }
}
