import Foundation

public enum WorkspaceMode: Equatable {
    case folder(URL)
    case staged
}

public struct Workspace: Equatable {
    public var directory: URL
    public var buildCache: URL
    public var links: [URL]

    public init(directory: URL, buildCache: URL, links: [URL]) {
        self.directory = directory
        self.buildCache = buildCache
        self.links = links
    }
}

public final class WorkspaceManager {
    private let root: URL
    private let fm: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fm = fileManager
    }

    public func makeWorkspace(for game: DetectedGame, mode: WorkspaceMode) throws -> Workspace {
        switch mode {
        case .folder(let dir):
            let cache = dir.appendingPathComponent(cacheName(for: game))
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            return Workspace(directory: dir, buildCache: cache, links: [])
        case .staged:
            let dir = root.appendingPathComponent(String(format: "%016llX", game.baseTitleId))
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let cache = dir.appendingPathComponent(cacheName(for: game))
            // Only links owned by this workspace are replaced. Never walk a link
            // into the original source tree, and leave build-cache contents alone.
            if let contents = fm.enumerator(at: dir, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                var oldLinks: [URL] = []
                for case let entry as URL in contents {
                    if entry.resolvingSymlinksInPath() == cache.resolvingSymlinksInPath() { contents.skipDescendants(); continue }
                    if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                        contents.skipDescendants()
                        oldLinks.append(entry)
                    }
                }
                for entry in oldLinks { try fm.removeItem(at: entry) }
                for entry in oldLinks {
                    var parent = entry.deletingLastPathComponent()
                    while parent.resolvingSymlinksInPath() != dir.resolvingSymlinksInPath(),
                          parent.resolvingSymlinksInPath().path.hasPrefix(dir.resolvingSymlinksInPath().path + "/"),
                          (try? fm.contentsOfDirectory(atPath: parent.path).isEmpty) == true {
                        try fm.removeItem(at: parent)
                        parent.deleteLastPathComponent()
                    }
                }
            }
            var links: [URL] = []
            var seen = Set<String>()
            for source in game.allSources {
                let relative: String
                if source.layout == .extracted {
                    switch source.kind {
                    case .base: relative = "base"
                    case .update:
                        guard let version = source.version, version > 0 else { throw EngineSourceError.invalidDump("invalid update version") }
                        relative = "updates/\(version)"
                    case .dlc: relative = String(format: "dlc/%016llX/0/romfs", source.titleId)
                    case .unknown: throw EngineSourceError.invalidDump("unknown content")
                    }
                } else { relative = source.url.lastPathComponent }
                guard seen.insert(relative).inserted else { continue }
                let link = dir.appendingPathComponent(relative)
                try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: link.path)
                    || (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
                    try fm.removeItem(at: link)
                }
                try fm.createSymbolicLink(at: link, withDestinationURL: source.url)
                links.append(link)
            }
            try fm.createDirectory(at: cache, withIntermediateDirectories: true)
            return Workspace(directory: dir, buildCache: cache, links: links)
        }
    }

    /// A workspace that already exists beside the sources can be adopted
    /// without touching its build cache, which is what makes rebuilds fast.
    public func adoptExistingWorkspace(for game: DetectedGame, folder: URL) -> Workspace {
        let cache = folder.appendingPathComponent(cacheName(for: game))
        return Workspace(directory: folder, buildCache: cache, links: [])
    }

    public func brokenLinks(in workspace: URL) -> [URL] {
        guard let items = try? fm.contentsOfDirectory(
            at: workspace, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [] }
        return items.compactMap { item -> URL? in
            guard let destination = try? fm.destinationOfSymbolicLink(atPath: item.path) else {
                return nil
            }
            let target = URL(fileURLWithPath: destination,
                             relativeTo: item.deletingLastPathComponent()).standardizedFileURL
            guard !fm.fileExists(atPath: target.path) else { return nil }
            // contentsOfDirectory may hand back /private/var while the workspace
            // URL is /var; keep the caller's spelling so comparisons match.
            return workspace.appendingPathComponent(item.lastPathComponent)
        }
    }

    private func cacheName(for game: DetectedGame) -> String {
        String(format: "%016llX_build", game.baseTitleId)
    }
}
