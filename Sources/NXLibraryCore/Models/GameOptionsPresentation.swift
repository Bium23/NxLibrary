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
    case fullscreen, fps60, frameRate, metalFX, gameUpscaler, metalHUD, consoleMode, language, rumble, rumbleStrength
    case renderScale, moreSettings, restoreDefaults
    case cheats, mods, rebuild, showInFinder, openSaves, editDetails, removeGame
    case changeArtwork, changeMetadata, storePage, attachSources, openLog, removeSources

    public var title: String {
        switch self {
        case .play: return "Play"
        case .move: return "Move"
        case .favorite: return "Favorite"
        case .hidden: return "Hidden"
        case .fullscreen: return "Fullscreen"
        case .fps60: return "60 FPS"
        case .frameRate: return "Frame rate"
        case .gameUpscaler: return "Game's upscaler"
        case .moreSettings: return "More settings"
        case .metalFX: return "MetalFX upscaling"
        case .metalHUD: return "Metal HUD"
        case .consoleMode: return "Console mode"
        case .language: return "Game language"
        case .rumble: return "Rumble"
        case .rumbleStrength: return "Rumble strength"
        case .renderScale: return "3D render scale"
        case .restoreDefaults: return "Use new game defaults"
        case .cheats: return "Cheats"
        case .mods: return "Mods"
        case .rebuild: return "Rebuild"
        case .showInFinder: return "Show in Finder"
        case .openSaves: return "Saves"
        case .editDetails: return "Edit details"
        case .removeGame: return "Remove game"
        case .changeArtwork: return "Change artwork"
        case .changeMetadata: return "Change metadata"
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
        case .fps60, .frameRate: return .sync
        case .gameUpscaler: return .tune
        case .moreSettings: return .settings
        case .metalFX: return .tune
        case .metalHUD: return .timeline
        case .consoleMode: return .gamepad
        case .language: return .language
        case .rumble, .rumbleStrength: return .volume
        case .renderScale: return .tune
        case .restoreDefaults: return .restore
        case .cheats: return .casino
        case .mods: return .puzzle
        case .rebuild: return .build
        case .showInFinder: return .folder
        case .openSaves: return .save
        case .editDetails: return .edit
        case .removeGame, .removeSources: return .delete
        case .changeArtwork: return .image
        case .changeMetadata: return .edit
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
        case .consoleMode, .language, .rumbleStrength, .renderScale, .frameRate, .gameUpscaler: return true
        default: return false
        }
    }

    /// Opens a sub-list (chevron).
    public var opensSubmenu: Bool {
        [.editDetails, .changeArtwork, .changeMetadata, .cheats, .mods, .openSaves, .moreSettings].contains(self)
    }

    /// The engine setting a row shows, for a build with saved choices.
    public var settingKey: String? {
        switch self {
        case .fullscreen: return "DM_FULLSCREEN"
        case .fps60, .frameRate: return "DM_FPS_TARGET"
        case .metalFX: return "DM_PRESENT_UPSCALE"
        case .gameUpscaler: return "DM_UPSCALER"
        case .metalHUD: return "DM_METAL_HUD"
        case .consoleMode: return "DM_OPMODE"
        case .language: return "DM_LANG"
        case .rumble: return "DM_RUMBLE"
        case .rumbleStrength: return "DM_RUMBLE_GAIN"
        case .renderScale: return "DM_RENDER_SCALE"
        default: return nil
        }
    }

    /// A switch row's "on" value when the build lists the setting as a choice (Display mode, Upscaling).
    public var onValue: String {
        self == .metalFX ? "metalfx" : "1"
    }

    /// The setting rows of the main list, in order, for a build with saved choices.
    public static let settingRows: [GameOptionsRow] = [
        .fullscreen, .frameRate, .metalFX, .gameUpscaler, .metalHUD, .consoleMode, .language,
        .rumble, .rumbleStrength, .renderScale,
    ]

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
    /// What the gate says about the refusal (ToolchainGateCopy.Summary.buildHint); nil keeps the generic line.
    public let toolchainHint: String?
    public let hasStorePage: Bool
    public let gameName: String
    public let appPath: String
    public let canDeleteBundle: Bool
    public let resolutionNote: String
    /// The Cheats row's value (CheatStatus.rowValue).
    public let cheatsValue: String
    /// The Mods row's value (ModStore.rowValue).
    public let modsValue: String
    /// The build's settings, for a build with saved choices; nil keeps the fixed rows of older builds.
    public let settings: GameSettingsSnapshot?

    public init(supportsRenderScale: Bool, isPlayable: Bool, sourcesDetached: Bool,
                toolchainBlocked: Bool = false, toolchainHint: String? = nil, hasStorePage: Bool = false,
                gameName: String = "", appPath: String = "", canDeleteBundle: Bool = false,
                cheatsValue: String = "None", modsValue: String = "None", settings: GameSettingsSnapshot? = nil) {
        self.cheatsValue = cheatsValue
        self.modsValue = modsValue
        self.settings = settings
        self.showRenderScale = supportsRenderScale
        self.canPlay = isPlayable
        self.sourcesDetached = sourcesDetached
        self.toolchainBlocked = toolchainBlocked
        self.toolchainHint = toolchainHint.flatMap { $0.isEmpty ? nil : $0 }
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
        if sourcesDetached { return "Game files are missing or not attached. Attach sources in Edit details." }
        if toolchainBlocked { return toolchainHint.map { $0 + "." } ?? "Blocked by the Metal gate. See Settings → Engine." }
        return "Build a new app; the old app stays if the build fails."
    }

    public var attachAbout: String {
        sourcesDetached
            ? "Game files are missing or not attached. Attach them to rebuild."
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
        if isFixed(row) { return true }
        switch row {
        case .play: return !canPlay
        case .rebuild: return rebuildDimmed
        default: return false
        }
    }

    /// A row whose setting the player's env.txt sets: shown, not changeable, as the engine's own window does.
    public func isFixed(_ row: GameOptionsRow) -> Bool {
        guard let settings, let key = row.settingKey else { return false }
        return settings.fixed.contains(key)
    }

    /// The row's one-line description, when it has one.
    public func about(_ row: GameOptionsRow) -> String? {
        if isFixed(row) { return "Set in env.txt" }
        switch row {
        case .play: return "Launch the installed Mac app."
        case .cheats: return "Install and switch this game's cheats."
        case .mods: return "Turn this game's file mods on and off, and choose which one wins."
        case .move: return "Change its place on Spotlight."
        case .favorite: return "On your Favorites tab."
        case .hidden: return "Hidden games stay out of your lists."
        case .fullscreen: return "Launch mode"
        case .fps60, .frameRate: return "Frame-rate target"
        case .gameUpscaler: return "The game's own 3D upscaler, or MetalFX instead"
        case .moreSettings: return "Other settings this build offers."
        case .metalFX: return "Sharper scaling of the whole picture to your screen"
        case .metalHUD: return "Performance overlay"
        case .consoleMode: return "Console profile"
        case .language: return "Game language"
        case .rumble: return "Controller vibration"
        case .rumbleStrength: return "Vibration strength"
        case .renderScale: return "Internal resolution"
        case .restoreDefaults: return "Copy current defaults"
        case .rebuild: return rebuildAbout
        case .showInFinder: return "Reveal the app in Finder."
        case .openSaves: return "Back up, import and restore progress."
        case .editDetails: return "Artwork, metadata, store page, sources and the build log."
        case .removeGame: return removal.message
        case .changeArtwork: return "Cover, background, icon and logo, from GameTDB, Title DB or a file."
        case .changeMetadata: return "Description, genres, developer, publisher and release date."
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
            return "On targets 60 FPS; Off targets 30 FPS. Some games run too fast at 60 FPS."
        case .metalFX:
            return "Enlarges the game's finished picture, menus and HUD included, to your window or screen with Apple's MetalFX instead of smooth scaling: sharper edges and text, for a little more GPU time. Nothing changes when the picture is already as large as the screen. Not the same as Game's upscaler. (DM_PRESENT_UPSCALE)"
        case .gameUpscaler:
            return "Some Switch 2 games, such as Donkey Kong Bananza, enlarge their 3D picture inside the frame with an upscaler of their own before drawing the HUD. Game's own keeps it; MetalFX does the same step with Apple's scaler in a fraction of the GPU time, with Apple's look instead of the game's. MetalFX upscaling is a later step: it enlarges the finished picture to your screen. Both can be on. (DM_UPSCALER)"
        case .metalHUD:
            return "Displays Apple's real-time Metal developer HUD (DM_METAL_HUD=1). Shows frame rate, frame pacing graphs, GPU time per frame in milliseconds, and memory allocation."
        case .consoleMode:
            return "Docked uses the game's TV profile; Handheld uses its portable profile."
        case .renderScale:
            return "Scales internal 3D scene resolution from 50% to 100% (DM_RENDER_SCALE). Decreasing internal resolution boosts framerates on demanding titles while UI overlays remain crisp."
        case .restoreDefaults:
            return "Copies your defaults for new games once. Later changes to those defaults leave this game unchanged."
        case .removeSources:
            return "Frees disk space by deleting original NSP/XCI dump files and the compilation cache workspace. The installed game app and all your save files are completely safe."
        default:
            return nil
        }
    }

    /// The rows of one level, in display order, with headings and notes between them.
    public func entries(level: GameOptionsLevel, origin: GameOptionsOrigin) -> [GameOptionsEntry] {
        switch level {
        case .main:
            var entries: [GameOptionsEntry] = [.row(.play), .row(.editDetails), .row(.cheats), .row(.mods), .row(.openSaves)]
            if origin == .spotlight { entries.append(.row(.move)) }
            entries += [.row(.favorite), .row(.hidden), .heading("Next launch")]
            if let settings {
                entries += GameOptionsRow.settingRows
                    .filter { $0.settingKey.map(settings.visible) ?? false }
                    .map(GameOptionsEntry.row)
                if !settings.isOffered("DM_RENDER_SCALE") {
                    entries.append(.note(title: "Internal resolution", text: resolutionNote))
                }
                if !settings.extraSettings.isEmpty { entries.append(.row(.moreSettings)) }
            } else {
                entries += [.fullscreen, .fps60, .metalFX, .metalHUD, .consoleMode, .language, .rumble, .rumbleStrength]
                    .map(GameOptionsEntry.row)
                if showRenderScale {
                    entries.append(.row(.renderScale))
                } else {
                    entries.append(.note(title: "Internal resolution", text: resolutionNote))
                }
            }
            entries += [.row(.restoreDefaults), .row(.rebuild), .row(.showInFinder),
                        .gap, .row(.removeGame)]
            return entries
        case .editDetails:
            var entries: [GameOptionsEntry] = [.heading("Edit details"), .row(.changeArtwork), .row(.changeMetadata)]
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

extension GameSettingsSnapshot {
    /// The settings the build offers that no main-list row shows, for More settings, in the build's order.
    public var extraSettings: [LauncherSetting] {
        let shown = Set(GameOptionsRow.settingRows.compactMap(\.settingKey))
        return settings.filter { !shown.contains($0.env) }
    }
}

/// Labels and steps for a setting drawn from the build's list.
public enum GameSettingValues {
    /// A choice's option label, On / Off for a toggle, a percentage for a range (as the engine's window shows it).
    public static func label(_ setting: LauncherSetting, _ value: String) -> String {
        switch setting.kind {
        case "toggle": return value == setting.on ? "On" : "Off"
        case "range":
            guard let x = LauncherSetting.number(value) else { return value }
            return "\(Int((x * 100).rounded()))%"
        default: return setting.options?.first { $0.value == value }?.label ?? value
        }
    }

    /// The next value in the direction, wrapping at the ends as the other value rows do.
    public static func stepped(_ setting: LauncherSetting, from value: String, by delta: Int) -> String {
        switch setting.kind {
        case "toggle":
            return value == setting.on ? (setting.off ?? value) : (setting.on ?? value)
        case "range":
            guard let min = setting.min, let max = setting.max, max >= min else { return value }
            let step = (setting.step ?? 0.1) > 0 ? (setting.step ?? 0.1) : 0.1
            let count = Int(((max - min) / step).rounded())
            let stops = (0...count).map { Swift.min(max, min + Double($0) * step) }
            let x = LauncherSetting.number(value) ?? setting.defaultValue.flatMap(LauncherSetting.number) ?? min
            let next = delta > 0
                ? (stops.first { $0 > x + 1e-9 } ?? stops[0])
                : (stops.last { $0 < x - 1e-9 } ?? stops[stops.count - 1])
            return LauncherSetting.rangeString(next)
        default:
            let options = setting.options ?? []
            guard !options.isEmpty else { return value }
            let index = options.firstIndex { $0.value == value }
            return options[GameOptionsValues.steppedIndex(index, by: delta, count: options.count)].value
        }
    }
}
