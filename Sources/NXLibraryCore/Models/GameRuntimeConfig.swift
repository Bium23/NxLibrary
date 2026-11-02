import Foundation

public struct GameRuntimeConfig: Codable, Equatable {
    public var enable60FPS: Bool
    public var enableMetalHUD: Bool
    public var isDockedMode: Bool
    public var renderScale: Double
    public var enableMetalFXUpscale: Bool
    public var language: String
    public var rumble: Bool
    public var rumbleGain: Int
    public var fullscreen: Bool
    /// With `enable60FPS`: 120 FPS instead of 60, for a game whose app offers it (its launcher.json lists DM_FPS_TARGET 120).
    public var highFrameRate: Bool
    /// DM_PAD_LAYOUT ("position" or "xbox"); nil leaves the app's own choice.
    public var buttonLayout: String?
    /// DM_PRESENT_FILL ("fit" or "stretch"); nil leaves the app's own choice.
    public var screenFill: String?

    public init(enable60FPS: Bool = true, enableMetalHUD: Bool = false,
                isDockedMode: Bool = true, renderScale: Double = 1.0,
                enableMetalFXUpscale: Bool = false, language: String = "auto",
                rumble: Bool = true, rumbleGain: Int = 1, fullscreen: Bool = false,
                highFrameRate: Bool = false, buttonLayout: String? = nil, screenFill: String? = nil) {
        self.enable60FPS = enable60FPS
        self.enableMetalHUD = enableMetalHUD
        self.isDockedMode = isDockedMode
        self.renderScale = renderScale
        self.enableMetalFXUpscale = enableMetalFXUpscale
        self.language = language
        self.rumble = rumble
        self.rumbleGain = rumbleGain
        self.fullscreen = fullscreen
        self.highFrameRate = highFrameRate
        self.buttonLayout = buttonLayout
        self.screenFill = screenFill
    }

