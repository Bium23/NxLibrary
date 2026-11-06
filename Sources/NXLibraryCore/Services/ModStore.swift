import Foundation

/// What NX Library remembers about one mod of a game, in the game's records file (list order = overlay order).
public struct ModRecord: Codable, Equatable, Sendable {
    public var folderName: String
    public var isOn: Bool
    public var gameBananaModID: Int?
    public var gameBananaFileID: Int?
    public var md5: String?
    public var installedAt: Date?

    public init(folderName: String, isOn: Bool, gameBananaModID: Int? = nil, gameBananaFileID: Int? = nil,
                md5: String? = nil, installedAt: Date? = nil) {
        self.folderName = folderName
        self.isOn = isOn
        self.gameBananaModID = gameBananaModID
        self.gameBananaFileID = gameBananaFileID
        self.md5 = md5
        self.installedAt = installedAt
    }
}

/// Two mods that are on and change at least one same file; `upper` comes first in the overlay and wins.
public struct ModConflict: Equatable, Sendable {
    public let upper: String
    public let lower: String

    public init(upper: String, lower: String) {
        self.upper = upper
        self.lower = lower
    }

    public var message: String { "\(upper) and \(lower) change the same files: the upper one wins." }
}

public enum ModStoreError: Error, Equatable {
    /// The game is running: its launcher read the overlay at start and the mods stay as they are until it quits.
    case notAllowed
    /// The folder holds no RomFS tree.
    case notAMod(String)
    /// `:` separates `DM_ROMFS_OVERLAY`'s folders, so a folder name with one cannot be on.
    case colonInName(String)
    /// The active mods' paths would not fit the launcher's line (`overlayLimit`).
    case overlayTooLong
    case writeFailed(String)
}

/// One game's RomFS mods: the folders in `<support>/mods`, NX Library's record of their order and on/off state,
/// and the `DM_ROMFS_OVERLAY` line of `<support>/env.txt` that makes the engine read the mods that are on, top first
/// (dm/host/hle_fs.c). The folder is the truth for what exists; the record only orders it. Every change happens only
/// while `canWrite` says the game is not running, and a removed mod goes to the Trash.
public struct ModStore {
    /// The Mac launcher reads `env.txt` lines into a 4096-byte buffer: `DM_ROMFS_OVERLAY=` (17) + value + newline
    /// must fit in 4095 (dm/mac/launcher.c `env_file`); the host keeps the value in `overlay[4096]`.
    public static let overlayLimit = 4077
    public static let overlayKey = "DM_ROMFS_OVERLAY"

    public let supportFolder: URL
    public let recordsFile: URL
    public let titleID: String
    private let canWrite: () -> Bool
    private let trash: (URL) throws -> Void

    public init(supportFolder: URL, recordsFile: URL, titleID: String,
                canWrite: @escaping () -> Bool, trash: @escaping (URL) throws -> Void) {
        self.supportFolder = supportFolder
        self.recordsFile = recordsFile
        self.titleID = titleID.uppercased()
        self.canWrite = canWrite
        self.trash = trash
    }

    /// The Mods row's value: "None" without mods, "Off" when none is on, otherwise "<n> on".
    public static func rowValue(on: Int, total: Int) -> String {
        total == 0 ? "None" : on == 0 ? "Off" : "\(on) on"
    }

    public var modsFolder: URL { supportFolder.appendingPathComponent("mods") }
    public var envFile: URL { supportFolder.appendingPathComponent("env.txt") }

    // MARK: - Reading

    /// Recorded mods in their order (only those whose folder exists), then folders without a record, off, by name.
    public func mods() -> [LocalMod] {
        let names = ModFolderScanner.entries(in: modsFolder).map(\.lastPathComponent)
        let present = Set(names)
        let recorded = loadRecords().filter { present.contains($0.folderName) }
        let known = Set(recorded.map(\.folderName))
        return recorded.map { mod($0.folderName, on: $0.isOn) }
            + names.filter { !known.contains($0) }.map { mod($0, on: false) }
    }

