import Foundation
import Darwin
import IOKit.pwr_mgt

public struct BuildResult: Equatable {
    public var success: Bool
    public var exitCode: Int32
    public var cancelled: Bool
    public var logURL: URL
    public var outputURL: URL?
    /// A valid compiled app waiting for installation, either while its game is
    /// running or after installation failed. The caller must keep its folder.
    public var heldApp: URL?
    public var error: String?

    public var installationFailed: Bool { !success && !cancelled && heldApp != nil }

    public init(success: Bool, exitCode: Int32, cancelled: Bool,
                logURL: URL, outputURL: URL? = nil, heldApp: URL? = nil, error: String? = nil) {
        self.success = success
        self.exitCode = exitCode
        self.cancelled = cancelled
        self.logURL = logURL
        self.outputURL = outputURL
        self.heldApp = heldApp
        self.error = error
    }
}

public final class BuildService {
    private let fm: FileManager
    private let ioQueue = DispatchQueue(label: L10n.text("local.nxlibrary.build.io"))
    private let stateLock = NSLock()
    private var process: Process?
    private var logHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var cancelled = false
    private var eventHandler: ((BuildEvent) -> Void)?
    private var completion: ((BuildResult) -> Void)?
    private var sleepAssertion: IOPMAssertionID?
    /// How long a stop waits before it kills what is left. Since nxnative 0b124486 every tool the build script
    /// runs leads a session of its own, which a signal to the build's process group does not reach: on SIGTERM
    /// the script stops that session itself, killing what is left of it after 5 s (dm/tools/proc_group.py GRACE),
    /// then exits with 143. Killing the script before then would leave its tools running with no parent.
    private let stopGrace: TimeInterval

    public init(fileManager: FileManager = .default, stopGrace: TimeInterval = 8) {
        self.fm = fileManager
        self.stopGrace = stopGrace
    }

    deinit {
        // A backstop for callers that drop the service without cancelling.
        stateLock.lock()
        let running = process
        stateLock.unlock()
        if let running, running.isRunning {
            Self.kill(tree: running.processIdentifier)
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
        holdInstall: @escaping () -> Bool = { false },
        acquireInstall: @escaping () -> (() -> Void)? = { {} },
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
        stdoutBuffer.removeAll(keepingCapacity: true)
        stderrBuffer.removeAll(keepingCapacity: true)

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
        let outputClosed = DispatchGroup()
        outputClosed.enter()
        outputClosed.enter()
        process.standardOutput = out
        process.standardError = err
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outputClosed.leave()
            } else {
                self?.consume(data, isError: false)
            }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outputClosed.leave()
            } else {
                self?.consume(data, isError: true)
            }
        }
        process.terminationHandler = { [weak self] proc in
            self?.finish(proc: proc, logURL: logURL,
                         tempApp: tempApp, finalApp: finalApp, holdInstall: holdInstall,
                         acquireInstall: acquireInstall, outputClosed: outputClosed)
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
        DispatchQueue.global().asyncAfter(deadline: .now() + stopGrace) {
            if process.isRunning { Self.kill(tree: process.processIdentifier) }
        }
    }

    /// Synchronous stop for app termination: the same SIGTERM as a cancel, so the engine stops its tools, waiting at
    /// most `stopGrace` (a build that stops normally ends in well under a second), then everything still running.
    public func terminateNow() {
        stateLock.lock()
        cancelled = true
        let process = self.process
        stateLock.unlock()
        guard let process, process.isRunning else { return }
        killpg(process.processIdentifier, SIGTERM)
        let deadline = Date().addingTimeInterval(stopGrace)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { Self.kill(tree: process.processIdentifier) }
    }

    /// SIGKILL to the build's process group and to every process descended from its leader, listed before any
    /// is killed: a tool in a session of its own is still the script's child while the script runs.
    static func kill(tree leader: pid_t) {
        var found: [pid_t] = []
        var pending = [leader]
        while let parent = pending.popLast() {
            let count = proc_listchildpids(parent, nil, 0)
            guard count > 0 else { continue }
            var children = [pid_t](repeating: 0, count: Int(count) + 32)
            let listed = proc_listchildpids(parent, &children, Int32(children.count * MemoryLayout<pid_t>.size))
            for child in children.prefix(max(0, Int(listed))) where child > 0 && !found.contains(child) {
                found.append(child)
                pending.append(child)
            }
        }
        killpg(leader, SIGKILL)
        for pid in found { Darwin.kill(pid, SIGKILL) }
    }

    private func consume(_ data: Data, isError: Bool) {
        guard !data.isEmpty else { return }
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.logHandle?.write(data)
            if isError {
                self.stderrBuffer.append(data)
                self.drain(&self.stderrBuffer, asError: true)
            } else {
                self.stdoutBuffer.append(data)
                self.drain(&self.stdoutBuffer, asError: false)
            }
        }
    }

    private func drain(_ buffer: inout Data, asError: Bool, atEOF: Bool = false) {
        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            emit(line, asError: asError)
        }
        if atEOF, !buffer.isEmpty {
            emit(buffer, asError: asError)
            buffer.removeAll(keepingCapacity: true)
        }
    }

    private func emit(_ data: Data, asError: Bool) {
        // Decode complete lines, so a pipe read may safely split any UTF-8 character.
        // Malformed text stays visible; the disk log always keeps the original bytes.
        let line = String(decoding: data, as: UTF8.self)
        if asError { eventHandler?(.log(line)) }
        else if let event = BuildEventParser.parse(line) { eventHandler?(event) }
    }

    /// `holdInstall` is asked once the build succeeds: true keeps the new app at `tempApp` (its game is running and
    /// replacing the app under it can crash it).
    private func finish(proc: Process, logURL: URL, tempApp: URL, finalApp: URL,
                        holdInstall: @escaping () -> Bool, acquireInstall: @escaping () -> (() -> Void)?,
                        outputClosed: DispatchGroup) {
        // The process may exit before the last pipe callback. Finish only after
        // both streams reached EOF and all their queued bytes were consumed.
        outputClosed.notify(queue: ioQueue) { [weak self] in
            guard let self else { return }
            self.drain(&self.stdoutBuffer, asError: false, atEOF: true)
            self.drain(&self.stderrBuffer, asError: true, atEOF: true)
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
            var held: URL?
            var error: String?
            if !wasCancelled && proc.terminationStatus == 0 {
                do {
                    guard self.fm.fileExists(atPath: tempApp.appendingPathComponent("Contents/Info.plist").path) else {
                        throw BuildInstallError.invalidApp(tempApp.path)
                    }
                    let release = holdInstall() ? nil : acquireInstall()
                    defer { release?() }
                    if release == nil {
                        held = tempApp
                    } else {
                        do {
                            try BuildOutputInstaller.install(tempApp: tempApp, finalApp: finalApp,
                                                             fileManager: self.fm, requiresExistingParent: true)
                        } catch {
                            held = tempApp
                            throw error
                        }
                    }
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
                outputURL: success && held == nil ? finalApp : nil, heldApp: held, error: error
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