    private enum CodingKeys: String, CodingKey {
        case enable60FPS, enableMetalHUD, isDockedMode, renderScale, enableMetalFXUpscale
        case language, rumble, rumbleGain, fullscreen
        case highFrameRate, buttonLayout, screenFill
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enable60FPS: try values.decodeIfPresent(Bool.self, forKey: .enable60FPS) ?? true,
            enableMetalHUD: try values.decodeIfPresent(Bool.self, forKey: .enableMetalHUD) ?? false,
            isDockedMode: try values.decodeIfPresent(Bool.self, forKey: .isDockedMode) ?? true,
            renderScale: try values.decodeIfPresent(Double.self, forKey: .renderScale) ?? 1,
            enableMetalFXUpscale: try values.decodeIfPresent(Bool.self, forKey: .enableMetalFXUpscale) ?? false,
            language: try values.decodeIfPresent(String.self, forKey: .language) ?? "auto",
            rumble: try values.decodeIfPresent(Bool.self, forKey: .rumble) ?? true,
            rumbleGain: try values.decodeIfPresent(Int.self, forKey: .rumbleGain) ?? 1,
            fullscreen: try values.decodeIfPresent(Bool.self, forKey: .fullscreen) ?? false,
            highFrameRate: try values.decodeIfPresent(Bool.self, forKey: .highFrameRate) ?? false,
            buttonLayout: try values.decodeIfPresent(String.self, forKey: .buttonLayout),
            screenFill: try values.decodeIfPresent(String.self, forKey: .screenFill)
        )
    }

    // Core-facing aliases; the launcher views keep their original property names.
    public var fpsTarget: Int {
        get { enable60FPS ? (highFrameRate ? 120 : 60) : 30 }
        set { enable60FPS = newValue != 30; highFrameRate = newValue == 120 }
    }
    public var metalHUD: Bool {
        get { enableMetalHUD }
        set { enableMetalHUD = newValue }
    }
    public var opmode: Int {
        get { isDockedMode ? 1 : 0 }
        set { isDockedMode = newValue == 1 }
    }
    public var presentUpscale: String {
        get { enableMetalFXUpscale ? "metalfx" : "off" }
        set { enableMetalFXUpscale = newValue == "metalfx" }
    }

    public func toEnvironmentDict() -> [String: String] {
        var values: [String: String] = [
            "DM_FPS_TARGET": "\(fpsTarget)",
            "DM_METAL_HUD": enableMetalHUD ? "1" : "0",
            "DM_OPMODE": isDockedMode ? "1" : "0",
            "DM_RENDER_SCALE": String(format: "%.2f", renderScale),
            "DM_PRESENT_UPSCALE": enableMetalFXUpscale ? "metalfx" : "off",
            "DM_RUMBLE": rumble ? "1" : "0",
            "DM_RUMBLE_GAIN": "\(rumbleGain)",
            "DM_FULLSCREEN": fullscreen ? "1" : "0",
        ]
        if let buttonLayout, !buttonLayout.isEmpty { values["DM_PAD_LAYOUT"] = buttonLayout }
        if let screenFill, !screenFill.isEmpty { values["DM_PRESENT_FILL"] = screenFill }
        // "auto" lets the engine's own language (DMLanguage) apply.
        if language != "auto", !language.isEmpty {
            values["DM_LANG"] = language
        }
        return values
    }

    public func mergedEnvContent(existing: String?) -> String {
        var values = Self.parseEnvDict(existing)
        for (key, value) in toEnvironmentDict() {
            values[key] = value
        }
        if language == "auto" || language.isEmpty {
            values.removeValue(forKey: "DM_LANG")
        }
        return values.keys.sorted().map { "\($0)=\(values[$0]!)" }
            .joined(separator: "\n") + "\n"
    }

    public func envFileContent() -> String {
        mergedEnvContent(existing: nil)
    }

    public var languageForBuild: String? {
        language == "auto" || language.isEmpty ? nil : language
    }

    public static func forReview(existing game: PortedGame?, defaults: GameRuntimeConfig) -> GameRuntimeConfig {
        game.map { load(for: $0) } ?? defaults
    }

    public static func storageKey(for game: PortedGame) -> String {
        "NXNative_GameConfig_" + game.uniqueKey
    }

    public static func load(for game: PortedGame) -> GameRuntimeConfig {
        if let data = UserDefaults.standard.data(forKey: storageKey(for: game)),
           let config = try? JSONDecoder().decode(GameRuntimeConfig.self, from: data) {
            return config
        }
        if let titleId = game.titleId, !titleId.isEmpty {
            let env = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/nxnative")
                .appendingPathComponent(titleId)
                .appendingPathComponent("env.txt")
            if let content = try? String(contentsOf: env, encoding: .utf8) {
                return parseEnvContent(content)
            }
        }
        let bundleEnv = game.url.appendingPathComponent("Contents/Resources/dm/env.txt")
        if let content = try? String(contentsOf: bundleEnv, encoding: .utf8) {
            return parseEnvContent(content)
        }
        return GameRuntimeConfig()
    }

    public func save(for game: PortedGame,
                     baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent("Library/Application Support/nxnative"),
                     preferences: UserDefaults = .standard) throws {
        let data = try JSONEncoder().encode(self)
        try applyToDisk(for: game, baseDirectory: baseDirectory)
        preferences.set(data, forKey: Self.storageKey(for: game))
    }

    public func applyToDisk(for game: PortedGame,
                            baseDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Library/Application Support/nxnative")) throws {
        guard let titleId = game.titleId, !titleId.isEmpty else { return }
        let fm = FileManager.default
        let dir = baseDirectory.appendingPathComponent(titleId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let envURL = dir.appendingPathComponent("env.txt")
        let existing = fm.fileExists(atPath: envURL.path) ? try String(contentsOf: envURL, encoding: .utf8) : nil
        try mergedEnvContent(existing: existing).write(
            to: envURL, atomically: true, encoding: .utf8
        )
    }

    private static func parseEnvDict(_ text: String?) -> [String: String] {
        guard let text else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || !trimmed.contains("=") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    static func parseEnvContent(_ text: String) -> GameRuntimeConfig {
        var config = GameRuntimeConfig()
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || !trimmed.contains("=") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "DM_FPS_TARGET": config.fpsTarget = Int(value) ?? 60
            case "DM_PAD_LAYOUT": config.buttonLayout = value
            case "DM_PRESENT_FILL": config.screenFill = value
            case "DM_METAL_HUD": config.enableMetalHUD = value == "1"
            case "DM_OPMODE": config.isDockedMode = value != "0"
            case "DM_RENDER_SCALE": config.renderScale = Double(value) ?? 1.0
            case "DM_PRESENT_UPSCALE": config.enableMetalFXUpscale = value == "metalfx"
            case "DM_LANG": config.language = value
            case "DM_RUMBLE": config.rumble = value != "0"
            case "DM_RUMBLE_GAIN": config.rumbleGain = Int(value) ?? 1
            case "DM_FULLSCREEN": config.fullscreen = value == "1"
            default: break
            }
        }
        return config
    }
}
