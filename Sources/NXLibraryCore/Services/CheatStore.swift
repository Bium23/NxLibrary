import Foundation

/// A game's cheats as they are on disk now, read the way the host loads them.
public struct CheatState: Equatable, Sendable {
    /// This build's file: the flat folder first, then the Atmosphère tree (hle_cheats.c scan_dirs).
    public var file: CheatFile?
    /// Keys the host would turn on at the next start (from `<build ID>.enabled`, read as states_read does).
    public var enabled: Set<String>
    public var hasEnabledFile: Bool
    /// No `.cheats-off-<title ID>`.
    public var masterOn: Bool
    /// `.cheats-running-<title ID>` exists: the last run ended with cheats on and without a clean exit.
    public var safeModePending: Bool
    /// Build IDs of the folder's other cheat files, upper case, sorted.
    public var otherBuilds: [String]

    /// Switches that are on (an on / off pair is one switch).
    public var onCount: Int { file?.switches.filter { enabled.contains($0.name) }.count ?? 0 }
}

public enum CheatStoreError: Error, Equatable {
    /// The game is running: the host owns the files until it quits.
    case notAllowed
    case writeFailed(String)
}

/// One game's cheat files in the folder its host reads (docs/frontends.md, Cheats): `<build ID>.txt`,
/// `<build ID>.enabled`, `.cheats-off-<title ID>`. Every write is a temporary file renamed over the target, and only
/// while `canWrite` says the game is not running; `.cheats-running-<title ID>` is the host's and never touched.
public struct CheatStore {
    public let folder: URL
    public let titleID: String
    public let buildID: String
    private let canWrite: () -> Bool
    private let trash: (URL) throws -> Void
    private let fm = FileManager.default

    public init(folder: URL, titleID: String, buildID: String,
                canWrite: @escaping () -> Bool, trash: @escaping (URL) throws -> Void) {
        self.folder = folder
        self.titleID = titleID.uppercased()
        self.buildID = buildID.uppercased()
        self.canWrite = canWrite
        self.trash = trash
    }

    private var enabledURL: URL { folder.appendingPathComponent("\(buildID).enabled") }
    private var offFlag: URL { folder.appendingPathComponent(".cheats-off-\(titleID)") }
    private var runningFlag: URL { folder.appendingPathComponent(".cheats-running-\(titleID)") }

    // MARK: - Reading

    /// The .txt files of the three folders the host scans, in its order.
    private func candidates() -> [URL] {
        [folder,
         folder.appendingPathComponent("atmosphere/contents/\(titleID)/cheats"),
         folder.appendingPathComponent("contents/\(titleID)/cheats")].flatMap { dir in
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "txt" && $0.lastPathComponent.count >= 5 }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    private func isThisBuild(_ url: URL) -> Bool { CheatInstall.build(inName: url.lastPathComponent) == buildID }

    private func metaURL(_ txt: URL) -> URL {
        txt.deletingPathExtension().appendingPathExtension("meta.tsv")
    }

    public func state() -> CheatState {
        let all = candidates()
        let picked = all.first(where: isThisBuild)
        var file: CheatFile?
        var meta: String?
        if let picked, let data = try? Data(contentsOf: picked) {
            var parsed = CheatFile.parse(data)
            meta = try? String(contentsOf: metaURL(picked), encoding: .utf8)
            if let meta { parsed.applyMeta(meta) }
            file = parsed
        }
        let saved = try? String(contentsOf: enabledURL, encoding: .utf8)
        var lines = saved
        if lines == nil, let meta, let carried = carriedEnabled(source: Self.metaSource(meta)) { lines = carried }
        var others: [String] = []
        for url in all where !isThisBuild(url) {
            guard let b = CheatInstall.build(inName: url.lastPathComponent) ?? Self.hexPrefix(url.lastPathComponent),
                  !others.contains(b) else { continue }
            others.append(b)
        }
        return CheatState(file: file, enabled: file.map { Self.statesRead(lines ?? "", in: $0) } ?? [],
                          hasEnabledFile: saved != nil, masterOn: !fm.fileExists(atPath: offFlag.path),
                          safeModePending: fm.fileExists(atPath: runningFlag.path), otherBuilds: others.sorted())
    }

    /// hle_cheats.c name_hex16: another version's file names start with a hex build ID.
    private static func hexPrefix(_ name: String) -> String? {
        let head = name.prefix(16)
        return head.count == 16 && head.allSatisfy(\.isHexDigit) ? head.uppercased() : nil
    }

    /// hle_cheats.c states_read: each line turns on the entry with that key, else the next entry of that name still
    /// off (an older file's plain name for every duplicate); masters and labels never.
    static func statesRead(_ text: String, in file: CheatFile) -> Set<String> {
        var on = Set<String>()
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(raw)
            let candidates = file.entries.filter { $0.kind != .master && $0.kind != .label && !on.contains($0.name) }
            if let hit = candidates.first(where: { $0.name == line }) ?? candidates.first(where: { $0.rawName == line }) {
                on.insert(hit.name)
            }
        }
        return on
    }

