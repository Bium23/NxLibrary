import Foundation
import CryptoKit
import Darwin

/// Replaceable filesystem boundary: production copies all metadata; failures leave originals intact.
internal struct SaveFileIO {
    var afterMutation: (String) throws -> Void = { _ in }
    var copy: (URL, URL) throws -> Void = { from, to in
        // On APFS a directory clone preserves the original metadata, including quarantine attribution.
        if clonefile(from.path, to.path, UInt32(CLONE_NOFOLLOW | CLONE_ACL)) == 0 { return }
        guard errno == EXDEV || errno == ENOTSUP || errno == ENOSYS else {
            throw SaveFailure.io("Could not copy the save: \(String(cString: strerror(errno))).")
        }
        guard copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL | COPYFILE_NOFOLLOW)) == 0 else {
            throw SaveFailure.io("Could not copy the save: \(String(cString: strerror(errno))).")
        }
    }
}

extension SaveFiles {
    static func readRegular(_ url: URL, limit: Int) throws -> Data {
        try safePath(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw SaveFailure.io("Could not read save metadata.") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= limit else { throw SaveFailure.invalidSnapshot }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw SaveFailure.invalidSnapshot }
        return data
    }
    static func checkSpace(at directory: URL, bytes: Int64) throws {
        guard bytes >= 0 else { throw SaveFailure.invalidSnapshot }
        var existing = directory
        while !exists(existing), existing.path != "/" { existing.deleteLastPathComponent() }
        if let capacity = try? existing.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           capacity < bytes { throw SaveFailure.io("There is not enough free space for this save operation.") }
    }
    // Compare the portable metadata. macOS can assign provenance and rewrite the
    // quarantine agent name on copy. Keep flags, timestamp and event ID exact.
    // This transforms inventory records only; the system copies the xattrs on disk.
    static func portableAttributes(_ values: [String: Data]) -> [String: Data] {
        var portable = values
        portable.removeValue(forKey: "com.apple.provenance")
        let key = "com.apple.quarantine"
        if let value = portable[key], let record = String(data: value, encoding: .utf8) {
            var fields = record.components(separatedBy: ";")
            if fields.count == 4, fields[0].count == 4, UInt16(fields[0], radix: 16) != nil,
               UInt64(fields[1], radix: 16) != nil {
                fields[2] = ""
                portable[key] = Data(fields.joined(separator: ";").utf8)
            }
        }
        return portable
    }
    static func attributes(_ url: URL) throws -> [String: Data] {
        let size = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { throw SaveFailure.io("Could not read save metadata.") }
        if size == 0 { return [:] }
        var names = [CChar](repeating: 0, count: size)
        guard listxattr(url.path, &names, size, XATTR_NOFOLLOW) == size else { throw SaveFailure.changed }
        var result: [String: Data] = [:]
        for nameBytes in names.split(separator: 0) {
            let name = String(decoding: nameBytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let count = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            guard count >= 0 else { throw SaveFailure.changed }
            var data = Data(count: count)
            let read = data.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
            guard read == count else { throw SaveFailure.changed }
            result[name] = data
        }
        return portableAttributes(result)
    }
    static func inventory(_ directory: URL, slot: SaveSlot) throws -> [SaveInventoryEntry] {
        try safePath(directory)
        guard exists(directory) else { return [] }
        var entries: [SaveInventoryEntry] = []
        func visit(_ url: URL, relative: String) throws {
            try safePath(url)
            var st = stat()
            guard lstat(url.path, &st) == 0 else { throw SaveFailure.changed }
            let kind = st.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG else { throw SaveFailure.unsafePath }
            guard relative.isEmpty || validRelative(relative) else { throw SaveFailure.unsafePath }
            var digest = ""
            if kind == S_IFREG {
                let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
                guard fd >= 0 else { throw SaveFailure.io("Could not read a save file.") }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                var hash = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
                digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            }
            entries.append(SaveInventoryEntry(slot: slot, path: relative, isDirectory: kind == S_IFDIR,
                byteCount: kind == S_IFREG ? Int64(st.st_size) : 0, sha256: digest, attributes: try attributes(url)))
            if kind == S_IFDIR {
                for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative: relative.isEmpty ? child.lastPathComponent : relative + "/" + child.lastPathComponent)
                }
            }
        }
        try visit(directory, relative: "")
        guard entries.first?.isDirectory == true else { throw SaveFailure.unsafePath }
        return entries
    }
    static func inventory(_ location: SaveLocation) throws -> [SaveInventoryEntry] {
        try location.validate()
        return try SaveSlot.allCases.flatMap { try inventory(location.directory($0), slot: $0) }
    }
    static func validRelative(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func makeDirectory(_ url: URL) throws {
        try safePath(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try safePath(url)
    }
    static func durableWrite<T: Encodable>(_ value: T, to url: URL) throws {
        try safePath(url)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw SaveFailure.io("Could not persist save recovery state.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw SaveFailure.io("Could not persist save recovery state.") }
        try syncDirectory(url.deletingLastPathComponent())
    }
    static func syncDirectory(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw SaveFailure.unsafePath }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw SaveFailure.io("Could not persist the save directory.") }
    }
    static func remove(_ url: URL) throws {
        try safePath(url)
        if exists(url) { try FileManager.default.removeItem(at: url) }
    }
}

extension SaveInventoryEntry {
    /// Also normalize inventories recorded in earlier manifests and recovery journals.
    var portable: SaveInventoryEntry {
        var entry = self
        entry.attributes = SaveFiles.portableAttributes(attributes)
        return entry
    }
}
