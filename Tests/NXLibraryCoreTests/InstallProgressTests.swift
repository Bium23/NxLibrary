import XCTest
@testable import NXLibraryCore

final class InstallProgressTests: XCTestCase {
    func testGitPhasesMapOntoOneBar() throws {
        let receiving = try XCTUnwrap(InstallProgress.git("Receiving objects:  50% (1350/2700), 12.00 MiB | 4.00 MiB/s"))
        XCTAssertEqual(receiving.fraction ?? -1, 0.475, accuracy: 0.0001)
        XCTAssertEqual(receiving.label, "Receiving objects 50%")

        let counting = try XCTUnwrap(InstallProgress.git("remote: Counting objects: 100% (40/40), done."))
        XCTAssertEqual(counting.fraction ?? -1, 0.05, accuracy: 0.0001)

        let files = try XCTUnwrap(InstallProgress.git("Updating files: 100% (900/900), done."))
        XCTAssertEqual(files.fraction ?? -1, 1, accuracy: 0.0001)

        XCTAssertNil(InstallProgress.git("Cloning into '/Users/x/nxnative'..."))
        XCTAssertNil(InstallProgress.git("HEAD is now at af616f5 engine"))
    }

    func testPercentTakesTheLastOne() {
        XCTAssertEqual(InstallProgress.percent("Downloading Metal Toolchain: 12.5% (88 MB of 704 MB)") ?? -1, 0.125, accuracy: 0.0001)
        XCTAssertEqual(InstallProgress.percent("5% then 40%") ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertNil(InstallProgress.percent("Finding content..."))
        XCTAssertNil(InstallProgress.percent("250% (bogus)"))
    }

    func testByteLabel() {
        XCTAssertEqual(InstallProgress.bytes(done: 52_428_800, total: 209_715_200),
                       InstallProgress(fraction: 0.25, label: "50 of 200 MB"))
        XCTAssertEqual(InstallProgress.bytes(done: 1_048_576, total: -1),
                       InstallProgress(fraction: nil, label: "1 MB"))
    }

    func testLineBufferSplitsOnReturnAndNewline() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("Receiving objects:  1%\rReceiving obj".utf8)), ["Receiving objects:  1%"])
        XCTAssertEqual(buffer.append(Data("ects:  2%\r\ndone\n\n".utf8)), ["Receiving objects:  2%", "done"])
        XCTAssertEqual(buffer.append(Data("tail".utf8)), [])
        XCTAssertEqual(buffer.finish(), ["tail"])
        XCTAssertEqual(buffer.finish(), [])
    }

    func testStreamDeliversBothPipesAndStatus() throws {
        var lines: [String] = []
        let lock = NSLock()
        let result = try SystemCommandRunner().stream(
            URL(fileURLWithPath: "/bin/sh"), ["-c", "printf 'a\\rb\\n'; printf 'err\\n' >&2; printf 'c'; exit 3"],
            environment: nil, currentDirectory: nil) { line in
                lock.lock(); lines.append(line); lock.unlock()
            }
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(Set(lines), ["a", "b", "c", "err"])
        XCTAssertTrue(result.stderr.contains("err"))
        XCTAssertTrue(result.stdout.contains("c"))
    }
}
