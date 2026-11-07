import Foundation

/// Selection is by content; workspace links and disk usage are by physical input.
public enum SourceSelection {
    public static func initialTitleID(available: [String], previous: String?) -> String? {
        if let previous, available.contains(previous) { return previous }
        return available.count == 1 ? available.first : nil
    }

    /// Catalog rescans create new UUIDs. Restore choices by physical content, never by those transient IDs.
    public static func restoredSelection(previous: [GameFileItem], selected: Set<UUID>,
                                         current: [GameFileItem]) -> Set<UUID> {
        let old = previous.map { (file: $0, key: ContentKey($0)) }
        let next = current.map { (file: $0, key: ContentKey($0)) }
        var result = initial(in: current)
        for entry in next where entry.file.kind != .base {
            let matches = old.filter { $0.key.matches(entry.key) }
            guard matches.count == 1, let match = matches.first else { continue }
            if selected.contains(match.file.id) { result.insert(entry.file.id) }
            else { result.remove(entry.file.id) }
        }
        if old.contains(where: { $0.file.kind == .update }) {
            result.subtract(current.filter { $0.kind == .update }.map(\.id))
            let chosen = old.filter { $0.file.kind == .update && selected.contains($0.file.id) }
            let updates = next.filter { entry in
                entry.file.kind == .update && chosen.contains { $0.key.matches(entry.key) }
            }
            if updates.count == 1, let update = updates.first { result.insert(update.file.id) }
        }
        return includingBundledDLC(in: current, selected: withRequiredUpdate(in: current, selected: result))
    }

    private struct ContentKey {
        let path: String
        let kind: SourceKind
        let title: String?
        let version: Int?

        init(_ file: GameFileItem) {
            path = SourceSelection.path(file)
            kind = file.kind
            title = file.titleId?.uppercased()
            version = file.versionString.flatMap { Int($0.lowercased().replacingOccurrences(of: "v", with: "")) }
        }

        func matches(_ other: Self) -> Bool {
            path == other.path && kind == other.kind
                && (title == nil || other.title == nil || title == other.title)
                && (version == nil || other.version == nil || version == other.version)
        }
    }

    public static func supported(_ files: [GameFileItem], titleSelection: Bool, extractedFolders: Bool,
                                 nupContainers: Bool = false) -> Bool {
        files.allSatisfy { ($0.layout != .extracted || extractedFolders)
            && ($0.layout != .container || nupContainers)
            && ($0.requiresTitleSelection != true || titleSelection) }
    }
    private static func path(_ file: GameFileItem) -> String {
        file.url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func uniqueSize(_ files: [GameFileItem]) -> Int64 {
        var seen = Set<String>()
        return files.reduce(0) { $0 + (seen.insert(path($1)).inserted ? $1.sizeBytes : 0) }
    }

    /// Whether the files hold a game the engine can build: a base game, or an update of a NUP or a dump with no base game.
    public static func hasGame(_ files: [GameFileItem]) -> Bool {
        files.contains { $0.kind == .base } || isUpdateOnly(files)
    }

    /// A NUP (nxnative 777a5f6c) or an extracted dump (pack_dump) with no base game: it has no v0, and the selected
    /// update is taken as the whole game. An NSP update without its base cannot be built.
    public static func isUpdateOnly(_ files: [GameFileItem]) -> Bool {
        !files.contains { $0.kind == .base }
            && files.contains { $0.kind == .update && ($0.layout == .container || $0.layout == .extracted) }
    }

    public static func requiresKeys(_ files: [GameFileItem]) -> Bool {
        files.contains { $0.layout == .package }
    }

    public static func versionForBuild(_ files: [GameFileItem]) -> String? {
        let updates = files.filter { $0.kind == .update }
        // A base game alone is packed at its own version: v0 for most, v65536 for one the eShop serves at 1.1.0 (nxnative 5c4dc18f).
        guard !updates.isEmpty else {
            let base = files.first { $0.kind == .base }?.versionString
            let digits = base.map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
            return "v\(digits.flatMap(Int.init) ?? 0)"
        }
        guard let raw = updates.first?.versionString else { return nil }
        let digits = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        return Int(digits).map { "v\($0)" }
    }

    public static func initial(in files: [GameFileItem]) -> Set<UUID> {
        var selected = Set(files.filter { $0.kind == .base || ($0.kind == .dlc && $0.sizeBytes > 0) }.map(\.id))
        if let update = files.filter({ $0.kind == .update }).max(by: {
            version($0) < version($1)
        }) { selected.insert(update.id) }
        return includingBundledDLC(in: files, selected: selected)
    }

    /// The base stays in; with no base game, the selected update stays in until another is chosen.
    public static func isLocked(_ file: GameFileItem, in files: [GameFileItem], selected: Set<UUID>) -> Bool {
        file.kind == .base
            || (file.kind == .update && selected.contains(file.id) && isUpdateOnly(files))
            || (file.kind == .dlc && files.contains {
            selected.contains($0.id) && $0.kind != .dlc && path($0) == path(file)
        })
    }

    public static func toggling(_ id: UUID, in files: [GameFileItem], selected: Set<UUID>) -> Set<UUID> {
        guard let file = files.first(where: { $0.id == id }), !isLocked(file, in: files, selected: selected) else { return selected }
        var result = selected
        if file.kind == .dlc {
            let group = Set(files.filter { $0.kind == .dlc && path($0) == path(file) }.map(\.id))
            if selected.contains(id) { result.subtract(group) } else { result.formUnion(group) }
        } else if selected.contains(id) {
            result.remove(id)
        } else {
            if file.kind == .update { result.subtract(files.filter { $0.kind == .update }.map(\.id)) }
            result.insert(id)
        }
        return includingBundledDLC(in: files, selected: result)
    }

    /// With no base game, one update is always selected: the newest when none of the previous choices remains.
    private static func withRequiredUpdate(in files: [GameFileItem], selected: Set<UUID>) -> Set<UUID> {
        let updates = files.filter { $0.kind == .update }
        guard isUpdateOnly(files), !updates.contains(where: { selected.contains($0.id) }),
              let newest = updates.max(by: { version($0) < version($1) }) else { return selected }
        return selected.union([newest.id])
    }

    private static func includingBundledDLC(in files: [GameFileItem], selected: Set<UUID>) -> Set<UUID> {
        let paths = Set(files.filter { selected.contains($0.id) }.map(path))
        return selected.union(files.filter { $0.kind == .dlc && paths.contains(path($0)) }.map(\.id))
    }

    private static func version(_ file: GameFileItem) -> Int {
        Int(file.versionString?.replacingOccurrences(of: "v", with: "") ?? "") ?? -1
    }
}
