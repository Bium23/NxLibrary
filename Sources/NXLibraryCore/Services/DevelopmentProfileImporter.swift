import Foundation
import CryptoKit

public enum DevelopmentProfileError: Error, LocalizedError {
    case invalidConfiguration, destinationExists, unsafeFile, invalidData, sourceChanged, preferencesUnavailable
    case unreadableFile(String)
    public var errorDescription: String? {
        let context = AppLocale(language: .automatic, region: nil)
        switch self {
        case .unreadableFile(let name): return L10n.format("The launcher file %@ could not be read. The original data has not been changed.", [name], context: context)
        case .invalidConfiguration: return L10n.text("The development profile configuration is invalid.", context: context)
        case .destinationExists: return L10n.text("The development data folder already exists without a completed import. It has been preserved.", context: context)
        case .unsafeFile: return L10n.text("The library copy contains a symbolic link or an unsupported file. The original data has not been changed.", context: context)
        case .invalidData: return L10n.text("Some launcher data could not be read. The original data has not been changed.", context: context)
        case .sourceChanged: return L10n.text("The original library changed during the copy. Close the other launcher copy and try again.", context: context)
        case .preferencesUnavailable: return L10n.text("The development preferences could not be saved. Try again.", context: context)
        }
    }
}

/// An allowlisted, one-time snapshot. Reads source bytes directly: source-store load/recovery hooks never run.
public struct DevelopmentProfileImporter {
    private let fm: FileManager
    public init(fileManager: FileManager = .default) { fm = fileManager }
    private static let files = ["library.json", "library.json.bak", "catalog.json", "catalog.json.bak", "settings.json", "play-sessions.json", "play-sessions-totals.json", "metadata-picks.json", "integrations/steam/metadata-picks.json", "app-sizes.json"]
    private static let folders = ["artwork-picks", "integrations/steam/artwork-picks", "artwork", "metadata", "SeleneImports", "app-icons", "mods", "gamebanana"]
    private static let marker = ".development-import.json"
    private static let preferenceFile = ".import-preferences.plist"
    private struct ImportState: Codable {
        let version: Int
        var ready: Bool
        let hashes: [String: String]
    }
    public func prepare(profile: AppDataProfile, sourcePreferences: () throws -> [String: Any],
                        savePreferences: ([String: Any]) throws -> Void) throws -> Bool {
        guard profile.isDevelopment else { return false }
        let source = profile.stableSupportRoot, destination = profile.supportRoot
        guard source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else { throw DevelopmentProfileError.invalidConfiguration }
        if try exists(destination) {
            try regularDirectory(destination)
            let marker = destination.appendingPathComponent(Self.marker)
            guard (try? fm.attributesOfItem(atPath: marker.path)[.type] as? FileAttributeType) == .typeRegular else { throw DevelopmentProfileError.destinationExists }
            guard let data = try? Data(contentsOf: marker), let state = try? JSONDecoder().decode(ImportState.self, from: data), state.version == 1 else {
                throw DevelopmentProfileError.destinationExists
            }
            if state.ready { return false }
            try finish(destination, state: state, savePreferences: savePreferences)
            return true
        }
        if try exists(source) { try regularDirectory(source) }
        let before = try snapshot(source)
        let preferences = try sourcePreferences().filter { Self.ownedPreference($0.key) }
        let preferencesData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".NXLibrary-Development-import-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) } // Only the staging folder created by this invocation.
        for relative in before.keys.sorted() {
            let from = source.appendingPathComponent(relative), to = stage.appendingPathComponent(relative)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard try fm.attributesOfItem(atPath: from.path)[.type] as? FileAttributeType == .typeRegular else { throw DevelopmentProfileError.sourceChanged }
            try fm.copyItem(at: from, to: to)
            guard try digest(to) == before[relative] else { throw DevelopmentProfileError.sourceChanged }
            if relative.hasSuffix(".json") {
                do { _ = try JSONSerialization.jsonObject(with: Data(contentsOf: to), options: [.fragmentsAllowed]) }
                catch { throw DevelopmentProfileError.unreadableFile(relative) }
            }
        }
        try validateRequiredData(stage)
        guard try snapshot(source) == before,
              NSDictionary(dictionary: try sourcePreferences().filter { Self.ownedPreference($0.key) }).isEqual(to: preferences) else { throw DevelopmentProfileError.sourceChanged }
        try preferencesData.write(to: stage.appendingPathComponent(Self.preferenceFile), options: .atomic)
        // End a copied unfinished session at its last recorded heartbeat, never at the current time.
        let sessionFile = stage.appendingPathComponent("play-sessions.json")
        if try exists(sessionFile) {
            var sessions = try JSONDecoder().decode([PlaySession].self, from: Data(contentsOf: sessionFile))
            if sessions.contains(where: \.isActive) {
                for i in sessions.indices where sessions[i].isActive {
                    sessions[i].endedAt = max(sessions[i].startedAt, sessions[i].lastHeartbeatAt)
                }
                try JSONEncoder().encode(sessions).write(to: sessionFile, options: .atomic)
            }
        }
        let state = ImportState(version: 1, ready: false, hashes: try snapshot(stage))
        try JSONEncoder().encode(state).write(to: stage.appendingPathComponent(Self.marker), options: .atomic)
        // Moving into place never replaces an existing destination. A racing import fails safely.
        try fm.moveItem(at: stage, to: destination)
        try finish(destination, state: state, savePreferences: savePreferences)
        return true
    }
    private func finish(_ destination: URL, state: ImportState, savePreferences: ([String: Any]) throws -> Void) throws {
        guard try snapshot(destination) == state.hashes else { throw DevelopmentProfileError.invalidData }
        let preferenceFile = destination.appendingPathComponent(Self.preferenceFile)
        guard try fm.attributesOfItem(atPath: preferenceFile.path)[.type] as? FileAttributeType == .typeRegular else { throw DevelopmentProfileError.unsafeFile }
        let data = try Data(contentsOf: preferenceFile)
        guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw DevelopmentProfileError.invalidData }
        try savePreferences(values.filter { Self.ownedPreference($0.key) })
        var ready = state
        ready.ready = true
        try JSONEncoder().encode(ready).write(to: destination.appendingPathComponent(Self.marker), options: .atomic)
    }
    // Version-one legacy launcher preference schema. Do not copy future secrets just because they share a prefix.
    private static let preferenceKeys: Set<String> = [
        "NXLibrary.lastPortingFinishSeconds", "NXLibrary_AllowUntestedToolchain", "NXLibrary_EngineFolder",
        "NXLibrary_NewestEngineChoice", "NXLibrary_SetupCompleted", "NXLibrary_SetupLastStates", "NXLibrary_SetupPage",
        "NXLibrary_UpdateLastCheck", "NXLibrary_UpdateLaterAt", "NXLibrary_UpdateLaterVersion", "NXLibrary_UpdateRepository",
        "NXLibrary_UpstreamStatus", "NXNative_ControllerDeadzone", "NXNative_SavedGameFolder", "NXNative_SavedIconAppearanceMode",
        "NXNative_SavedLibraryFolder", "NXNative_SavedProdKeysPath"
    ]
    public static func ownedPreference(_ key: String) -> Bool {
        preferenceKeys.contains(key) || key.hasPrefix("NXNative_GameConfig_")
    }
    private func validateRequiredData(_ root: URL) throws {
        for name in ["library.json", "catalog.json", "catalog.json.bak", "settings.json", "play-sessions.json"] {
            let file = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { continue }
            let data = try Data(contentsOf: file)
            do {
                switch name {
                case "library.json":
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    _ = try decoder.decode(LibraryFile.self, from: data)
                case "catalog.json", "catalog.json.bak":
                    let document = try CatalogStore.decode(data)
                    try CatalogStore(directory: root).validateImportedOrigin(document)
                case "settings.json": _ = try JSONDecoder().decode(AppSettings.self, from: data)
                default: _ = try JSONDecoder().decode([PlaySession].self, from: data)
                }
            } catch { throw DevelopmentProfileError.unreadableFile(name) }
        }
    }
    private func snapshot(_ root: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        func visit(_ relative: String, depth: Int) throws {
            guard depth < 32, result.count < 100_000 else { throw DevelopmentProfileError.unsafeFile }
            let url = root.appendingPathComponent(relative)
            let attrs = try fm.attributesOfItem(atPath: url.path)
            switch attrs[.type] as? FileAttributeType {
            case .typeRegular: result[relative] = try digest(url)
            case .typeDirectory:
                for name in try fm.contentsOfDirectory(atPath: url.path).sorted() { try visit(relative + "/" + name, depth: depth + 1) }
            default: throw DevelopmentProfileError.unsafeFile
            }
        }
        for name in Self.files + Self.folders {
            let url = root.appendingPathComponent(name)
            // attributes also detects broken symlinks, which fileExists would silently skip.
            if try exists(url) { try visit(name, depth: 0) }
        }
        return result
    }
    private func exists(_ url: URL) throws -> Bool {
        do { _ = try fm.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return false }
    }
    private func regularDirectory(_ url: URL) throws {
        guard try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else { throw DevelopmentProfileError.unsafeFile }
    }
    private func digest(_ url: URL) throws -> String {
        guard try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else { throw DevelopmentProfileError.unsafeFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
