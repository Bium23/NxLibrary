import Foundation

/// Where Game options was opened from. Only a Spotlight game gets the Move row.
public enum GameOptionsOrigin: Equatable, Sendable {
    case spotlight
    case collection
    case details
}

/// The two levels of Game options. Edit details opens its own list; B returns to the main one.
public enum GameOptionsLevel: Equatable, Sendable {
    case main
    case editDetails
}

/// Every focusable row of Game options. Headings and notes are not rows (see `GameOptionsEntry`).
public enum GameOptionsRow: String, CaseIterable, Sendable {
    case play, move, favorite, hidden
    case fullscreen, fps60, metalFX, metalHUD, consoleMode, language, rumble, rumbleStrength
    case renderScale, restoreDefaults
    case rebuild, showInFinder, openSaves, editDetails, removeGame
    case changeArtwork, storePage, attachSources, openLog, removeSources

    public var title: String {
        switch self {
        case .play: return "Play"
        case .move: return "Move"
        case .favorite: return "Favorite"
        case .hidden: return "Hidden"
        case .fullscreen: return "Fullscreen"
        case .fps60: return "60 FPS"
        case .metalFX: return "MetalFX"
        case .metalHUD: return "Metal HUD"
        case .consoleMode: return "Console mode"
        case .language: return "Game language"
        case .rumble: return "Rumble"
        case .rumbleStrength: return "Rumble strength"
        case .renderScale: return "3D render scale"
        case .restoreDefaults: return "Restore defaults"
        case .rebuild: return "Rebuild"
        case .showInFinder: return "Show in Finder"
        case .openSaves: return "Open saves"
        case .editDetails: return "Edit details"
        case .removeGame: return "Remove game"
        case .changeArtwork: return "Change artwork"
        case .storePage: return "Store page"
        case .attachSources: return "Attach sources…"
        case .openLog: return "Open log"
        case .removeSources: return "Remove sources & build cache"
        }
    }

    public var icon: MaterialIcon {
        switch self {
        case .play: return .play
        case .move: return .swap
        case .favorite: return .star
        case .hidden: return .hidden
        case .fullscreen: return .monitor
        case .fps60: return .sync
        case .metalFX: return .tune
        case .metalHUD: return .timeline
        case .consoleMode: return .gamepad
        case .language: return .language
        case .rumble, .rumbleStrength: return .volume
        case .renderScale: return .tune
        case .restoreDefaults: return .restore
        case .rebuild: return .build
        case .showInFinder: return .folder
        case .openSaves: return .save
        case .editDetails: return .edit
        case .removeGame, .removeSources: return .delete
        case .changeArtwork: return .image
        case .storePage: return .store
        case .attachSources: return .link
        case .openLog: return .terminal
        }
    }

    /// A switch on the trailing edge: A flips it.
    public var isToggle: Bool {
        switch self {
        case .favorite, .hidden, .fullscreen, .fps60, .metalFX, .metalHUD, .rumble: return true
        default: return false
        }
    }

    /// A value chip on the trailing edge: Left/Right cycle it, A cycles forward.
    public var isChoice: Bool {
        switch self {
        case .consoleMode, .language, .rumbleStrength, .renderScale: return true
        default: return false
        }
    }

    /// Opens a sub-list (chevron).
    public var opensSubmenu: Bool { self == .editDetails || self == .changeArtwork }

    /// Red title, confirmed in a dialog.
    public var isDestructive: Bool { self == .removeGame || self == .removeSources }
}

/// One line of a Game options level, top to bottom.
public enum GameOptionsEntry: Equatable, Sendable {
    case row(GameOptionsRow)
    case heading(String)
    case note(title: String, text: String)
    /// Breathing room before a danger zone.
    case gap
}

/// Copy for the removal confirmation dialog (Remove game).
public struct GameRemovalCopy: Equatable, Sendable {
    public let title: String
    public let confirmTitle: String
    public let message: String
}

public struct GameOptionsPresentation: Equatable {
    public let showRenderScale: Bool
    public let canPlay: Bool
    public let sourcesDetached: Bool
    /// The Metal gate refuses new builds (a known report that does not pass, without the override).
    public let toolchainBlocked: Bool
    public let hasStorePage: Bool
    public let gameName: String
    public let appPath: String
    public let canDeleteBundle: Bool
    public let resolutionNote: String

