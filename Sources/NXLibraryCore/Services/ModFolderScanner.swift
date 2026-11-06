import Foundation

/// Reads a game's `mods` folder: which subfolders there are, where each one's RomFS tree is, and the files in it.
/// A mod's RomFS is what the engine's `DM_ROMFS_OVERLAY` reads before the game's own (dm/host/hle_fs.c).
public enum ModFolderScanner {
    /// The mod's RomFS tree: `<folder>/romfs`, else the Atmosphère layouts `<folder>/atmosphere/contents/<TID>/romfs`
    /// and `<folder>/contents/<TID>/romfs` (title ID in either case). A real directory, never a symlink, so an overlay
    /// path cannot lead out of the mods folder.
    public static func romfs(in folder: URL, titleID: String) -> URL? {
        let ids = [titleID.uppercased(), titleID.lowercased()]
        let candidates = [folder.appendingPathComponent("romfs")]
            + ids.map { folder.appendingPathComponent("atmosphere/contents/\($0)/romfs") }
            + ids.map { folder.appendingPathComponent("contents/\($0)/romfs") }
        return candidates.first(where: isRealDirectory)
    }

    /// The mods folder's visible entries, sorted by name: subfolders and stray files (an archive not unzipped yet, which
    /// is then shown as not a mod). Hidden entries and symlinks are left out.
    public static func entries(in modsFolder: URL) -> [URL] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: modsFolder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                   options: .skipsHiddenFiles)) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Every file under a RomFS tree, as a path relative to it, in its exact case (RomFS paths are case-sensitive).
    /// Hidden files (Finder's `.DS_Store`) are left out: the game never reads them.
    public static func files(under romfs: URL) -> Set<String> {
        let base = romfs.resolvingSymlinksInPath().standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: romfs, includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: .skipsHiddenFiles) else { return [] }
        var found: Set<String> = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            found.insert(String(path.dropFirst(base.count + 1)))
        }
        return found
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
