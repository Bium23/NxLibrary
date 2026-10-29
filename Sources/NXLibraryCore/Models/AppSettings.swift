import Foundation

public enum BackgroundShade: String, Codable, CaseIterable, Identifiable, Equatable {
    case light, balanced, deep

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var heroScrimOpacity: Double {
        switch self {
        case .light: return 0.20
        case .balanced: return 0.35
        case .deep: return 0.55
        }
    }
}

public struct AppSettings: Codable, Equatable {
    public var backgroundShade: BackgroundShade
    public var readableText: Bool
    public var reduceMotion: Bool
    public var showButtonHints: Bool
    public var showClock: Bool
    public var restoreLastGame: Bool
    public var checkEngineAtLaunch: Bool
    public var refreshLibraryAtLaunch: Bool
    public var lastSelectedGameID: UUID?
    public var steamGridDbApiKey: String
    public var gameDefaults: GameRuntimeConfig
    public var colorThemeID: String
    public var buttonNames: ButtonNameStyle

    public init(backgroundShade: BackgroundShade = .balanced,
                readableText: Bool = true,
                reduceMotion: Bool = false,
                showButtonHints: Bool = true,
                showClock: Bool = true,
                restoreLastGame: Bool = true,
                checkEngineAtLaunch: Bool = true,
                refreshLibraryAtLaunch: Bool = true,
                lastSelectedGameID: UUID? = nil,
                steamGridDbApiKey: String = "",
                gameDefaults: GameRuntimeConfig = GameRuntimeConfig(),
                colorThemeID: String = "selene",
                buttonNames: ButtonNameStyle = .automatic) {
        self.backgroundShade = backgroundShade
        self.readableText = readableText
        self.reduceMotion = reduceMotion
        self.showButtonHints = showButtonHints
        self.showClock = showClock
        self.restoreLastGame = restoreLastGame
        self.checkEngineAtLaunch = checkEngineAtLaunch
        self.refreshLibraryAtLaunch = refreshLibraryAtLaunch
        self.lastSelectedGameID = lastSelectedGameID
        self.steamGridDbApiKey = steamGridDbApiKey
        self.gameDefaults = gameDefaults
        self.colorThemeID = colorThemeID
        self.buttonNames = buttonNames
    }

    enum CodingKeys: String, CodingKey {
        case backgroundShade, readableText, reduceMotion, showButtonHints, showClock
        case restoreLastGame, checkEngineAtLaunch, refreshLibraryAtLaunch, lastSelectedGameID
        case steamGridDbApiKey, gameDefaults, colorThemeID, buttonNames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backgroundShade = try container.decodeIfPresent(BackgroundShade.self, forKey: .backgroundShade) ?? .balanced
        self.readableText = try container.decodeIfPresent(Bool.self, forKey: .readableText) ?? true
        self.reduceMotion = try container.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? false
        self.showButtonHints = try container.decodeIfPresent(Bool.self, forKey: .showButtonHints) ?? true
        self.showClock = try container.decodeIfPresent(Bool.self, forKey: .showClock) ?? true
        self.restoreLastGame = try container.decodeIfPresent(Bool.self, forKey: .restoreLastGame) ?? true
        self.checkEngineAtLaunch = try container.decodeIfPresent(Bool.self, forKey: .checkEngineAtLaunch) ?? true
        self.refreshLibraryAtLaunch = try container.decodeIfPresent(Bool.self, forKey: .refreshLibraryAtLaunch) ?? true
        self.lastSelectedGameID = try container.decodeIfPresent(UUID.self, forKey: .lastSelectedGameID)
        self.steamGridDbApiKey = try container.decodeIfPresent(String.self, forKey: .steamGridDbApiKey) ?? ""
        self.gameDefaults = try container.decodeIfPresent(GameRuntimeConfig.self, forKey: .gameDefaults) ?? GameRuntimeConfig()
        self.colorThemeID = try container.decodeIfPresent(String.self, forKey: .colorThemeID) ?? "selene"
        self.buttonNames = try container.decodeIfPresent(ButtonNameStyle.self, forKey: .buttonNames) ?? .automatic
    }
}
