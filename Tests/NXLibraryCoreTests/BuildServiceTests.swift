import XCTest
import Darwin
@testable import NXLibraryCore

final class BuildServiceTests: XCTestCase {
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
