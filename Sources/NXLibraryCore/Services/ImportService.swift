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

    public init(fileManager: FileManager = .default) { self.fm = fileManager }

    public func scan(directories: [URL]) -> [ImportedApp] {
        var apps: [ImportedApp] = []
        for directory in directories {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items where item.pathExtension.lowercased() == "app" {
                guard let info = info(at: item) else { continue }
                let bundleId = info["CFBundleIdentifier"] as? String
                let dmTitle = info["DMTitleID"] as? String
                let suffix = bundleId?.split(separator: ".").last.map(String.init)
                let titleId = dmTitle
                    ?? (bundleId?.hasPrefix("org.nxnative.") == true ? suffix : nil)
                guard bundleId != "local.nxlibrary", titleId != nil else { continue }
                let name = (info["CFBundleDisplayName"] as? String)
                    ?? (info["CFBundleName"] as? String)
                    ?? item.deletingPathExtension().lastPathComponent
                let version = info["CFBundleShortVersionString"] as? String
                let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? Date.distantPast
                apps.append(ImportedApp(
                    name: name, version: version, titleId: titleId,
                    bundleId: bundleId, appURL: item,
                    sizeBytes: directorySize(item), modificationDate: date
                ))
            }
        }
        return apps.sorted { $0.modificationDate > $1.modificationDate }
    }

    public func makeGame(from app: ImportedApp) -> PortedGame {
        var game = PortedGame(
            name: app.name, url: app.appURL, platform: .macApp,
            sizeBytes: app.sizeBytes, modificationDate: app.modificationDate,
            bundleId: app.bundleId, titleId: app.titleId,
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

    private func info(at app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return object
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
