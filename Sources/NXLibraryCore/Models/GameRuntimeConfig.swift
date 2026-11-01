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

    public init(enable60FPS: Bool = true, enableMetalHUD: Bool = false,
                isDockedMode: Bool = true, renderScale: Double = 1.0,
                enableMetalFXUpscale: Bool = false, language: String = "auto",
                rumble: Bool = true, rumbleGain: Int = 1, fullscreen: Bool = false) {
        self.enable60FPS = enable60FPS
        self.enableMetalHUD = enableMetalHUD
        self.isDockedMode = isDockedMode
        self.renderScale = renderScale
        self.enableMetalFXUpscale = enableMetalFXUpscale
        self.language = language
        self.rumble = rumble
        self.rumbleGain = rumbleGain
        self.fullscreen = fullscreen
    }

    // Core-facing aliases; the launcher views keep their original property names.
    public var fpsTarget: Int {
        get { enable60FPS ? 60 : 30 }
        set { enable60FPS = newValue != 30 }
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
            "DM_FPS_TARGET": enable60FPS ? "60" : "30",
            "DM_METAL_HUD": enableMetalHUD ? "1" : "0",
            "DM_OPMODE": isDockedMode ? "1" : "0",
            "DM_RENDER_SCALE": String(format: "%.2f", renderScale),
            "DM_PRESENT_UPSCALE": enableMetalFXUpscale ? "metalfx" : "off",
            "DM_RUMBLE": rumble ? "1" : "0",
            "DM_RUMBLE_GAIN": "\(rumbleGain)",
            "DM_FULLSCREEN": fullscreen ? "1" : "0",
        ]
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

    public func save(for game: PortedGame) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey(for: game))
        }
        applyToDisk(for: game)
    }

    public func applyToDisk(for game: PortedGame) {
        guard let titleId = game.titleId, !titleId.isEmpty else { return }
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/nxnative")
            .appendingPathComponent(titleId)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let envURL = dir.appendingPathComponent("env.txt")
        let existing = try? String(contentsOf: envURL, encoding: .utf8)
        try? mergedEnvContent(existing: existing).write(
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
            case "DM_FPS_TARGET": config.enable60FPS = value != "30"
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
