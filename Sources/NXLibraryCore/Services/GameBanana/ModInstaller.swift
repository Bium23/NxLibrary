import Foundation
import CryptoKit

public enum ModInstallError: Error, Equatable {
    case notAllowed, download, damaged, unreadable, unsafe, noRomFS, noSpace
    case writeFailed(String)

    public var message: String {
        switch self {
        case .notAllowed: return "Quit the game to install mods."
        case .download: return "The download didn't finish."
        case .damaged: return "The download was damaged. Try again."
        case .unreadable: return "This archive can't be opened."
        case .unsafe: return "This archive has files outside its folder, so it wasn't installed."
        case .noRomFS: return "This file has no romfs folder, so it can't work."
        case .noSpace: return "There isn't enough space to install this mod."
        case .writeFailed(let reason): return "The mod could not be installed: \(reason)"
        }
    }
}

public enum ModInstallResult: Equatable {
    /// Installed and on.
    case on(String)
    /// An update of a mod the player had turned off: it stays off.
    case off(String)
    /// Installed, but the overlay line is full, so it stays off.
    case installedOff(String)

    public var folderName: String {
        switch self { case .on(let name), .off(let name), .installedOff(let name): return name }
    }

    /// The sentence to show, if any.
    public var message: String? {
        if case .installedOff = self { return "Installed, but too many mods are on. Turn one off first." }
        return nil
    }
}

/// Installs a downloaded GameBanana file into the game's mods folder: verify size and MD5, list the archive with the
/// system `bsdtar`, refuse absolute or `..` paths, find the single RomFS root, unpack into a hidden staging folder
/// inside the mods folder, refuse symlinks, then hand the RomFS tree to `ModStore.adopt`. The staging folder is
/// removed whatever happens; the downloaded archive belongs to the caller.
public struct ModInstaller {
    public let store: ModStore
    private let runner: CommandRunning
    private let bsdtar: URL
    private let freeSpace: (URL) -> Int64?
    private let now: () -> Date

    public init(store: ModStore, runner: CommandRunning = SystemCommandRunner(),
                bsdtar: URL = URL(fileURLWithPath: "/usr/bin/bsdtar"),
                freeSpace: @escaping (URL) -> Int64? = ModInstaller.availableCapacity,
                now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.runner = runner
        self.bsdtar = bsdtar
        self.freeSpace = freeSpace
        self.now = now
    }

    /// Free space on the volume of `url` (or its nearest existing parent), for important use.
    public static func availableCapacity(_ url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// Size first, then the MD5 GameBanana publishes (any case).
    public static func verify(_ archive: URL, file: GameBananaFile) throws {
        let size = (try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        guard size == file.size else { throw ModInstallError.damaged }
        guard let handle = try? FileHandle(forReadingFrom: archive) else { throw ModInstallError.damaged }
        defer { try? handle.close() }
        var md5 = Insecure.MD5()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { md5.update(data: chunk) }
        let digest = md5.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == file.md5.lowercased() else { throw ModInstallError.damaged }
    }

    public func install(archive: URL, file: GameBananaFile, mod: AvailableMod) throws -> ModInstallResult {
        guard store.isWritable else { throw ModInstallError.notAllowed }
        try Self.verify(archive, file: file)
        if let free = freeSpace(store.modsFolder), free < 3 * file.size { throw ModInstallError.noSpace }

        let listing = try tar(["-tf", archive.path])
        let paths = listing.split(separator: "\n").map { line in
            line.split(separator: "/", omittingEmptySubsequences: true).filter { $0 != "." }.joined(separator: "/")
        }.filter { !$0.isEmpty }
        let raw = listing.split(separator: "\n").map(String.init)
        guard !raw.contains(where: { $0.hasPrefix("/") }),
              !paths.contains(where: { $0.split(separator: "/").contains("..") }) else { throw ModInstallError.unsafe }
        guard let root = ModSupport.romfsRoot(in: paths, titleID: store.titleID) else { throw ModInstallError.noRomFS }

        let fm = FileManager.default
        let staging = store.modsFolder.appendingPathComponent(".installing-\(UUID().uuidString)")
        do { try fm.createDirectory(at: staging, withIntermediateDirectories: true) }
        catch { throw ModInstallError.writeFailed(error.localizedDescription) }
        defer { try? fm.removeItem(at: staging) }

        _ = try tar(["-xf", archive.path, "-C", staging.path])
        if Self.containsSymlink(staging) { throw ModInstallError.unsafe }
        let tree = staging.appendingPathComponent(root)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: tree.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ModInstallError.noRomFS
        }

        let isUpdate = store.gameBananaRecords()[mod.id] != nil
        let existing = Set(ModFolderScanner.entries(in: store.modsFolder).map(\.lastPathComponent))
        let name = ModFolderName.make(from: mod.name, modID: mod.id, existing: existing)
        let record = ModRecord(folderName: name, isOn: false, gameBananaModID: mod.id, gameBananaFileID: file.id,
                               md5: file.md5.lowercased(), installedAt: now())
        let on: Bool
        do {
            on = try store.adopt(staged: tree, folderName: name, record: record, turnOn: true)
        } catch ModStoreError.notAllowed {
            throw ModInstallError.notAllowed
        } catch let ModStoreError.writeFailed(reason) {
            throw ModInstallError.writeFailed(reason)
        } catch {
            throw ModInstallError.writeFailed(error.localizedDescription)
        }
        let folder = store.gameBananaRecords()[mod.id]?.folderName ?? name
        if on { return .on(folder) }
        return isUpdate ? .off(folder) : .installedOff(folder)
    }

    private func tar(_ arguments: [String]) throws -> String {
        let result: CommandResult
        do { result = try runner.run(bsdtar, arguments, environment: nil, currentDirectory: nil) }
        catch { throw ModInstallError.unreadable }
        guard result.status == 0 else { throw ModInstallError.unreadable }
        return result.stdout
    }

    private static func containsSymlink(_ folder: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            return true
        }
        for case let url as URL in walker where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            return true
        }
        return false
    }
}
