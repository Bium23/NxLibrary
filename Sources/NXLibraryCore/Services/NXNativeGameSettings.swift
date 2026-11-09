import Foundation

/// A game's settings as they apply now: the build's list, each setting's value, and the keys the player's
/// `env.txt` sets, which win in the engine and so cannot be changed here.
public struct GameSettingsSnapshot: Equatable {
    public let settings: [LauncherSetting]
    public let values: [String: String]
    public let fixed: Set<String>

    public init(settings: [LauncherSetting], values: [String: String], fixed: Set<String>) {
        self.settings = settings
        self.values = values
        self.fixed = fixed
    }

    public func setting(_ env: String) -> LauncherSetting? { settings.first { $0.env == env } }
    public func value(_ env: String) -> String? { values[env] }
    public func isOffered(_ env: String) -> Bool { setting(env) != nil }

    /// Offered, and its `needs` holds.
    public func visible(_ env: String) -> Bool {
        setting(env)?.needsSatisfied(values) ?? false
    }
}

public enum GameSettingsError: LocalizedError, Equatable {
    case notOffered(String)
    case refused(String, String)

    public var errorDescription: String? {
        switch self {
        case .notOffered(let env): return L10n.format("This build has no %@ setting.", [String(describing: (env))])
        case .refused(let env, let value): return L10n.format("This build does not take %@=%@.", [String(describing: (env)), String(describing: (value))])
        }
    }
}

/// The settings of a game built with saved choices (its Info.plist has DMSettings): kept as `launcher.<env>` in the
/// app's preferences domain, only where they differ from the build's tested default (docs/frontends.md). A build
/// from before saved choices has no adapter and keeps `env.txt` (`GameRuntimeConfig.save`).
public struct NXNativeGameSettings {
    /// The keys NX Library wrote into every game's env.txt up to 0.1.2.
    public static let managedKeys: Set<String> = [
        "DM_FPS_TARGET", "DM_METAL_HUD", "DM_OPMODE", "DM_RENDER_SCALE", "DM_PRESENT_UPSCALE",
        "DM_LANG", "DM_RUMBLE", "DM_RUMBLE_GAIN", "DM_FULLSCREEN",
    ]

    public let settings: [LauncherSetting]
    public let domain: String
    public let envURL: URL
    private let store: SavedChoicesStore
    private let preferences: UserDefaults
    private let legacyKey: String

    public static func forGame(_ game: PortedGame,
                               store: SavedChoicesStore = SystemSavedChoices(),
                               supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                                   .appendingPathComponent("Library/Application Support/nxnative"),
                               preferences: UserDefaults = .standard) -> NXNativeGameSettings? {
        guard let titleId = game.titleId, !titleId.isEmpty else { return nil }
        let plist = game.url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["DMSettings"] is [Any],
              let file = LauncherSettingsReader.load(for: game.url),
              let domain = (info["CFBundleIdentifier"] as? String) ?? game.effectiveBundleId else { return nil }
        return NXNativeGameSettings(
            settings: file.settings, domain: domain,
            envURL: supportDirectory.appendingPathComponent(titleId).appendingPathComponent("env.txt"),
            store: store, preferences: preferences, legacyKey: GameRuntimeConfig.storageKey(for: game))
    }

    private func setting(_ env: String) -> LauncherSetting? { settings.first { $0.env == env } }

    // MARK: - Migration

    /// Moves the lines NX Library wrote into env.txt to saved choices: each managed key this build offers and
    /// accepts, replacing a saved choice (the env.txt line is what the game used). Every other line stays; a file
    /// with no settings left is removed. NX Library's own copy in its preferences goes too. Safe to repeat.
    public func migrate() throws {
        preferences.removeObject(forKey: legacyKey)
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return }
        var kept: [String] = []
        var moved = false
        for line in text.components(separatedBy: "\n") {
            if let (key, value) = Self.pair(line), Self.managedKeys.contains(key),
               let setting = setting(key), setting.accepts(value) {
                try store.set(setting.isDefault(value) ? nil : value, key, domain: domain)
                moved = true
            } else {
                kept.append(line)
            }
        }
        guard moved else { return }
        while kept.last == "" { kept.removeLast() }
        if kept.contains(where: { Self.pair($0) != nil }) {
            try (kept.joined(separator: "\n") + "\n").write(to: envURL, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.removeItem(at: envURL)
        }
    }

