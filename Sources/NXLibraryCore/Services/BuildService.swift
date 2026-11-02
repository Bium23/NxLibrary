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
    private let ioQueue = DispatchQueue(label: "local.nxlibrary.build.io")
    private let stateLock = NSLock()
    private var process: Process?
    private var logHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var cancelled = false
    private var eventHandler: ((BuildEvent) -> Void)?
    private var completion: ((BuildResult) -> Void)?
    private var sleepAssertion: IOPMAssertionID?
    /// Keeps App Nap off the app while it builds: hidden or in the background, a napping app's timers and
    /// pipes slow down, and the build's progress and output handling with them.
    private var buildActivity: NSObjectProtocol?

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
        buildActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "NX Library build")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // set -m makes the wrapper its own process-group leader, so cancel()
        // can signal the compiler and every tool it spawned.
        process.arguments = ["-c", "set -m; exec \"$@\"", "nxbuild",
                             command.executable.path] + command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = command.environment
        process.qualityOfService = .userInitiated
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
        if let buildActivity {
            ProcessInfo.processInfo.endActivity(buildActivity)
            self.buildActivity = nil
        }
    }
}