    /// The overlay value for the mods that are on, top first; nil when none is.
    public func overlayValue() -> String? { overlay(for: mods()) }

    /// The records of mods installed from GameBanana whose folder still exists, by GameBanana mod id.
    public func gameBananaRecords() -> [Int: ModRecord] {
        let present = Set(ModFolderScanner.entries(in: modsFolder).map(\.lastPathComponent))
        var found: [Int: ModRecord] = [:]
        for record in loadRecords() where present.contains(record.folderName) {
            if let id = record.gameBananaModID, found[id] == nil { found[id] = record }
        }
        return found
    }

    /// Pairs of mods that are on and share a file, in list order.
    public func conflicts() -> [ModConflict] {
        let on = mods().filter { $0.isOn }.compactMap { mod in mod.romfs.map { (mod.folderName, ModFolderScanner.files(under: $0)) } }
        var found: [ModConflict] = []
        for i in on.indices {
            for j in on.indices where j > i && !on[i].1.isDisjoint(with: on[j].1) {
                found.append(ModConflict(upper: on[i].0, lower: on[j].0))
            }
        }
        return found
    }

    /// Removes what an install interrupted by a quit or crash left in the mods folder: the hidden `.installing-<UUID>`
    /// staging folders and `.installing-<UUID>.download` archives. Mods and other files stay; nothing happens while
    /// the game runs.
    public func removeLeftoverInstalls() {
        guard canWrite() else { return }
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: modsFolder.path)) ?? [] where name.hasPrefix(".installing-") {
            try? fm.removeItem(at: modsFolder.appendingPathComponent(name))
        }
    }

    // MARK: - Changing

    public func setOn(_ on: Bool, folderName: String) throws {
        try change { list in
            guard let index = list.firstIndex(where: { $0.folderName == folderName }) else { return }
            if on {
                guard list[index].romfs != nil else { throw ModStoreError.notAMod(folderName) }
                guard !folderName.contains(":") else { throw ModStoreError.colonInName(folderName) }
            }
            list[index].isOn = on
        }
    }

    /// Moves a mod up (negative) or down (positive) in the list; the ends hold it.
    public func move(folderName: String, by offset: Int) throws {
        try change { list in
            guard let index = list.firstIndex(where: { $0.folderName == folderName }) else { return }
            let target = min(max(index + offset, 0), list.count - 1)
            guard target != index else { return }
            list.insert(list.remove(at: index), at: target)
        }
    }

    /// Whether changes are allowed now (the game is not running).
    public var isWritable: Bool { canWrite() }

    /// Takes a mod installed from GameBanana: moves the `staged` RomFS tree to `mods/<folderName>/romfs` and records
    /// it. An update (a record with the same GameBanana mod id) moves the old folder to the Trash and keeps its folder
    /// name, place in the list and on/off state. A new mod goes to the bottom, on when `turnOn` and the overlay still
    /// fits the launcher's line. Returns whether the mod is on.
    @discardableResult
    public func adopt(staged romfs: URL, folderName: String, record: ModRecord, turnOn: Bool) throws -> Bool {
        guard canWrite() else { throw ModStoreError.notAllowed }
        let fm = FileManager.default
        let previous = record.gameBananaModID.flatMap { gameBananaRecords()[$0] }
        let name = previous?.folderName ?? folderName
        let folder = modsFolder.appendingPathComponent(name)
        do {
            if previous != nil, fm.fileExists(atPath: folder.path) { try trash(folder) }
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.moveItem(at: romfs, to: folder.appendingPathComponent("romfs"))
        } catch {
            throw ModStoreError.writeFailed(error.localizedDescription)
        }
        var list = mods()
        if previous == nil, turnOn, let index = list.firstIndex(where: { $0.folderName == name }),
           list[index].romfs != nil, !name.contains(":") {
            list[index].isOn = true
            if let value = overlay(for: list), value.utf8.count > Self.overlayLimit { list[index].isOn = false }
        }
        var adopted = record
        adopted.folderName = name
        try save(list, replacing: adopted)
        return list.first { $0.folderName == name }?.isOn ?? false
    }

    /// Moves the mod's folder to the Trash and forgets it.
    public func remove(folderName: String) throws {
        guard canWrite() else { throw ModStoreError.notAllowed }
        let folder = modsFolder.appendingPathComponent(folderName)
        if FileManager.default.fileExists(atPath: folder.path) {
            do { try trash(folder) } catch { throw ModStoreError.writeFailed(error.localizedDescription) }
        }
        try save(mods())
    }

    /// Drops records whose folder is gone and brings the overlay line in line with the list. Does nothing while the
    /// game runs, or before NX Library has managed this game's mods (no records yet: a hand-written overlay stays). A
    /// list whose overlay no longer fits the launcher's line leaves `env.txt` as it is and throws `overlayTooLong`.
    public func sync() throws {
        guard canWrite(), FileManager.default.fileExists(atPath: recordsFile.path) else { return }
        let list = mods()
        let value = overlay(for: list)
        if let value, value.utf8.count > Self.overlayLimit { throw ModStoreError.overlayTooLong }
        let stored = loadRecords()
        let recorded = Set(stored.map(\.folderName))
        let kept = list.filter { recorded.contains($0.folderName) }.map(\.folderName)
        if kept != stored.map(\.folderName) {
            try write(records: stored.filter { kept.contains($0.folderName) })
        }
        try writeOverlay(value)
    }

    // MARK: - Internals

    private func change(_ edit: (inout [LocalMod]) throws -> Void) throws {
        guard canWrite() else { throw ModStoreError.notAllowed }
        var list = mods()
        try edit(&list)
        if let value = overlay(for: list), value.utf8.count > Self.overlayLimit { throw ModStoreError.overlayTooLong }
        try save(list)
    }

    /// Records the whole list (hand-installed folders get a record where they stand) and writes the overlay.
    private func save(_ list: [LocalMod], replacing: ModRecord? = nil) throws {
        var previous = Dictionary(loadRecords().map { ($0.folderName, $0) }, uniquingKeysWith: { first, _ in first })
        if let replacing { previous[replacing.folderName] = replacing }
        let records = list.map { mod -> ModRecord in
            var record = previous[mod.folderName] ?? ModRecord(folderName: mod.folderName, isOn: false)
            record.isOn = mod.isOn
            return record
        }
        try write(records: records)
        try writeOverlay(overlay(for: list))
    }

    private func mod(_ name: String, on: Bool) -> LocalMod {
        let folder = modsFolder.appendingPathComponent(name)
        let romfs = ModFolderScanner.romfs(in: folder, titleID: titleID)
        return LocalMod(folderName: name, folder: folder, romfs: romfs, isOn: on && romfs != nil && !name.contains(":"))
    }

    private func overlay(for list: [LocalMod]) -> String? {
        let paths = list.filter { $0.isOn }.compactMap { $0.romfs?.path }
        return paths.isEmpty ? nil : paths.joined(separator: ":")
    }

    private func writeOverlay(_ value: String?) throws {
        do { try EnvFileEditor.set(Self.overlayKey, to: value, in: envFile) }
        catch { throw ModStoreError.writeFailed(error.localizedDescription) }
    }

    private func loadRecords() -> [ModRecord] {
        guard let data = try? Data(contentsOf: recordsFile) else { return [] }
        return (try? JSONDecoder().decode([ModRecord].self, from: data)) ?? []
    }

    private func write(records: [ModRecord]) throws {
        do {
            try FileManager.default.createDirectory(at: recordsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(records).write(to: recordsFile, options: .atomic)
        } catch {
            throw ModStoreError.writeFailed(error.localizedDescription)
        }
    }
}
