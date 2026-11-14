import Foundation
import Darwin

/// Only the commit boundary is replaceable; staging, decoding, locking and
/// source/revision checks remain real in failure and concurrency tests.
struct CatalogPublication {
    let publish: (_ staged: URL, _ destination: URL, _ replacing: Bool, _ validate: () throws -> Void) throws -> Void

    let syncDirectory: (URL) throws -> Void

    init(syncDirectory: @escaping (URL) throws -> Void = Self.synchronize,
         publish: @escaping (URL, URL, Bool, () throws -> Void) throws -> Void) {
        self.syncDirectory = syncDirectory
        self.publish = publish
    }

    private static func synchronize(_ directory: URL) throws {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static let atomic = Self { staged, destination, replacing, validate in
        try validate()
        let result = replacing ? rename(staged.path, destination.path) : link(staged.path, destination.path)
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func stage(_ data: Data, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(".catalog-stage-" + UUID().uuidString)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            guard fsync(fd) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            try handle.close()
            return url
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
