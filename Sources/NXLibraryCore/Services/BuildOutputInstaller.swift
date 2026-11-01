import Foundation
import CryptoKit
import Darwin

public enum BuildInstallError: Error, LocalizedError {
    case invalidApp(String)
    case replaceFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidApp(let p): return "The built app is invalid: \(p)"
        case .replaceFailed(let m): return "Could not replace the app: \(m)"
        }
    }
}

/// Filesystem boundary for failure and cross-volume tests.
internal struct BuildInstallIO {
    var sameVolume: (URL, URL) throws -> Bool = { source, parent in
        var sourceInfo = stat(), parentInfo = stat()
        guard stat(source.path, &sourceInfo) == 0, stat(parent.path, &parentInfo) == 0 else {
            throw BuildInstallError.replaceFailed("Could not inspect the destination volume.")
        }
        return sourceInfo.st_dev == parentInfo.st_dev
    }
    var publish: (URL, URL, Bool) throws -> Void = { source, destination, replacing in
        let flags = replacing ? RENAME_SWAP : RENAME_EXCL
        guard renamex_np(source.path, destination.path, UInt32(flags)) == 0 else {
            throw BuildInstallError.replaceFailed(String(cString: strerror(errno)))
        }
    }
    var afterPublish: () throws -> Void = {}
}

public enum BuildOutputInstaller {
    private static let installLock = NSLock()

    private struct Identity: Codable, Equatable {
        let device: UInt64
        let inode: UInt64
    }
    private struct Receipt: Codable {
        var version = 1
        let sourcePath: String
        let source: Identity
        let previous: Identity?
        let copied: Bool
        var prepared: Identity?
    }

    /// The app's CFBundleShortVersionString, if it has one.
    public static func version(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    public static func install(tempApp: URL, finalApp: URL,
                               fileManager: FileManager = .default) throws {
        try install(tempApp: tempApp, finalApp: finalApp, fileManager: fileManager, io: BuildInstallIO())
    }

    internal static func install(tempApp: URL, finalApp: URL, fileManager: FileManager = .default,
                                 io: BuildInstallIO) throws {
        installLock.lock()
        defer { installLock.unlock() }
        let source = tempApp.standardizedFileURL
        let destination = finalApp.standardizedFileURL
        guard source.path != destination.path,
              !source.path.hasPrefix(destination.path + "/"),
              !destination.path.hasPrefix(source.path + "/") else {
            throw BuildInstallError.invalidApp(tempApp.path)
        }
        let parent = destination.deletingLastPathComponent()
        let key = SHA256.hash(data: Data(destination.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let state = parent.appendingPathComponent(".nxlibrary-install-\(key).json")
        let copy = parent.appendingPathComponent(".nxlibrary-incoming-\(key).app")
        guard source != copy else { throw BuildInstallError.invalidApp(tempApp.path) }
        let saved = try readReceipt(state, fileManager)
        if let saved, saved.sourcePath == source.path {
            let currentSource = identity(source, fileManager)
            let sameAttempt = currentSource == nil || currentSource == saved.source || currentSource == saved.previous
            if sameAttempt {
                if let prepared = saved.prepared, identity(destination, fileManager) == prepared {
                    cleanup(saved, source: source, copy: copy, fileManager: fileManager)
                    return
                }
                guard identity(destination, fileManager) == saved.previous else {
                    throw BuildInstallError.replaceFailed("The destination changed since this installation started.")
                }
                if let prepared = saved.prepared {
                    let incoming = saved.copied ? copy : source
                    if identity(incoming, fileManager) == prepared {
                        try publish(saved, source: source, destination: destination, copy: copy,
                                    fileManager: fileManager, io: io)
                        return
                    }
                }
            }
        }

        try validateApp(source, fileManager)
        guard let sourceID = identity(source, fileManager) else { throw BuildInstallError.invalidApp(tempApp.path) }
        let previous = identity(destination, fileManager)
        if previous != nil, !fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path) {
            throw BuildInstallError.replaceFailed("refusing to replace a non-app item at \(destination.path)")
        }
        guard sourceID != previous else { throw BuildInstallError.invalidApp(tempApp.path) }
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        let copied = try !io.sameVolume(source, parent)
        // Only a recorded cross-volume preparation owns the reserved incoming path.
        if identity(copy, fileManager) != nil {
            guard saved?.copied == true else {
                throw BuildInstallError.replaceFailed("An unrecognized incoming app is already at the destination.")
            }
            try fileManager.removeItem(at: copy)
        }
        var receipt = Receipt(sourcePath: source.path, source: sourceID, previous: previous,
                              copied: copied, prepared: copied ? nil : sourceID)
        // Keep one small receipt per destination, including after success. It
        // survives build-folder cleanup before the library record is saved.
        try writeReceipt(receipt, to: state)
        if copied {
            do {
                try fileManager.copyItem(at: source, to: copy)
                try validateApp(copy, fileManager)
                guard let prepared = identity(copy, fileManager) else { throw BuildInstallError.invalidApp(copy.path) }
                receipt.prepared = prepared
                try writeReceipt(receipt, to: state)
            } catch {
                try? fileManager.removeItem(at: copy)
                throw error
            }
        }
        try publish(receipt, source: source, destination: destination, copy: copy,
                    fileManager: fileManager, io: io)
    }

    private static func publish(_ receipt: Receipt, source: URL, destination: URL, copy: URL,
                                fileManager: FileManager, io: BuildInstallIO) throws {
        let incoming = receipt.copied ? copy : source
        guard let prepared = receipt.prepared, identity(incoming, fileManager) == prepared,
              identity(destination, fileManager) == receipt.previous else {
            throw BuildInstallError.replaceFailed("The app changed since this installation started.")
        }
        try io.publish(incoming, destination, receipt.previous != nil)
        try io.afterPublish()
        cleanup(receipt, source: source, copy: copy, fileManager: fileManager)
    }

    private static func cleanup(_ receipt: Receipt, source: URL, copy: URL, fileManager: FileManager) {
        let old = receipt.copied ? copy : source
        if let previous = receipt.previous, identity(old, fileManager) == previous {
            try? fileManager.removeItem(at: old)
        }
        if receipt.copied, identity(source, fileManager) == receipt.source {
            try? fileManager.removeItem(at: source)
        }
    }

    private static func identity(_ url: URL, _ fileManager: FileManager) -> Identity? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return Identity(device: device.uint64Value, inode: inode.uint64Value)
    }

    private static func validateApp(_ url: URL, _ fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.appendingPathComponent("Contents/Info.plist").path) else {
            throw BuildInstallError.invalidApp(url.path)
        }
    }

    private static func readReceipt(_ url: URL, _ fileManager: FileManager) throws -> Receipt? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let size = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
              size.intValue <= 64 * 1024,
              let data = try? Data(contentsOf: url),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data), receipt.version == 1 else {
            throw BuildInstallError.replaceFailed("The previous installation state could not be read.")
        }
        return receipt
    }

    private static func writeReceipt(_ receipt: Receipt, to url: URL) throws {
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        let file = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard file >= 0 else { throw BuildInstallError.replaceFailed("Could not persist the installation state.") }
        defer { close(file) }
        guard fsync(file) == 0 else { throw BuildInstallError.replaceFailed("Could not persist the installation state.") }
    }
}
