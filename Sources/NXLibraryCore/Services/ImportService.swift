import Foundation

public struct ImportedApp: Identifiable, Equatable {
    public var id: String { titleId ?? bundleId ?? appURL.path }
    public var name: String
    public var version: String?
    public var titleId: String?
    public var bundleId: String?
    public var appURL: URL
    public var sizeBytes: Int64
    public var modificationDate: Date

    public init(name: String, version: String?, titleId: String?,
                bundleId: String?, appURL: URL, sizeBytes: Int64,
                modificationDate: Date) {
        self.name = name
        self.version = version
        self.titleId = titleId
        self.bundleId = bundleId
        self.appURL = appURL
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
    }
}

public final class ImportService {
    private let fm: FileManager
    private let sizeCache: AppSizeCache
    private let maximumDepth: Int
    private let maximumDirectories: Int
    public private(set) var scanWarnings: [String] = []

    /// Without a cache, sizes are remembered for the life of this service only.
    public init(fileManager: FileManager = .default, sizeCache: AppSizeCache? = nil,
                maximumDepth: Int = 6, maximumDirectories: Int = 4000) {
        self.fm = fileManager
        self.sizeCache = sizeCache ?? AppSizeCache(file: nil)
        self.maximumDepth = max(0, maximumDepth)
        self.maximumDirectories = max(1, maximumDirectories)
    }

    public func scan(directories: [URL]) -> [ImportedApp] {
        var apps: [ImportedApp] = []
        scanWarnings = []
        var queue: [(url: URL, depth: Int)] = []
        var visited: Set<String> = []
        var appPaths: Set<String> = []

        func warn(_ message: String) {
            if scanWarnings.count < 5, !scanWarnings.contains(message) { scanWarnings.append(message) }
        }
        func enqueue(_ url: URL, depth: Int) {
            let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard !visited.contains(canonical) else { return }
            guard queue.count < maximumDirectories else {
                warn("Search stopped at \(maximumDirectories) folders. Choose a Game apps folder closer to your games.")
                return
            }
            visited.insert(canonical)
            queue.append((url, depth))
        }
        defer {
            sizeCache.retain(apps.map(\.appURL))
            sizeCache.save()
        }
        for directory in directories { enqueue(directory, depth: 0) }
        var next = 0
        while next < queue.count {
            let (directory, depth) = queue[next]
            next += 1
            let items: [URL]
            do {
                items = try fm.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
                                                  .contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            } catch {
                warn("Cannot read \(directory.path). Check folder access or choose another Game apps folder. (\(error.localizedDescription))")
                continue
            }
            for item in items.sorted(by: { $0.path < $1.path }) {
                if item.pathExtension.lowercased() != "app" {
                    if let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]),
                       values.isDirectory == true, values.isSymbolicLink != true, values.isPackage != true {
                        if depth < maximumDepth { enqueue(item, depth: depth + 1) }
                        else { warn("Some subfolders are more than \(maximumDepth) levels deep. Choose their parent as Game apps to scan them.") }
                    }
                    continue
                }
                // An app is a boundary, including an unrecognised app. Never discover its nested helpers.
                let canonical = item.resolvingSymlinksInPath().standardizedFileURL.path
                guard appPaths.insert(canonical).inserted else { continue }
                guard let info = info(at: item) else { continue }
                let bundleId = info["CFBundleIdentifier"] as? String
                let dmTitle = info["DMTitleID"] as? String
                let suffix = bundleId?.hasPrefix("org.nxnative.") == true
                    ? bundleId?.split(separator: ".").last.map(String.init) : nil
                let titleId = [dmTitle, suffix]
                    .compactMap { $0 }
                    .compactMap(Self.normalizedTitleId)
                    .first
                guard bundleId != "local.nxlibrary", let titleId else { continue }
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? item.deletingPathExtension().lastPathComponent
                let version = info["CFBundleShortVersionString"] as? String
                let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date.distantPast
                apps.append(ImportedApp(
                    name: name, version: version, titleId: titleId,
                    bundleId: bundleId, appURL: item,
                    sizeBytes: size(of: item, date: date), modificationDate: date
                ))
            }
        }
        return apps.sorted {
            if $0.modificationDate == $1.modificationDate { return $0.appURL.path < $1.appURL.path }
            return $0.modificationDate > $1.modificationDate
        }
    }

    /// Select one observation per title before merging it into the persisted catalog.
    public func appsForLibrary(scanned: [ImportedApp], existing: [PortedGame]) -> [ImportedApp] {
        var preferred: [String: String] = [:]
        for game in existing {
            if let title = game.titleId, game.url.pathExtension.lowercased() == "app",
               fm.fileExists(atPath: game.url.path) {
                preferred[title.uppercased()] = game.url.resolvingSymlinksInPath().standardizedFileURL.path
            }
        }
        var selected: [String: ImportedApp] = [:]
        // scan() is newest first. A known installed path takes precedence over another copy.
        for app in scanned {
            let key = app.id.uppercased()
            if let path = preferred[key], app.appURL.resolvingSymlinksInPath().standardizedFileURL.path != path {
                continue
            }
            if selected[key] == nil { selected[key] = app }
        }
        return selected.values.sorted {
            if $0.modificationDate == $1.modificationDate { return $0.appURL.path < $1.appURL.path }
            return $0.modificationDate > $1.modificationDate
        }
    }

    public func makeGame(from app: ImportedApp) -> PortedGame {
        var game = PortedGame(
            name: app.name, url: app.appURL, platform: .macApp,
            sizeBytes: app.sizeBytes, modificationDate: app.modificationDate,
            bundleId: app.bundleId,
            titleId: app.titleId.flatMap(Self.normalizedTitleId),
            versionString: app.version
        )
        game.status = .builtSourcesMissing
        game.toolchain = ToolchainInfo(
            verified: false,
            note: "Imported build; build record unavailable"
        )
        game.settings = GameRuntimeConfig()
        return game
    }

    static func normalizedTitleId(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("0x") { text.removeFirst(2) }
        guard text.count == 16,
              text.allSatisfy({ $0.isHexDigit }) else { return nil }
        return text.uppercased()
    }

    private func info(at app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object
    }

    /// The remembered size while the app's date is unchanged, else measured.
    private func size(of app: URL, date: Date) -> Int64 {
        if let known = sizeCache.size(for: app, date: date) { return known }
        let measured = directorySize(app)
        sizeCache.set(measured, for: app, date: date)
        return measured
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
