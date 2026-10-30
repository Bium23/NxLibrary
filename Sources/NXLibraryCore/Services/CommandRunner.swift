import Foundation

public struct CommandResult: Equatable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: URL, _ arguments: [String],
             environment: [String: String]?,
             currentDirectory: URL?) throws -> CommandResult
}

public final class SystemCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: URL, _ arguments: [String],
                    environment: [String: String]?,
                    currentDirectory: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let environment { process.environment = environment }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Runs like `run`, and hands every line of either pipe to `onLine` as it
    /// arrives (on a background queue), for installs that report progress.
    public func stream(_ executable: URL, _ arguments: [String],
                       environment: [String: String]?, currentDirectory: URL?,
                       onLine: @escaping (String) -> Void) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        if let environment { process.environment = environment }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let group = DispatchGroup()
        let lock = NSLock()
        var collected = [Data(), Data()]
        for (slot, pipe) in [out, err].enumerated() {
            var buffer = LineBuffer()
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    buffer.finish().forEach(onLine)
                    group.leave()
                    return
                }
                lock.lock()
                collected[slot].append(chunk)
                lock.unlock()
                buffer.append(chunk).forEach(onLine)
            }
        }
        do {
            try process.run()
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        process.waitUntilExit()
        group.wait()
        return CommandResult(status: process.terminationStatus,
                             stdout: String(decoding: collected[0], as: UTF8.self),
                             stderr: String(decoding: collected[1], as: UTF8.self))
    }
}
