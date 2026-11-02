import Foundation

/// Shared by build review, disk checks and installation. Resolving a path never moves an app.
public enum GameAppDestination {
    /// A new user may accept ~/Applications without a picker. Never recreate a remembered destination.
    public static func prepareInitialFolder(_ folder: URL, hasExplicitChoice: Bool,
                                            home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let initial = home.appendingPathComponent("Applications")
        guard !hasExplicitChoice, folder.standardizedFileURL.path == initial.standardizedFileURL.path,
              !FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }

    public static func url(for game: PortedGame, in folder: URL) -> URL {
        if game.status != .notBuilt, game.canDeleteAppBundle(),
           FileManager.default.fileExists(atPath: game.url.path) {
            return game.url
        }
        return url(name: game.name, titleId: game.titleId, in: folder)
    }

    public static func url(name: String, titleId: String?, in folder: URL) -> URL {
        let fm = FileManager.default
        let base = appName(name)
        let title = titleId.flatMap(ImportService.normalizedTitleId)
        let preferred = folder.appendingPathComponent(base + ".app")
        if !fm.fileExists(atPath: preferred.path) || (title != nil && titleID(at: preferred) == title) {
            return preferred
        }
        let stem = title.map { "\(base) (\($0))" } ?? base
        var candidate = folder.appendingPathComponent(stem + ".app")
        var number = 2
        while fm.fileExists(atPath: candidate.path) {
            if let title, titleID(at: candidate) == title { break }
            candidate = folder.appendingPathComponent("\(stem) \(number).app")
            number += 1
        }
        return candidate
    }

    /// Check before starting the engine. In particular, never recreate a disconnected destination.
    public static func folderProblem(at folder: URL, fileManager fm: FileManager = .default) -> String? {
        var isDirectory: ObjCBool = false
        guard folder.isFileURL, folder.standardizedFileURL.path != "/",
              fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fm.isReadableFile(atPath: folder.path), fm.isExecutableFile(atPath: folder.path) else {
            return "The Game apps folder is unavailable. Reconnect it or choose another in Settings → Library."
        }
        guard fm.isWritableFile(atPath: folder.path) else {
            return "The app folder is read-only: \(folder.path). Allow writing here before building."
        }
        return nil
    }

    private static func appName(_ name: String) -> String {
        let value = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: " -")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Game" : value
    }

    private static func titleID(at app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        let bundleID = info["CFBundleIdentifier"] as? String
        let suffix = bundleID?.hasPrefix("org.nxnative.") == true
            ? bundleID?.split(separator: ".").last.map(String.init) : nil
        return [info["DMTitleID"] as? String, suffix].compactMap { $0 }
            .compactMap(ImportService.normalizedTitleId).first
    }
}
