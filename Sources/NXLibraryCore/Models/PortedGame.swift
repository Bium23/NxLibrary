import Foundation

public struct PortedGame: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var url: URL
    public var platform: TargetPlatform
    public var sizeBytes: Int64
    public var modificationDate: Date
    public var bundleId: String?
    public var titleId: String?
    public var versionString: String?
    public var sources: [GameFileItem]
    public var workspacePath: String?
    public var buildCachePath: String?
    public var status: GameStatus
    public var toolchain: ToolchainInfo
    public var settings: GameRuntimeConfig
    public var lastBuild: BuildRecord?

    public init(id: UUID = UUID(), name: String, url: URL,
                platform: TargetPlatform, sizeBytes: Int64,
                modificationDate: Date, bundleId: String? = nil,
                titleId: String? = nil, versionString: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.platform = platform
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.bundleId = bundleId
        self.titleId = titleId
        self.versionString = versionString
        self.sources = []
        self.workspacePath = nil
        self.buildCachePath = nil
        self.status = .notBuilt
        self.toolchain = ToolchainInfo()
        self.settings = GameRuntimeConfig()
        self.lastBuild = nil
    }

    public var uniqueKey: String {
        if let titleId, !titleId.isEmpty { return titleId }
        if let bundleId, !bundleId.isEmpty { return bundleId }
        return name
    }

    /// True only when `url` is an installed app bundle and none of the source
    /// files live inside it. This prevents "delete game" from removing a source
    /// folder that happens to be used as the workspace before a build.
    public func canDeleteAppBundle() -> Bool {
        guard url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(
                atPath: url.appendingPathComponent("Contents/Info.plist").path) else {
            return false
        }
        let appPath = url.standardizedFileURL.path
        if let workspacePath,
           URL(fileURLWithPath: workspacePath).standardizedFileURL.path == appPath {
            return false
        }
        for source in sources {
            let sourcePath = source.url.standardizedFileURL.path
            if sourcePath == appPath || sourcePath.hasPrefix(appPath + "/") {
                return false
            }
        }
        return true
    }

    public var isPlayableLocally: Bool {
        guard platform == .macApp,
              url.pathExtension.lowercased() == "app" else { return false }
        switch status {
        case .notBuilt, .building, .appMissing:
            return false
        default:
            return true
        }
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }
}
