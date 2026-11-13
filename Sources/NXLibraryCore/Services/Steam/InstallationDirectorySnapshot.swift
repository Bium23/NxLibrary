import Foundation
import Darwin

typealias InstallationDirectoryReader = @Sendable (URL, Int, () -> Bool) throws -> InstallationDirectorySnapshot

/// One directory-read boundary shared by library inventory and app discovery.
struct InstallationDirectorySnapshot: Sendable {
    let entries: [URL]
    let isComplete: Bool
    let observation: InstallationFileObservation

    static func read(at url: URL, maximumEntries: Int, cancelled: () -> Bool) throws -> Self {
        if cancelled() { throw CancellationError() }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | O_DIRECTORY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard let directory = fdopendir(fd) else {
            let failure = errno
            Darwin.close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        defer { closedir(directory) }
        let observation = try InstallationFileObservation.capture(fileDescriptor: fd, url: url, expectedType: mode_t(S_IFDIR))
        let budget = min(max(0, maximumEntries), 10_000)
        var entries: [URL] = []
        var examined = 0
        var complete = true
        while true {
            if cancelled() { throw CancellationError() }
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                break
            }
            let count = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: count) {
                    String(bytes: UnsafeBufferPointer(start: $0, count: count), encoding: .utf8)
                }
            }
            guard let name, !name.isEmpty else { throw InstallationFileReadError.invalidText }
            if name == "." || name == ".." { continue }
            guard examined < budget else { complete = false; break }
            examined += 1
            if name.hasPrefix(".") { continue }
            entries.append(url.appendingPathComponent(name))
        }
        try observation.verifyUnchanged()
        return Self(entries: entries, isComplete: complete, observation: observation)
    }
}
