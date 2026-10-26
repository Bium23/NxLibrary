import Foundation
import Darwin
import IOKit.pwr_mgt

public struct BuildResult: Equatable {
    public var success: Bool
    public var exitCode: Int32
    public var cancelled: Bool
    public var logURL: URL
    public var outputURL: URL?
    public var error: String?

    public init(success: Bool, exitCode: Int32, cancelled: Bool,
                logURL: URL, outputURL: URL? = nil, error: String? = nil) {
        self.success = success
        self.exitCode = exitCode
        self.cancelled = cancelled
        self.logURL = logURL
        self.outputURL = outputURL
        self.error = error
    }
}

public final class BuildService {
    private let fm: FileManager
    private let ioQueue = DispatchQueue(label: "local.nxlibrary.build.io")
    private let stateLock = NSLock()
    private var process: Process?
    private var logHandle: FileHandle?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var cancelled = false
    private var eventHandler: ((BuildEvent) -> Void)?
    private var completion: ((BuildResult) -> Void)?
    private var sleepAssertion: IOPMAssertionID?

    public init(fileManager: FileManager = .default) { self.fm = fileManager }

    deinit {
        // A backstop for callers that drop the service without cancelling.
        stateLock.lock()
        let running = process
        stateLock.unlock()
        if let running, running.isRunning {
            killpg(running.processIdentifier, SIGKILL)
        }
    }

    public var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return process?.isRunning == true
    }

    public func start(
        command: BuildCommand,
        logURL: URL,
        tempApp: URL,
        finalApp: URL,
        eventHandler: @escaping (BuildEvent) -> Void,
        completion: @escaping (BuildResult) -> Void
    ) {
        stateLock.lock()
        let alreadyRunning = process?.isRunning == true
        if !alreadyRunning {
            cancelled = false
            self.eventHandler = eventHandler
            self.completion = completion
        }
        stateLock.unlock()
        guard !alreadyRunning else { return }

        try? fm.createDirectory(at: logURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        fm.createFile(atPath: logURL.path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: logURL)

        var assertion = IOPMAssertionID(0)
        if IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NX Library build" as CFString,
            &assertion
        ) == kIOReturnSuccess {
            sleepAssertion = assertion
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // set -m makes the wrapper its own process-group leader, so cancel()
        // can signal the compiler and every tool it spawned.
        process.arguments = ["-c", "set -m; exec \"$@\"", "nxbuild",
                             command.executable.path] + command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = command.environment
        self.process = process

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isError: false)
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData, isError: true)
        }
        process.terminationHandler = { [weak self] proc in
            self?.finish(proc: proc, logURL: logURL,
                         tempApp: tempApp, finalApp: finalApp)
        }

        do {
            try process.run()
        } catch {
            releaseAssertion()
            stateLock.lock()
            let done = self.completion
            self.process = nil
            self.completion = nil
            self.eventHandler = nil
            stateLock.unlock()
            done?(BuildResult(success: false, exitCode: -1, cancelled: false,
                              logURL: logURL, outputURL: nil,
                              error: error.localizedDescription))
        }
    }

    public func cancel() {
        stateLock.lock()
        cancelled = true
        let process = self.process
        stateLock.unlock()
        guard let process, process.isRunning else { return }
        killpg(process.processIdentifier, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process.isRunning { killpg(process.processIdentifier, SIGKILL) }
        }
    }

    /// Synchronous backstop for app termination. The normal cancel path gives
    /// the toolchain a grace period; shutting down cannot wait for it.
    public func terminateNow() {
        stateLock.lock()
        cancelled = true
        let process = self.process
        stateLock.unlock()
        guard let process, process.isRunning else { return }
        killpg(process.processIdentifier, SIGKILL)
    }

    private func consume(_ data: Data, isError: Bool) {
        guard !data.isEmpty else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.logHandle?.write(data)
            guard let text = String(data: data, encoding: .utf8) else { return }
            if isError {
                self.stderrBuffer += text
                self.drain(&self.stderrBuffer, asError: true)
            } else {
                self.stdoutBuffer += text
                self.drain(&self.stdoutBuffer, asError: false)
            }
        }
    }

    private func drain(_ buffer: inout String, asError: Bool) {
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            if asError {
                eventHandler?(.log(line))
            } else if let event = BuildEventParser.parse(line) {
                eventHandler?(event)
            }
        }
    }

    private func finish(proc: Process, logURL: URL, tempApp: URL, finalApp: URL) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.drain(&self.stdoutBuffer, asError: false)
            self.drain(&self.stderrBuffer, asError: true)
            self.logHandle?.closeFile()
            self.logHandle = nil
            self.releaseAssertion()

            self.stateLock.lock()
            let wasCancelled = self.cancelled
            let done = self.completion
            self.completion = nil
            self.eventHandler = nil
            self.process = nil
            self.stateLock.unlock()

            var success = false
            var error: String?
            if !wasCancelled && proc.terminationStatus == 0 {
                do {
                    try BuildOutputInstaller.install(tempApp: tempApp, finalApp: finalApp)
                    success = true
                } catch let failure {
                    error = failure.localizedDescription
                }
            } else if !wasCancelled {
                error = "Build exited with status \(proc.terminationStatus)"
            }
            let result = BuildResult(
                success: success, exitCode: proc.terminationStatus,
                cancelled: wasCancelled, logURL: logURL,
                outputURL: success ? finalApp : nil, error: error
            )
            done?(result)
        }
    }

    private func releaseAssertion() {
        if let sleepAssertion {
            IOPMAssertionRelease(sleepAssertion)
            self.sleepAssertion = nil
        }
    }
}
