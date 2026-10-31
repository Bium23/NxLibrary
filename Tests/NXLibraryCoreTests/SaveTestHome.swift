import Foundation
@testable import NXLibraryCore

final class SaveTestHome {
    let base: URL
    let home: URL
    let app: URL
    let tid = "0100000000000001"
    var support: URL { home.appendingPathComponent("Library/Application Support/nxnative/\(tid)") }
    var backups: URL { home.appendingPathComponent("Library/Application Support/NXLibrary/SaveBackups") }
    init() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("nx-save-test-\(UUID())")
        home = base.appendingPathComponent("home")
        app = base.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
    func write(_ text: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func location(id: String? = nil, environment: [String: String] = [:], gameCloud: String? = nil,
                  libraryCloud: String? = nil) throws -> SaveLocation {
        try SaveLocation.resolve(titleID: id ?? tid, appURL: app, home: home, environment: environment,
                                 gameCloudFolder: gameCloud, libraryCloudFolder: libraryCloud)
    }
}