    // MARK: - Reading and writing

    /// What each setting is now: the player's env.txt, then a saved choice this build accepts, then the default.
    public func snapshot() -> GameSettingsSnapshot {
        try? migrate()
        let env = envValues()
        var values: [String: String] = [:]
        var fixed: Set<String> = []
        for setting in settings {
            if let value = env[setting.env] {
                values[setting.env] = value
                fixed.insert(setting.env)
            } else if let saved = store.value(setting.env, domain: domain), setting.accepts(saved) {
                values[setting.env] = saved
            } else {
                values[setting.env] = setting.defaultValue ?? ""
            }
        }
        return GameSettingsSnapshot(settings: settings, values: values, fixed: fixed)
    }

    /// Keeps `value` as the player's choice; the build's default removes the key.
    public func set(_ env: String, to value: String) throws {
        guard let setting = setting(env) else { throw GameSettingsError.notOffered(env) }
        guard setting.accepts(value) else { throw GameSettingsError.refused(env, value) }
        try store.set(setting.isDefault(value) ? nil : value, env, domain: domain)
    }

    /// Every setting back to the build's tested default.
    public func resetAll() throws {
        for setting in settings { try store.set(nil, setting.env, domain: domain) }
    }

    // MARK: - The typed view

    /// The typed settings Add game and the new-game defaults use, from the values that apply now.
    public func runtimeConfig() -> GameRuntimeConfig {
        var config = GameRuntimeConfig.parseEnvContent((try? String(contentsOf: envURL, encoding: .utf8)) ?? "")
        let values = snapshot().values
        if let v = values["DM_FPS_TARGET"] { config.enable60FPS = v != "30" }
        if let v = values["DM_METAL_HUD"] { config.enableMetalHUD = v == "1" }
        if let v = values["DM_OPMODE"] { config.isDockedMode = v != "0" }
        if let v = values["DM_RENDER_SCALE"], let x = LauncherSetting.number(v) { config.renderScale = x }
        if let v = values["DM_PRESENT_UPSCALE"] { config.enableMetalFXUpscale = v == "metalfx" }
        if let v = values["DM_LANG"], !v.isEmpty { config.language = v }
        if let v = values["DM_RUMBLE"] { config.rumble = v != "0" }
        if let v = values["DM_RUMBLE_GAIN"], let x = LauncherSetting.number(v) { config.rumbleGain = Int(x.rounded()) }
        if let v = values["DM_FULLSCREEN"] { config.fullscreen = v == "1" }
        return config
    }

    /// Writes the typed fields `config` changed from `base`, where this build offers and takes them: a value the
    /// typed view cannot show (120 fps, a 0.5 strength) stays unless the player changed that field.
    public func apply(_ config: GameRuntimeConfig, changedFrom base: GameRuntimeConfig) throws {
        let new = typedValues(config)
        let old = typedValues(base)
        for (env, value) in new where old[env] != value {
            guard let setting = setting(env), setting.accepts(value) else { continue }
            try store.set(setting.isDefault(value) ? nil : value, env, domain: domain)
        }
    }

    private func typedValues(_ c: GameRuntimeConfig) -> [String: String] {
        [
            "DM_FPS_TARGET": c.enable60FPS ? "60" : "30",
            "DM_METAL_HUD": c.enableMetalHUD ? "1" : "0",
            "DM_OPMODE": c.isDockedMode ? "1" : "0",
            "DM_RENDER_SCALE": LauncherSetting.rangeString(c.renderScale),
            "DM_PRESENT_UPSCALE": c.enableMetalFXUpscale ? "metalfx" : "off",
            // "auto" is the build's own language.
            "DM_LANG": c.language == "auto" || c.language.isEmpty ? (setting("DM_LANG")?.defaultValue ?? "") : c.language,
            "DM_RUMBLE": c.rumble ? "1" : "0",
            "DM_RUMBLE_GAIN": LauncherSetting.rangeString(Double(c.rumbleGain)),
            "DM_FULLSCREEN": c.fullscreen ? "1" : "0",
        ]
    }

    // MARK: - env.txt

    private func envValues() -> [String: String] {
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            if let (key, value) = Self.pair(line), values[key] == nil { values[key] = value }
        }
        return values
    }

    /// A `KEY=VALUE` line, as the launcher reads it; nil for comments and blank lines.
    static func pair(_ line: String) -> (String, String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
        let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return (key, trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))
    }
}