    /// The "compiled from" source a meta file names (meta_source), "" when none.
    static func metaSource(_ meta: String) -> String {
        let prefix = "# cheat_anchor.py: compiled from "
        guard let first = meta.split(separator: "\n", maxSplits: 1).first, first.hasPrefix(prefix),
              let cut = first.range(of: " for build ") else { return "" }
        return String(first[first.index(first.startIndex, offsetBy: prefix.count)..<cut.lowerBound])
    }

    /// newest_other_enabled: a compiled file without its own toggles takes the newest other build's compiled from the
    /// same source.
    private func carriedEnabled(source: String) -> String? {
        guard !source.isEmpty else { return nil }
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        var best: (Date, URL)?
        for name in names where name.count == 24 && name.lowercased().hasSuffix(".enabled")
            && name.prefix(16).uppercased() != buildID {
            let meta = folder.appendingPathComponent("\(name.prefix(16)).meta.tsv")
            guard let text = try? String(contentsOf: meta, encoding: .utf8), Self.metaSource(text) == source else { continue }
            let url = folder.appendingPathComponent(name)
            let date = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
            if best == nil || date >= best!.0 { best = (date, url) }
        }
        return best.flatMap { try? String(contentsOf: $0.1, encoding: .utf8) }
    }

    /// Changes whenever the files state() reads may have changed: the three folders (a rename or a new file changes a
    /// folder's date), this build's own files (the host rewrites `.enabled` in place) and the master switch. For a
    /// cache in front of state().
    public func fingerprint() -> [String] {
        let dirs = [folder,
                    folder.appendingPathComponent("atmosphere/contents/\(titleID)/cheats"),
                    folder.appendingPathComponent("contents/\(titleID)/cheats")]
        let files = dirs.flatMap { [$0, $0.appendingPathComponent("\(buildID).txt"), $0.appendingPathComponent("\(buildID).meta.tsv")] }
            + [enabledURL, offFlag]
        return files.map { url in
            guard let a = try? fm.attributesOfItem(atPath: url.path) else { return "-" }
            let date = (a[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            return "\(date):\((a[.size] as? NSNumber)?.int64Value ?? 0):\((a[.systemFileNumber] as? NSNumber)?.int64Value ?? 0)"
        }
    }

    // MARK: - Writing

    private func allowed() throws { guard canWrite() else { throw CheatStoreError.notAllowed } }

    private func write(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).nxlibrary-\(UUID().uuidString)")
        do {
            try data.write(to: tmp)
            guard rename(tmp.path, url.path) == 0 else {
                throw CheatStoreError.writeFailed(String(cString: strerror(errno)))
            }
        } catch let error as CheatStoreError {
            try? fm.removeItem(at: tmp)
            throw error
        } catch {
            try? fm.removeItem(at: tmp)
            throw CheatStoreError.writeFailed(error.localizedDescription)
        }
    }

    private func enabledText(_ names: Set<String>, file: CheatFile) -> Data {
        Data(file.switches.filter { names.contains($0.name) }.map { $0.name + "\n" }.joined().utf8)
    }

    /// Writes `<build ID>.txt` in the flat folder (normalized: no byte order mark). Replacing keeps on the switches
    /// that were on and keep their key; a new file starts with every cheat off. An old meta / values file of this build
    /// goes to the Trash, so a downloaded file never wears a compiled file's sections.
    public func install(_ data: Data, replacing: Bool) throws {
        try allowed()
        let previous = replacing ? state().enabled : []
        let bytes = CheatFile.normalized(data)
        let file = CheatFile.parse(bytes)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            throw CheatStoreError.writeFailed(error.localizedDescription)
        }
        for stale in ["\(buildID).meta.tsv", "\(buildID).values"].map(folder.appendingPathComponent)
        where fm.fileExists(atPath: stale.path) {
            do { try trash(stale) } catch { throw CheatStoreError.writeFailed(error.localizedDescription) }
        }
        try write(bytes, to: folder.appendingPathComponent("\(buildID).txt"))
        try write(enabledText(previous, file: file), to: enabledURL)
    }

    /// Only this file's switches are written, one key per line in file order (states_save).
    public func setEnabled(_ names: Set<String>) throws {
        try allowed()
        guard let file = state().file else { return }
        try write(enabledText(names, file: file), to: enabledURL)
    }

    public func setMaster(on: Bool) throws {
        try allowed()
        if on {
            guard fm.fileExists(atPath: offFlag.path) else { return }
            do { try fm.removeItem(at: offFlag) } catch { throw CheatStoreError.writeFailed(error.localizedDescription) }
        } else {
            try write(Data(), to: offFlag)
        }
    }

    /// Every switch off; the master switch is left as it is.
    public func turnAllOff() throws {
        try allowed()
        try write(Data(), to: enabledURL)
    }

    /// A build's cheat files (wherever the host would find them), its toggles, meta and values, to the Trash.
    public func remove(build: String) throws {
        try allowed()
        let id = build.uppercased()
        let texts = candidates().filter { CheatInstall.build(inName: $0.lastPathComponent) == id }
        let urls = texts + texts.map(metaURL) + ["\(id).enabled", "\(id).values", "\(id).meta.tsv"].map(folder.appendingPathComponent)
        var seen = Set<String>()
        for url in urls where fm.fileExists(atPath: url.path) && seen.insert(url.standardizedFileURL.path).inserted {
            do { try trash(url) } catch { throw CheatStoreError.writeFailed(error.localizedDescription) }
        }
    }
}
