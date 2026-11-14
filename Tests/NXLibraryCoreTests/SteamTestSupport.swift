import Foundation
import XCTest

/// Generated metadata/header bytes only; these fixtures are not game executables.
struct SteamTestFixture: Sendable {
    let root: URL

    static func temporary(in test: XCTestCase) throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SteamSourceTests-" + UUID().uuidString)
            .resolvingSymlinksInPath().standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        test.addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return Self(root: root)
    }

    @discardableResult
    func app(at relative: String = "Game.app", category: String? = "public.app-category.games",
             cpuTypes: [UInt32] = [0x0100000c], metadata: [String: Any] = [:]) throws -> URL {
        let app = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "test.game",
                                   "CFBundleDisplayName": "Fixture game", "CFBundleExecutable": "fixture"]
        info["LSApplicationCategoryType"] = category
        info.merge(metadata) { _, new in new }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/fixture")
        let data = cpuTypes.count == 1 ? Self.machHeader(cpu: cpuTypes[0]) : Self.fatHeader(cpus: cpuTypes)
        try data.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }

    static func words(_ values: [UInt32], bigEndian: Bool = false) -> Data {
        Data(values.flatMap { word in
            let shifts = bigEndian ? [24, 16, 8, 0] : [0, 8, 16, 24]
            return shifts.map { UInt8(truncatingIfNeeded: word >> $0) }
        })
    }

    static func machHeader(cpu: UInt32, fileType: UInt32 = 2) -> Data {
        words([0xfeedfacf, cpu, 0, fileType, 0, 0, 0, 0])
    }

    func library(_ relative: String = "Steam") throws -> URL {
        let library = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("steamapps/common"), withIntermediateDirectories: true)
        return library
    }

    @discardableResult
    func manifest(in library: URL, id: String = "10", name: String = "First game", directory: String = "First",
                  filenameID: String? = nil, size: String = "100", extra: String = "") throws -> URL {
        let file = library.appendingPathComponent("steamapps/appmanifest_\(filenameID ?? id).acf")
        let text = "\"AppState\" { \"appid\" \(Self.quote(id)) \"name\" \(Self.quote(name)) \"installdir\" \(Self.quote(directory)) \"SizeOnDisk\" \(Self.quote(size)) \"buildid\" \"42\" \"StateFlags\" \"4\" \(extra) }"
        try Data(text.utf8).write(to: file)
        return file
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    func inventory() throws -> [String: Data] {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let file as URL in files {
            if (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count))] = try Data(contentsOf: file)
            }
        }
        return result
    }

    static func fatHeader(cpus: [UInt32]) -> Data {
        var data = words([0xcafebabe, UInt32(cpus.count)], bigEndian: true)
        for (i, cpu) in cpus.enumerated() {
            data.append(words([cpu, 0, UInt32(8 + cpus.count * 20 + i * 32), 32, 0], bigEndian: true))
        }
        for cpu in cpus { data.append(machHeader(cpu: cpu)) }
        return data
    }
}
