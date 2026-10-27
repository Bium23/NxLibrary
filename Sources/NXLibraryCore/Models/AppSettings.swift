import Foundation

public enum BackgroundShade: String, Codable, CaseIterable, Identifiable, Equatable {
    case light, balanced, deep

    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }

    public var heroScrimOpacity: Double {
        switch self {
        case .light: return 0.55
        case .balanced: return 0.72
        case .deep: return 0.86
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
    public var gameDefaults: GameRuntimeConfig

    public init(backgroundShade: BackgroundShade = .balanced,
                readableText: Bool = true,
                reduceMotion: Bool = false,
                showButtonHints: Bool = true,
                showClock: Bool = true,
                restoreLastGame: Bool = true,
                checkEngineAtLaunch: Bool = true,
                refreshLibraryAtLaunch: Bool = true,
                lastSelectedGameID: UUID? = nil,
                gameDefaults: GameRuntimeConfig = GameRuntimeConfig()) {
        self.backgroundShade = backgroundShade
        self.readableText = readableText
        self.reduceMotion = reduceMotion
        self.showButtonHints = showButtonHints
        self.showClock = showClock
        self.restoreLastGame = restoreLastGame
        self.checkEngineAtLaunch = checkEngineAtLaunch
        self.refreshLibraryAtLaunch = refreshLibraryAtLaunch
        self.lastSelectedGameID = lastSelectedGameID
        self.gameDefaults = gameDefaults
    }
}
