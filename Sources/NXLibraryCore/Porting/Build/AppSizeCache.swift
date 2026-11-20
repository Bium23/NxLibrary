import Foundation

/// Sizes of built game apps, by path and modification date, kept between launches: measuring an app walks every
/// file in it (hundreds of thousands for a large game), so a library scan measures only apps that are new or rebuilt.
public final class AppSizeCache {
    private struct Entry: Codable {
        var date: Date
        var size: Int64
    }

    private let file: URL?
    private let lock = NSLock()
    private var entries: [String: Entry]

    /// `file` nil keeps the sizes in memory only.
    public init(file: URL?) {
        self.file = file
        entries = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    private static func key(_ app: URL) -> String { app.standardizedFileURL.path }

    public func size(for app: URL, date: Date) -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[Self.key(app)], entry.date == date else { return nil }
        return entry.size
    }

    public func set(_ size: Int64, for app: URL, date: Date) {
        lock.lock(); defer { lock.unlock() }
        entries[Self.key(app)] = Entry(date: date, size: size)
    }

    /// Forgets every app not in `apps`.
    public func retain(_ apps: [URL]) {
        let keep = Set(apps.map(Self.key))
        lock.lock(); defer { lock.unlock() }
        entries = entries.filter { keep.contains($0.key) }
    }

    public func save() {
        guard let file else { return }
        lock.lock()
        let data = try? JSONEncoder().encode(entries)
        lock.unlock()
        guard let data else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// The library's "No games yet": only once the library has been read, never while it still loads at launch.
public enum LibraryEmptyState {
    public static func showsMessage(hasGames: Bool, isReadingLibrary: Bool) -> Bool {
        !hasGames && !isReadingLibrary
    }
}
