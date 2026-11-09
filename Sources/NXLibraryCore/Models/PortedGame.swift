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
    public var isFavorite: Bool = false
    public var isHidden: Bool = false
    /// The last porting failed or was cancelled; cleared by a successful one.
    public var portingFailure: PortingFailure?
    /// Why the last porting failed, when NX Library recognised it; cleared with `portingFailure`.
    public var portingFailureReason: PortingFailureReason?
    /// A finished build waiting for the game to quit before it replaces the running app.
    public var pendingInstall: PendingInstall?
    /// The player chose to show NX Library's Icon pick as the game app's icon in Finder and the Dock
    /// (`AppIconWriter`); written again after every build.
    public var usesPickedAppIcon = false
    /// Explicit scope chosen in Change artwork: false means only in NX Library, even without an original app icon.
    /// Nil preserves the behavior of libraries saved before 0.1.4.2 until the player makes a choice.
    public var appIconOnMac: Bool? = nil
    /// The app's icon still has to be written or put back: the game was running. Done when it quits.
    public var appIconPending = false

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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        url = try c.decode(URL.self, forKey: .url)
        platform = try c.decode(TargetPlatform.self, forKey: .platform)
        sizeBytes = try c.decode(Int64.self, forKey: .sizeBytes)
        modificationDate = try c.decode(Date.self, forKey: .modificationDate)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        titleId = try c.decodeIfPresent(String.self, forKey: .titleId)
        versionString = try c.decodeIfPresent(String.self, forKey: .versionString)
        sources = try c.decode([GameFileItem].self, forKey: .sources)
        workspacePath = try c.decodeIfPresent(String.self, forKey: .workspacePath)
        buildCachePath = try c.decodeIfPresent(String.self, forKey: .buildCachePath)
        status = try c.decode(GameStatus.self, forKey: .status)
        toolchain = try c.decode(ToolchainInfo.self, forKey: .toolchain)
        settings = try c.decode(GameRuntimeConfig.self, forKey: .settings)
        lastBuild = try c.decodeIfPresent(BuildRecord.self, forKey: .lastBuild)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        portingFailure = try c.decodeIfPresent(PortingFailure.self, forKey: .portingFailure)
        portingFailureReason = try c.decodeIfPresent(PortingFailureReason.self, forKey: .portingFailureReason)
        pendingInstall = try c.decodeIfPresent(PendingInstall.self, forKey: .pendingInstall)
        usesPickedAppIcon = try c.decodeIfPresent(Bool.self, forKey: .usesPickedAppIcon) ?? false
        appIconOnMac = try c.decodeIfPresent(Bool.self, forKey: .appIconOnMac)
        appIconPending = try c.decodeIfPresent(Bool.self, forKey: .appIconPending) ?? false
    }

    /// Shared by reconciliation and the icon writer, so an explicit launcher-only choice survives scans and builds.
    public func wantsPickedAppIcon(hasPick: Bool, hasOriginalIcon: Bool) -> Bool {
        hasPick && (appIconOnMac ?? (usesPickedAppIcon || !hasOriginalIcon))
    }

    /// Filling a genuinely missing app icon is allowed by default, but never after an explicit Only here choice.
    public func wantsAutomaticAppIcon(hasPick: Bool, hasOriginalIcon: Bool) -> Bool {
        !hasPick && !hasOriginalIcon && appIconOnMac != false
    }

    /// Selecting the image source does not change where the image is shown.
    public mutating func useAutomaticAppIcon() {
        if appIconOnMac == nil && usesPickedAppIcon { appIconOnMac = true }
        usesPickedAppIcon = false
        appIconPending = true
    }

    /// The bundle id the built app runs as: the stored one, else nxnative's default
    /// `org.nxnative.<title id in lowercase>`. Nil when neither is known; an empty id never matches.
    public var effectiveBundleId: String? {
        if let bundleId, !bundleId.isEmpty { return bundleId }
        if let titleId, !titleId.isEmpty { return "org.nxnative.\(titleId.lowercased())" }
        return nil
    }

    /// Switch 2 titles have IDs starting 04.
    public var isSwitch2: Bool { titleId?.hasPrefix("04") == true }

    public var consoleName: String { isSwitch2 ? "Nintendo Switch 2" : "Nintendo Switch" }

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
