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

    /// Multiplies Selene's 0.3 left / bottom / top shades over the art.
    public var scrimMultiplier: Double {
        switch self {
        case .light: return 0.7
        case .balanced: return 1
        case .deep: return 1.6
        }
    }
}

/// Which home screen the app opens on (and which one was last used).
public enum StartScreen: String, Codable, CaseIterable {
    case spotlight, collection, last
}

/// How the background artwork is fitted to the window.
public enum BackgroundSizing: String, Codable, CaseIterable, Identifiable, Equatable {
    case fill, fit, stretch

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        }
    }
}

/// What a game's launch screen shows while its window starts.
public enum LaunchStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    case artAndLogo, artOnly, logoOnBlack, minimal

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .artAndLogo: return "Art and logo"
        case .artOnly: return "Art only"
        case .logoOnBlack: return "Logo on black"
        case .minimal: return "Minimal"
        }
    }
}

/// Shading laid over the launch screen art.
public enum LaunchShade: String, Codable, CaseIterable, Identifiable, Equatable {
    case none, soft, dark

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .none: return "None"
        case .soft: return "Soft"
        case .dark: return "Dark"
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
    public var spotlightCards: [SpotlightCard]
    public var spotlightOrder: [String]
    public var startingTab: LibraryFilter.RawValue
    public var surprisePool: SurprisePool
    /// The library's cloud saves folder, written into each game's preferences.
    public var cloudSaves: CloudSaves
    /// The last folder picked for cloud saves, so stepping back to Folder finds it.
    public var cloudSavesPickedFolder: String
    public var startOn: StartScreen
    /// The home screen last shown: `.spotlight` or `.collection`.
    public var lastHome: StartScreen
    public var introAnimation: Bool
    public var viewButtonSwitches: Bool
    public var interfaceSounds: Bool
    public var soundVolume: Double
    public var quietLaunch: Bool
    /// Nil means the palette's default wallpaper.
    public var wallpaperID: String?
    public var backgroundSizing: BackgroundSizing
    public var animatedBackground: Bool
    public var launchStyle: LaunchStyle
    public var launchMotion: Bool
    public var launchShade: LaunchShade

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
                buttonNames: ButtonNameStyle = .automatic,
                spotlightCards: [SpotlightCard] = [.surprise, .activity, .addGame],
                spotlightOrder: [String] = [],
                startingTab: LibraryFilter.RawValue = "All games",
                surprisePool: SurprisePool = .installed,
                cloudSaves: CloudSaves = .off,
                cloudSavesPickedFolder: String = "",
                startOn: StartScreen = .spotlight,
                lastHome: StartScreen = .spotlight,
                introAnimation: Bool = true,
                viewButtonSwitches: Bool = true,
                interfaceSounds: Bool = true,
                soundVolume: Double = 0.6,
                quietLaunch: Bool = true,
                wallpaperID: String? = nil,
                backgroundSizing: BackgroundSizing = .fill,
                animatedBackground: Bool = true,
                launchStyle: LaunchStyle = .artAndLogo,
                launchMotion: Bool = true,
                launchShade: LaunchShade = .soft) {
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
        self.spotlightCards = spotlightCards
        self.spotlightOrder = spotlightOrder
        self.startingTab = startingTab
        self.surprisePool = surprisePool
        self.cloudSaves = cloudSaves
        self.cloudSavesPickedFolder = cloudSavesPickedFolder
        self.startOn = startOn
        self.lastHome = lastHome
        self.introAnimation = introAnimation
        self.viewButtonSwitches = viewButtonSwitches
        self.interfaceSounds = interfaceSounds
        self.soundVolume = soundVolume
        self.quietLaunch = quietLaunch
        self.wallpaperID = wallpaperID
        self.backgroundSizing = backgroundSizing
        self.animatedBackground = animatedBackground
        self.launchStyle = launchStyle
        self.launchMotion = launchMotion
        self.launchShade = launchShade
    }

    enum CodingKeys: String, CodingKey {
        case backgroundShade, readableText, reduceMotion, showButtonHints, showClock
        case restoreLastGame, checkEngineAtLaunch, refreshLibraryAtLaunch, lastSelectedGameID
        case steamGridDbApiKey, gameDefaults, colorThemeID, buttonNames
        case spotlightCards, spotlightOrder, startingTab, surprisePool, cloudSaves, cloudSavesPickedFolder
        case startOn, lastHome
        case introAnimation, viewButtonSwitches, interfaceSounds, soundVolume, quietLaunch
        case wallpaperID, backgroundSizing, animatedBackground, launchStyle, launchMotion, launchShade
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
        self.spotlightCards = try container.decodeIfPresent([SpotlightCard].self, forKey: .spotlightCards) ?? [.surprise, .activity, .addGame]
        self.spotlightOrder = try container.decodeIfPresent([String].self, forKey: .spotlightOrder) ?? []
        self.startingTab = try container.decodeIfPresent(String.self, forKey: .startingTab) ?? "All games"
        self.surprisePool = try container.decodeIfPresent(SurprisePool.self, forKey: .surprisePool) ?? .installed
        self.cloudSaves = try container.decodeIfPresent(CloudSaves.self, forKey: .cloudSaves) ?? .off
        self.cloudSavesPickedFolder = try container.decodeIfPresent(String.self, forKey: .cloudSavesPickedFolder) ?? ""
        self.startOn = try container.decodeIfPresent(StartScreen.self, forKey: .startOn) ?? .spotlight
        self.lastHome = try container.decodeIfPresent(StartScreen.self, forKey: .lastHome) ?? .spotlight
        self.introAnimation = try container.decodeIfPresent(Bool.self, forKey: .introAnimation) ?? true
        self.viewButtonSwitches = try container.decodeIfPresent(Bool.self, forKey: .viewButtonSwitches) ?? true
        self.interfaceSounds = try container.decodeIfPresent(Bool.self, forKey: .interfaceSounds) ?? true
        self.soundVolume = try container.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.6
        self.quietLaunch = try container.decodeIfPresent(Bool.self, forKey: .quietLaunch) ?? true
        self.wallpaperID = try container.decodeIfPresent(String.self, forKey: .wallpaperID)
        self.backgroundSizing = try container.decodeIfPresent(BackgroundSizing.self, forKey: .backgroundSizing) ?? .fill
        self.animatedBackground = try container.decodeIfPresent(Bool.self, forKey: .animatedBackground) ?? true
        self.launchStyle = try container.decodeIfPresent(LaunchStyle.self, forKey: .launchStyle) ?? .artAndLogo
        self.launchMotion = try container.decodeIfPresent(Bool.self, forKey: .launchMotion) ?? true
        self.launchShade = try container.decodeIfPresent(LaunchShade.self, forKey: .launchShade) ?? .soft
    }
}
