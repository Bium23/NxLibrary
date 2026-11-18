import Foundation
import Darwin

enum InstallationFileReadError: Error { case tooLarge, unsafeFile, sourceChanged, invalidText }

/// Retain only this small identity after parsing, not all source-file contents.
struct InstallationFileObservation: Equatable, Sendable {
    let url: URL
    private let identity: Identity?
    private let fileType: mode_t

    fileprivate struct Identity: Equatable, Sendable {
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init(_ status: stat) {
            device = status.st_dev
            inode = status.st_ino
            size = status.st_size
            modifiedSeconds = status.st_mtimespec.tv_sec
            modifiedNanoseconds = status.st_mtimespec.tv_nsec
            changedSeconds = status.st_ctimespec.tv_sec
            changedNanoseconds = status.st_ctimespec.tv_nsec
        }
    }

    private init(url: URL, status: stat) {
        self.url = url
        identity = Identity(status)
        fileType = status.st_mode & mode_t(S_IFMT)
    }
    private init(absentURL: URL) { url = absentURL; identity = nil; fileType = 0 }
    var byteCount: Int64 { identity?.size ?? 0 }

    static func capture(fileDescriptor: Int32, url: URL, expectedType: mode_t = mode_t(S_IFREG)) throws -> Self {
        var status = stat()
        guard fstat(fileDescriptor, &status) == 0, status.st_mode & mode_t(S_IFMT) == expectedType else {
            throw InstallationFileReadError.unsafeFile
        }
        return Self(url: url, status: status)
    }

    static func absent(at url: URL) throws -> Self {
        var status = stat()
        if lstat(url.path, &status) == 0 { throw InstallationFileReadError.sourceChanged }
        guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Self(absentURL: url)
    }

    func verifyUnchanged() throws {
        var current = stat()
        let result = lstat(url.path, &current)
        if identity == nil {
            guard result == -1, errno == ENOENT else { throw InstallationFileReadError.sourceChanged }
            return
        }
        guard result == 0, current.st_mode & mode_t(S_IFMT) == fileType, Identity(current) == identity else {
            throw InstallationFileReadError.sourceChanged
        }
    }
}

/// Bounded read from a regular file with no final symlink following.
/// The same identity is checked after the read and again before scan publication.
struct InstallationFileSnapshot {
    let data: Data
    let observation: InstallationFileObservation

    static func read(at url: URL, maximumBytes: Int) throws -> Self {
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw InstallationFileReadError.tooLarge }
        let handle = try openReadOnly(url)
        defer { try? handle.close() }
        let observation = try InstallationFileObservation.capture(fileDescriptor: handle.fileDescriptor, url: url)
        guard observation.byteCount >= 0, observation.byteCount <= Int64(maximumBytes) else { throw InstallationFileReadError.tooLarge }
        let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard bytes.count <= maximumBytes else { throw InstallationFileReadError.tooLarge }
        try observation.verifyUnchanged()
        guard Int64(bytes.count) == observation.byteCount else { throw InstallationFileReadError.sourceChanged }
        return Self(data: bytes, observation: observation)
    }

    static func openReadOnly(_ url: URL) throws -> FileHandle {
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    func verifyUnchanged() throws { try observation.verifyUnchanged() }

    var text: String {
        get throws {
            guard let result = String(data: data, encoding: .utf8) else { throw InstallationFileReadError.invalidText }
            return result
        }
    }
}