    public init(supportsRenderScale: Bool, isPlayable: Bool, sourcesDetached: Bool,
                toolchainBlocked: Bool = false, hasStorePage: Bool = false,
                gameName: String = "", appPath: String = "", canDeleteBundle: Bool = false) {
        self.showRenderScale = supportsRenderScale
        self.canPlay = isPlayable
        self.sourcesDetached = sourcesDetached
        self.toolchainBlocked = toolchainBlocked
        self.hasStorePage = hasStorePage
        self.gameName = gameName
        self.appPath = appPath
        self.canDeleteBundle = canDeleteBundle
        self.resolutionNote = "Output follows the window/display. Render scale changes the internal 3D resolution only; native 1440p/4K is not available in this engine pin."
    }

    // MARK: - Derived copy and state

    /// Rebuild's row looks dim when a base source is missing or the Metal gate refuses builds.
    /// Dim rows still take focus; the action explains the refusal itself.
    public var rebuildDimmed: Bool { sourcesDetached || toolchainBlocked }

    /// Says where to fix a dimmed Rebuild: the sources or the Metal gate.
    public var rebuildAbout: String {
        if sourcesDetached { return "A base source is required. Attach sources in Edit details." }
        if toolchainBlocked { return "Blocked by the Metal gate. See Settings → Engine." }
        return "Build a new app; the old app stays if the build fails."
    }

    public var attachAbout: String {
        sourcesDetached
            ? "Sources are detached. Attach them to rebuild."
            : "Sources attached. Rebuild without touching saves."
    }

    public var removal: GameRemovalCopy {
        if canDeleteBundle {
            return GameRemovalCopy(
                title: "Delete \(gameName)?",
                confirmTitle: "Delete",
                message: "This deletes \(appPath). Sources, saves and the build cache are not deleted.")
        }
        return GameRemovalCopy(
            title: "Remove \(gameName)?",
            confirmTitle: "Remove",
            message: "This removes the library record only; \(appPath) stays on disk.")
    }

    /// A row that looks disabled. It still takes focus, and its action explains why it cannot run.
    public func isDimmed(_ row: GameOptionsRow) -> Bool {
        switch row {
        case .play: return !canPlay
        case .rebuild: return rebuildDimmed
        default: return false
        }
    }

    /// The row's one-line description, when it has one.
    public func about(_ row: GameOptionsRow) -> String? {
        switch row {
        case .play: return "Launch the installed Mac app."
        case .move: return "Change its place on Spotlight."
        case .favorite: return "On your Favorites tab."
        case .hidden: return "Hidden games stay out of your lists."
        case .fullscreen: return "Output follows the display resolution."
        case .fps60: return "Unlock the frame limiter when the game supports it."
        case .metalFX: return "Spatial upscaling; it does not raise the internal resolution."
        case .metalHUD: return "Apple's real-time performance overlay."
        case .consoleMode: return "Docked uses the TV profile; handheld uses the portable profile."
        case .language: return "Game Default leaves the engine's language untouched."
        case .rumble: return "Controller vibration when the game supports it."
        case .rumbleStrength: return "Gain from 0 to 3."
        case .renderScale: return "100% keeps the game's own resolution."
        case .restoreDefaults: return "Reset this game's runtime settings."
        case .rebuild: return rebuildAbout
        case .showInFinder: return "Reveal the app in Finder."
        case .openSaves: return "Open the game's save folder."
        case .editDetails: return "Artwork, store page, sources and the build log."
        case .removeGame: return removal.message
        case .changeArtwork: return "Cover, background, icon and logo, from GameTDB, Title DB or a file."
        case .storePage: return "Open the game's Nintendo store page."
        case .attachSources: return attachAbout
        case .openLog: return "Reveal the latest build log."
        case .removeSources: return "Deletes only the source files named in this game and its app-owned workspace. The app and saves stay."
        }
    }

    /// Longer explanation, shown as a tooltip on hover.
    public func info(_ row: GameOptionsRow) -> String? {
        switch row {
        case .fps60:
            return "Overrides the default frame pacing target (DM_PRESENT_HZ=60). Recommended for games that support 60 fps; titles with physics tied to 30 fps ticks may run in fast-forward."
        case .metalFX:
            return "Applies Apple MetalFX spatial upscaling (DM_PRESENT_UPSCALE=metalfx). It sharpens the 3D viewport to match your Mac display without increasing internal render workload."
        case .metalHUD:
            return "Displays Apple's real-time Metal developer HUD (DM_METAL_HUD=1). Shows frame rate, frame pacing graphs, GPU time per frame in milliseconds, and memory allocation."
        case .consoleMode:
            return "Switches the Switch operational profile (DM_OPERATION_MODE). Docked targets higher clock profiles, higher LODs, and up to 1080p, while Handheld mimics the 720p portable mode with lower power draw."
        case .renderScale:
            return "Scales internal 3D scene resolution from 50% to 100% (DM_RENDER_SCALE). Decreasing internal resolution boosts framerates on demanding titles while UI overlays remain crisp."
        case .removeSources:
            return "Frees disk space by deleting original NSP/XCI dump files and the compilation cache workspace. The installed game in ~/Applications and all your save files are completely safe."
        default:
            return nil
        }
    }

