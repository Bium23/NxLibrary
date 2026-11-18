import Foundation

/// The established nxnative scan merge, shared with the legacy store. It only
/// handles nxnative payloads; other catalog integrations never enter this path.
enum NXNativeLibraryMerge {
    static func merge(scanned: [PortedGame], into existing: [PortedGame], replacingSources: Bool = false,
                      fileManager fm: FileManager = .default) -> [PortedGame] {
        var games = existing
        for game in scanned {
            if let index = games.firstIndex(where: { existing in
                if existing.id == game.id { return true }
                guard let target = game.titleId else { return false }
                return existing.titleId?.caseInsensitiveCompare(target) == .orderedSame
            }) {
                let old = games[index]
                // Scans refresh disk observations. Application-owned state survives a scan.
                var merged = old
                merged.name = game.name
                merged.url = game.url
                merged.platform = game.platform
                merged.sizeBytes = game.sizeBytes
                merged.modificationDate = game.modificationDate
                merged.bundleId = game.bundleId
                merged.titleId = game.titleId
                merged.versionString = game.versionString
                merged.status = game.status
                merged.toolchain = game.toolchain
                merged.lastBuild = game.lastBuild
                let explicitSources = replacingSources && !game.sources.isEmpty
                if explicitSources || old.sources.isEmpty {
                    merged.sources = game.sources
                } else {
                    let oldSourcesExist = old.sources.allSatisfy {
                        fm.fileExists(atPath: $0.url.path)
                    }
                    merged.sources = (oldSourcesExist || game.sources.isEmpty)
                        ? old.sources : game.sources
                }
                merged.workspacePath = explicitSources ? game.workspacePath ?? old.workspacePath : old.workspacePath ?? game.workspacePath
                merged.buildCachePath = explicitSources ? game.buildCachePath ?? old.buildCachePath : old.buildCachePath ?? game.buildCachePath
                if (old.status == .built || old.status == .builtSourcesMissing
                    || old.status == .needsRebuild),
                   old.url.pathExtension.lowercased() == "app",
                   fm.fileExists(atPath: old.url.path) {
                    merged.url = old.url
                    merged.sizeBytes = old.sizeBytes
                    merged.bundleId = old.bundleId ?? merged.bundleId
                    merged.versionString = old.versionString ?? merged.versionString
                }
                if old.status == .built || old.status == .builtSourcesMissing
                    || old.status == .needsRebuild {
                    if merged.sources.isEmpty {
                        merged.status = game.status == .built ? .built : .builtSourcesMissing
                    } else {
                        let sourcesExist = merged.sources.allSatisfy {
                            fm.fileExists(atPath: $0.url.path)
                        }
                        merged.status = sourcesExist ? .built : .builtSourcesMissing
                    }
                    merged.toolchain = old.toolchain
                    merged.lastBuild = old.lastBuild
                }
                games[index] = merged
            } else {
                games.append(game)
            }
        }
        return games
    }
}
