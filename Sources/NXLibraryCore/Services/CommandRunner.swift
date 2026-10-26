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
}
