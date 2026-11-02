import Foundation

/// Selection is by content; workspace links and disk usage are by physical input.
public enum SourceSelection {
    public static func supported(_ files: [GameFileItem], titleSelection: Bool, extractedFolders: Bool) -> Bool {
        files.allSatisfy { ($0.layout != .extracted || extractedFolders)
            && ($0.requiresTitleSelection != true || titleSelection) }
    }
    private static func path(_ file: GameFileItem) -> String {
        file.url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    public static func uniqueSize(_ files: [GameFileItem]) -> Int64 {
        var seen = Set<String>()
        return files.reduce(0) { $0 + (seen.insert(path($1)).inserted ? $1.sizeBytes : 0) }
    }

    public static func requiresKeys(_ files: [GameFileItem]) -> Bool {
        files.contains { $0.layout == .package }
    }

    public static func versionForBuild(_ files: [GameFileItem]) -> String? {
        let updates = files.filter { $0.kind == .update }
        guard !updates.isEmpty else { return "v0" }
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

    public static func isLocked(_ file: GameFileItem, in files: [GameFileItem], selected: Set<UUID>) -> Bool {
        file.kind == .base || (file.kind == .dlc && files.contains {
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

    private static func includingBundledDLC(in files: [GameFileItem], selected: Set<UUID>) -> Set<UUID> {
        let paths = Set(files.filter { selected.contains($0.id) }.map(path))
        return selected.union(files.filter { $0.kind == .dlc && paths.contains(path($0)) }.map(\.id))
    }

    private static func version(_ file: GameFileItem) -> Int {
        Int(file.versionString?.replacingOccurrences(of: "v", with: "") ?? "") ?? -1
    }
}
