import XCTest

/// The bundled runtime carries every Python package the pinned engine asks players to install: its README's
/// `pip install` line and, from engines that have it, `.github/requirements/tools.txt`. A re-pin that adds one
/// (zbic in 0.1.3, found only by a player) fails here until runtime.lock has it or `notBundled` says why not.
final class EngineRuntimeRequirementsTests: XCTestCase {
    /// Packages the README lists that the runtime leaves out on purpose, with the reason.
    static let notBundled: [String: String] = [:]

    func testRuntimeLockHasEveryEnginePackage() throws {
        let explicitEngine = ProcessInfo.processInfo.environment["NX_TEST_ENGINE_REPO"]
        let engine = explicitEngine.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("nxnative")
        guard FileManager.default.fileExists(atPath: engine.appendingPathComponent(".git").path) else {
            if explicitEngine != nil { return XCTFail("NX_TEST_ENGINE_REPO is not an engine checkout") }
            throw XCTSkip("no ~/nxnative checkout")
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let viewModel = try String(contentsOf: root.appendingPathComponent("Sources/NXLibrary/ViewModels/AppViewModel.swift"),
                                   encoding: .utf8)
        guard let match = viewModel.range(of: #"pinnedEngineCommit = "[0-9a-f]{40}""#, options: .regularExpression) else {
            return XCTFail("no pinnedEngineCommit in AppViewModel.swift")
        }
        let pin = ProcessInfo.processInfo.environment["NX_TEST_ENGINE_COMMIT"]
            ?? String(viewModel[match].dropFirst("pinnedEngineCommit = \"".count).dropLast())

        guard let readme = gitShow("\(pin):README.md", in: engine) else { throw XCTSkip("\(pin) is not in the engine checkout") }
        let fromReadme = Self.pipPackages(in: readme)
        XCTAssertFalse(fromReadme.isEmpty, "no `pip install` line in nxnative \(pin.prefix(7)) README.md")
        let required = fromReadme + Self.requirementPackages(in: gitShow("\(pin):.github/requirements/tools.txt", in: engine) ?? "")

        let lock = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("runtime.lock")))
        let wheels = ((lock as? [String: Any])?["wheels"] as? [[String: Any]] ?? [])
            .compactMap { ($0["name"] as? String)?.lowercased() }
        for package in required where Self.notBundled[package] == nil {
            XCTAssertTrue(wheels.contains(package),
                          "nxnative \(pin.prefix(7)) needs \(package): add it to runtime.lock or to notBundled with the reason")
        }
    }

    func testPipLineParsing() {
        let readme = #"""
        Install the tools:
        ```
        python3 -m pip install lz4 "capstone>=5,<6" fonttools nsz zbic "backports.zstd; python_version < '3.14'"
        ```
        """#
        XCTAssertEqual(Self.pipPackages(in: readme), ["lz4", "capstone", "fonttools", "nsz", "zbic"])
    }

    func testRequirementsFileParsing() {
        let file = "# comment\ncapstone==5.0.9\nfonttools==4.68.0\nzbic==1.0.1.post1\n\n"
        XCTAssertEqual(Self.requirementPackages(in: file), ["capstone", "fonttools", "zbic"])
    }

    /// Package names from a requirements file (`name==version` lines, comments skipped).
    static func requirementPackages(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("-") else { return nil }
            let name = trimmed.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
            return name.isEmpty ? nil : name.lowercased()
        }
    }

    /// Package names from every `pip install` line, without version ranges; a requirement whose marker applies only
    /// before Python 3.14 (the runtime's version) is left out.
    static func pipPackages(in text: String) -> [String] {
        var names: [String] = []
        for line in text.split(separator: "\n") {
            guard let range = line.range(of: "pip install ") else { continue }
            let rest = line[range.upperBound...]
            var tokens: [String] = []
            var current = ""
            var quote: Character?
            for char in rest {
                if let open = quote {
                    if char == open { quote = nil } else { current.append(char) }
                } else if char == "\"" || char == "'" {
                    quote = char
                } else if char == " " {
                    if !current.isEmpty { tokens.append(current); current = "" }
                } else {
                    current.append(char)
                }
            }
            if !current.isEmpty { tokens.append(current) }
            for token in tokens where !token.hasPrefix("-") {
                let parts = token.split(separator: ";", maxSplits: 1)
                if parts.count == 2, parts[1].contains("python_version <") { continue }
                let name = parts[0].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
                if !name.isEmpty { names.append(name.lowercased()) }
            }
        }
        return names
    }

    /// The file at that commit, or nil when the commit or the file is not there.
    private func gitShow(_ object: String, in repo: URL) -> String? {
        let p = Process()
        let out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "show", object]
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
