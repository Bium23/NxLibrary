import XCTest
import Darwin
@testable import NXLibraryCore

final class BuildServiceTests: XCTestCase {
    func testFailedInstallationKeepsReadyBuildForRetryWithoutRunningEngineAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXInstallRetry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let final = root.appendingPathComponent("Applications/Game.app")
        let temp = root.appendingPathComponent("Temp/Game.app")
        try FileManager.default.createDirectory(at: final.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: final.appendingPathComponent("Contents/Info.plist"))
        let script = root.appendingPathComponent("engine.sh")
        let runs = root.appendingPathComponent("engine-runs")
        try """
        echo run >> "$2"
        mkdir -p "$1/Contents"
        printf new > "$1/Contents/Info.plist"
        """.write(to: script, atomically: true, encoding: .utf8)
        let denied = DenyInstallDirectory(parent: final.deletingLastPathComponent())
        let service = BuildService(fileManager: denied)
        let finished = expectation(description: "installation failed after compilation")
        var result: BuildResult?
        service.start(command: BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path, temp.path, runs.path], environment: [:], workingDirectory: root),
            logURL: root.appendingPathComponent("build.log"), tempApp: temp, finalApp: final,
            eventHandler: { _ in }, completion: { result = $0; finished.fulfill() })
        wait(for: [finished], timeout: 10)
        let ready = try XCTUnwrap(result)
        XCTAssertFalse(ready.success)
        XCTAssertFalse(ready.cancelled)
        XCTAssertNotNil(ready.error)
        XCTAssertTrue(ready.installationFailed)
        XCTAssertEqual(ready.heldApp, temp)
        XCTAssertNil(ready.outputURL)
        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("Contents/Info.plist")), "old")
        XCTAssertEqual(try String(contentsOf: temp.appendingPathComponent("Contents/Info.plist")), "new")

        var game = PortedGame(name: "Game", url: final, platform: .macApp, sizeBytes: 1, modificationDate: Date())
        game.status = .built
        let pending = PendingInstall(tempApp: try XCTUnwrap(ready.heldApp), finalApp: final,
            record: BuildRecord(startedAt: Date(timeIntervalSince1970: 10), engineCommit: "2716f78"),
            toolchain: ToolchainInfo(engineCommit: "2716f78"))
        PendingInstaller.hold(pending, for: &game)
        XCTAssertThrowsError(try PendingInstaller.install(&game, fileManager: denied))
        XCTAssertEqual(game.pendingInstall, pending)
        let store = LibraryStore(directory: root.appendingPathComponent("catalog"))
        try store.save(LibraryFile(games: [game]))
        game = try XCTUnwrap(store.load().games.first)
        XCTAssertEqual(game.pendingInstall, pending)
        XCTAssertEqual(try PendingInstaller.install(&game), .installed)
        XCTAssertNil(game.pendingInstall)
        XCTAssertEqual(try String(contentsOf: final.appendingPathComponent("Contents/Info.plist")), "new")
        XCTAssertEqual(try String(contentsOf: runs), "run\n", "Retry installs the existing build without starting the engine")
    }

    func testFailedEngineDoesNotKeepItsPartialOutputAsReady() throws {
        try assertUnreadyOutput(script: "mkdir -p \"$1/Contents\"; printf partial > \"$1/Contents/Info.plist\"; exit 1")
    }

    func testInvalidSuccessfulOutputDoesNotBecomeAReadyBuild() throws {
        try assertUnreadyOutput(script: "mkdir -p \"$1\"; exit 0")
    }

    private func assertUnreadyOutput(script: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXUnready-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("engine.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let service = BuildService()
        let finished = expectation(description: "unready build")
        service.start(command: BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [file.path, root.appendingPathComponent("Temp.app").path], environment: [:], workingDirectory: root),
            logURL: root.appendingPathComponent("build.log"), tempApp: root.appendingPathComponent("Temp.app"),
            finalApp: root.appendingPathComponent("Final.app"), eventHandler: { _ in }, completion: { result in
                XCTAssertFalse(result.success)
                XCTAssertFalse(result.installationFailed)
                XCTAssertNil(result.heldApp)
                XCTAssertNil(result.outputURL)
                XCTAssertNotNil(result.error)
                finished.fulfill()
            })
        wait(for: [finished], timeout: 10)
    }

    func testParsesEventsAndInstallsApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXBuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fake.sh")
        let tempApp = root.appendingPathComponent("Temp.app")
        let finalApp = root.appendingPathComponent("Final.app")
        try """
        #!/bin/sh
        echo '{"ev":"stage","k":1,"n":2,"name":"extract"}'
        echo '{"ev":"progress","frac":0.5,"done":1,"total":2,"eta":1}'
        mkdir -p "$1/Contents"
        printf '<plist><dict/></plist>' > "$1/Contents/Info.plist"
        echo '{"ev":"stage_end","name":"extract","ok":true,"elapsed":0.1,"summary":"done"}'
        exit 0
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let command = BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                   arguments: [script.path, tempApp.path],
                                   environment: [:], workingDirectory: root)
        let service = BuildService()
        let exp = expectation(description: "build")
        var events: [BuildEvent] = []
        service.start(command: command,
                      logURL: root.appendingPathComponent("build.log"),
                      tempApp: tempApp, finalApp: finalApp,
                      eventHandler: { events.append($0) },
                      completion: { result in
            XCTAssertTrue(result.success)
            exp.fulfill()
        })
        wait(for: [exp], timeout: 10)
        XCTAssertTrue(events.contains { if case .stage = $0 { return true }; return false })
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalApp.appendingPathComponent("Contents/Info.plist").path))
    }

    /// The game is open while its own build finishes: the new app waits beside the old one.
    func testHeldBuildKeepsTempAppAndLeavesFinalApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXHold-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fake.sh")
        let tempApp = root.appendingPathComponent("Temp/Game.app")
        let finalApp = root.appendingPathComponent("Final.app")
        try FileManager.default.createDirectory(at: finalApp.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        try "old".write(to: finalApp.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        try """
        #!/bin/sh
        mkdir -p "$1/Contents"
        printf 'new' > "$1/Contents/Info.plist"
        exit 0
        """.write(to: script, atomically: true, encoding: .utf8)
        let command = BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                   arguments: [script.path, tempApp.path],
                                   environment: [:], workingDirectory: root)
        let service = BuildService()
        let exp = expectation(description: "held")
        var result: BuildResult?
        service.start(command: command, logURL: root.appendingPathComponent("build.log"),
                      tempApp: tempApp, finalApp: finalApp, holdInstall: { true },
                      eventHandler: { _ in }, completion: { result = $0; exp.fulfill() })
        wait(for: [exp], timeout: 10)
        XCTAssertEqual(result?.success, true)
        XCTAssertEqual(result?.heldApp, tempApp)
        XCTAssertNil(result?.outputURL)
        XCTAssertEqual(try String(contentsOf: finalApp.appendingPathComponent("Contents/Info.plist"), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: tempApp.appendingPathComponent("Contents/Info.plist"), encoding: .utf8), "new")
    }

    func testSaveLeaseHoldsBuildUntilExclusiveInstallationIsPossible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NXSaveHold-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("fake.sh")
        let temp = root.appendingPathComponent("Temp.app")
        let final = root.appendingPathComponent("Final.app")
        try "mkdir -p \"$1/Contents\"\nprintf new > \"$1/Contents/Info.plist\"\n".write(to: script, atomically: true, encoding: .utf8)
        let gate = SaveOperationGate()
        let token = try XCTUnwrap(gate.begin(titleID: "0100000000000001"))
        let done = expectation(description: "held behind saves")
        let service = BuildService()
        service.start(command: BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path, temp.path], environment: [:], workingDirectory: root),
            logURL: root.appendingPathComponent("log"), tempApp: temp, finalApp: final,
            acquireInstall: {
                guard let lease = gate.begin(titleID: "0100000000000001") else { return nil }
                return { gate.end(titleID: "0100000000000001", token: lease) }
            }, eventHandler: { _ in }, completion: { result in
                XCTAssertTrue(result.success)
                XCTAssertEqual(result.heldApp, temp)
                XCTAssertFalse(FileManager.default.fileExists(atPath: final.path))
                done.fulfill()
            })
        wait(for: [done], timeout: 10)
        gate.end(titleID: "0100000000000001", token: token)
    }

    func testCancelKillsChild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXCancel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appendingPathComponent("cancel.sh")
        let pidFile = root.appendingPathComponent("child.pid")
        try """
        #!/bin/sh
        sleep 30 &
        echo $! > "$1"
        wait
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let command = BuildCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                   arguments: [script.path, pidFile.path],
                                   environment: [:], workingDirectory: root)
        let service = BuildService()
        let exp = expectation(description: "cancelled")
        service.start(command: command,
                      logURL: root.appendingPathComponent("cancel.log"),
                      tempApp: root.appendingPathComponent("Temp.app"),
                      finalApp: root.appendingPathComponent("Final.app"),
                      eventHandler: { _ in },
                      completion: { result in
            XCTAssertTrue(result.cancelled)
            exp.fulfill()
        })
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: pidFile.path), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        let pid = Int32(try String(contentsOf: pidFile)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        service.cancel()
        wait(for: [exp], timeout: 10)
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }
}

private final class DenyInstallDirectory: FileManager, @unchecked Sendable {
    let parent: URL
    init(parent: URL) { self.parent = parent.standardizedFileURL; super.init() }
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        if url.standardizedFileURL == parent { throw CocoaError(.fileWriteNoPermission) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}