    /// The rows of one level, in display order, with headings and notes between them.
    public func entries(level: GameOptionsLevel, origin: GameOptionsOrigin) -> [GameOptionsEntry] {
        switch level {
        case .main:
            var entries: [GameOptionsEntry] = [.row(.play)]
            if origin == .spotlight { entries.append(.row(.move)) }
            entries += [.row(.favorite), .row(.hidden), .heading("Runtime")]
            entries += [.fullscreen, .fps60, .metalFX, .metalHUD, .consoleMode, .language, .rumble, .rumbleStrength]
                .map(GameOptionsEntry.row)
            if showRenderScale {
                entries.append(.row(.renderScale))
            } else {
                entries.append(.note(title: "Internal resolution", text: resolutionNote))
            }
            entries += [.row(.restoreDefaults), .row(.rebuild), .row(.showInFinder), .row(.openSaves),
                        .row(.editDetails), .gap, .row(.removeGame)]
            return entries
        case .editDetails:
            var entries: [GameOptionsEntry] = [.heading("Edit details"), .row(.changeArtwork)]
            if hasStorePage { entries.append(.row(.storePage)) }
            entries += [.row(.attachSources), .row(.openLog), .gap, .row(.removeSources)]
            return entries
        }
    }

    /// The focusable rows of one level, top to bottom.
    public func focusableRows(level: GameOptionsLevel, origin: GameOptionsOrigin) -> [GameOptionsRow] {
        entries(level: level, origin: origin).compactMap { entry in
            if case .row(let row) = entry { return row }
            return nil
        }
    }
}

/// Focus within one level. Movement clamps at the ends; it does not wrap.
/// Focus is found by row identity (`init(row:in:)`), so a row that appears above
/// the focused one (a Store page arriving late) does not move the focus.
public struct GameOptionsFocus: Equatable, Sendable {
    public private(set) var index: Int

    public init(index: Int = 0) {
        self.index = max(0, index)
    }

    /// Focus on `row`'s place in `rows`. A row that is not listed, or none, starts at the top.
    public init(row: GameOptionsRow?, in rows: [GameOptionsRow]) {
        self.index = row.flatMap { rows.firstIndex(of: $0) } ?? 0
    }

    public mutating func move(by delta: Int, count: Int) {
        index = Self.clamped(index + delta, count: count)
    }

    public mutating func focus(_ row: GameOptionsRow, in rows: [GameOptionsRow]) {
        if let found = rows.firstIndex(of: row) { index = found }
    }

    public func row(in rows: [GameOptionsRow]) -> GameOptionsRow? {
        rows.indices.contains(index) ? rows[index] : nil
    }

    public static func clamped(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

/// Values for the choice rows. Left/Right step through them, wrapping at the ends.
public enum GameOptionsValues {
    public static let rumbleStrengthCount = 4
    public static let renderScaleStops = Array(stride(from: 50, through: 100, by: 5))

    public static func consoleModeLabel(docked: Bool) -> String {
        docked ? "Docked" : "Handheld"
    }

    public static func renderScalePercent(_ scale: Double) -> Int {
        Int((scale * 100).rounded())
    }

    public static func renderScaleLabel(_ scale: Double) -> String {
        "\(renderScalePercent(scale))%"
    }

    /// The next 5% stop in the direction, wrapping (100% forward goes to 50%, 50% back to 100%).
    public static func steppedRenderScale(_ scale: Double, by delta: Int) -> Double {
        let percent = renderScalePercent(scale)
        let next: Int
        if delta > 0 {
            next = renderScaleStops.first { $0 > percent } ?? renderScaleStops[0]
        } else {
            next = renderScaleStops.last { $0 < percent } ?? renderScaleStops[renderScaleStops.count - 1]
        }
        return Double(next) / 100
    }

    public static func steppedRumbleStrength(_ gain: Int, by delta: Int) -> Int {
        let count = rumbleStrengthCount
        return ((gain + delta) % count + count) % count
    }

    /// Steps a list index with wrapping. No current index (an unknown value) starts at the first item.
    public static func steppedIndex(_ index: Int?, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        guard let index else { return 0 }
        return ((index + delta) % count + count) % count
    }
}
