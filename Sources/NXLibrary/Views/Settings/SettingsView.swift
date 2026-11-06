import SwiftUI
import AppKit
import NXLibraryCore

enum SettingsFocusArea { case sidebar, rows }

/// Selene's settings screen (`SettingsScreen.cs`): groups on the left, the group's rows on the right.
public struct SettingsView: View {
    private let initialSection: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var router: AppRouter
    @ObservedObject var artwork: ArtworkStore

    @State private var section: SettingsSection
    @State private var showingControls = false
    @State private var focusArea: SettingsFocusArea = .sidebar
    @State private var rowFocus = FocusIndex()
    @State private var rowActions: [SettingsRowAction] = []
    @State private var keyMonitor: Any?
    @State private var resetNotice: String?
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneBackdropStyle) private var appBackdropStyle

    /// The app's backdrop with the Settings wallpaper (Settings → Look), which may be the app's own.
    private var settingsBackdropStyle: SeleneBackdropStyle {
        var style = appBackdropStyle
        let id = WallpaperCatalog.settingsWallpaper(settingsID: settings.settings.settingsWallpaperID,
                                                    appID: settings.settings.wallpaperID)
        style.wallpaperURL = theme.wallpaper(for: id)?.url
        return style
    }
    /// A palette change redraws the whole screen; selection and focus live here and survive it.
    @ObservedObject private var theme = ThemeStore.shared

    public init(initialSection: SettingsSection,
                viewModel: AppViewModel,
                settings: AppSettingsStore,
                router: AppRouter,
                artwork: ArtworkStore) {
        self.initialSection = initialSection
        self.viewModel = viewModel
        self.settings = settings
        self.router = router
        self.artwork = artwork
        _section = State(initialValue: initialSection)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: canvas.u(24)) {
                SettingsSidebar(selection: $section, isFocused: focusArea == .sidebar)
                    .frame(width: canvas.u(400))
                content
            }
            .padding(.horizontal, canvas.u(120))
            .padding(.top, canvas.u(110))
            .frame(maxHeight: .infinity, alignment: .top)
            SeleneHintsBar(right: commandHints)
        }
        .id(theme.palette.id)
        .overlay(alignment: .bottom) {
            if let resetNotice {
                SeleneSuccessNotice(title: "Group reset", message: resetNotice)
                    .padding(.bottom, canvas.u(100))
                    .allowsHitTesting(false)
            }
        }
        .task(id: resetNotice) {
            guard resetNotice != nil else { return }
            do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            withAnimation(reduceMotion ? nil : SeleneTheme.quick) { resetNotice = nil }
        }
        .background(SeleneBackdrop().environment(\.seleneBackdropStyle, settingsBackdropStyle))
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: section) { _ in
            rowActions = []
            rowFocus = FocusIndex()
        }
        .onChange(of: initialSection) { value in
            section = value
            focusArea = .sidebar
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .overlay {
            if viewModel.isEditingSteamGridDBKey {
                SteamGridDBKeyDialog(viewModel: viewModel, gamepad: .nxSettingsGamepadAction) { _ in
                    viewModel.isEditingSteamGridDBKey = false
                }
            }
        }
        .overlay {
            if showingControls {
                ControlsView(canHandleInput: {
                    !router.isMenuPresented && !viewModel.showSetupCheck
                        && !viewModel.isUpdateOfferOpen && !NativeMenuCommands.shared.isTracking
                        && viewModel.settingsNotice == nil && viewModel.gameWithInstallFailure == nil
                }) { showingControls = false }
            }
        }
        .environment(\.seleneMinimumFont, 12)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: canvas.u(8)) {
                    Text(section.title)
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink.opacity(0.55))
                        .padding(.bottom, canvas.u(6))
                    SettingsSectionContent(
                        section: section,
                        viewModel: viewModel,
                        settings: settings,
                        artwork: artwork,
                        onViewControls: { showingControls = true },
                        onOpenConsole: { router.openConsole() },
                        onOpenGroup: openGroup,
                        onSearchSubmit: enterRows,
                        onActions: updateActions
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.seleneFocusedRowID, focusArea == .rows ? focusedRow?.rowID : nil)
                .padding(.bottom, canvas.u(60))
            }
            .scrollIndicators(.hidden)
            .onChange(of: rowFocus.index) { _ in
                guard focusArea == .rows,
                      rowActions.indices.contains(rowFocus.index) else { return }
                let id = "selene-row-\(rowActions[rowFocus.index].rowID)"
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var reduceMotion: Bool {
        settings.settings.reduceMotion || environmentReduceMotion
    }

    private var commandHints: [HintItem] {
        var hints = [HintItem(.b, "Back") { handleBack() }]
        if canResetSection {
            hints.append(HintItem(.x, "Reset group") { resetSection() })
        }
        if focusArea == .sidebar {
            hints.append(HintItem(.a, "Open") { enterRows() })
        } else if focusedRow?.cycle != nil {
            hints.append(HintItem(.a, "Change"))
        } else {
            hints.append(HintItem(.a, "Select"))
        }
        return hints
    }

    private var focusedRow: SettingsRowAction? {
        rowActions.indices.contains(rowFocus.index) ? rowActions[rowFocus.index] : nil
    }

    private func updateActions(_ actions: [SettingsRowAction]) {
        // One focus slot per visible row. Secondary buttons in a row stay
        // pointer-reachable; the controller uses the row's primary action.
        let focusedID = focusedRow?.id
        rowActions = SettingsRowAction.primaryActions(actions)
        if let focusedID, let index = rowActions.firstIndex(where: { $0.id == focusedID }) {
            rowFocus.index = index
        }
        rowFocus.move(by: 0, count: rowActions.count)
        if rowActions.isEmpty, focusArea == .rows { focusArea = .sidebar }
    }

    private func openGroup(_ group: SettingsSection) {
        section = group
        focusArea = .sidebar
        SoundEffectService.shared.play(.click)
    }

    private func enterRows() {
        guard focusArea == .sidebar, !rowActions.isEmpty else { return }
        focusArea = .rows
        SoundEffectService.shared.play(.focus)
    }

    private func leaveRows() {
        focusArea = .sidebar
        SoundEffectService.shared.play(.focus)
    }

    private var canResetSection: Bool {
        switch section {
        case .startUp, .navigation, .spotlight, .soundMusic, .look, .games, .controllers, .library:
            return true
        case .search, .changed, .engine, .storage, .about:
            return false
        }
    }

    private func resetSection() {
        guard canResetSection else { return }
        let defaults = AppSettings()
        var next = settings.settings
        switch section {
        case .startUp:
            next.startOn = defaults.startOn
            next.restoreLastGame = defaults.restoreLastGame
            next.startInFullscreen = defaults.startInFullscreen
            next.checkEngineAtLaunch = defaults.checkEngineAtLaunch
            next.refreshLibraryAtLaunch = defaults.refreshLibraryAtLaunch
            next.checkAppUpdatesAtLaunch = defaults.checkAppUpdatesAtLaunch
            next.introAnimation = defaults.introAnimation
        case .navigation:
            next.showButtonHints = defaults.showButtonHints
            next.buttonNames = defaults.buttonNames
            next.viewButtonSwitches = defaults.viewButtonSwitches
        case .spotlight:
            next.visibleSpotlightCards = defaults.visibleSpotlightCards
            next.startingTab = defaults.startingTab
            next.spotlightOrder = defaults.spotlightOrder
        case .soundMusic:
            next.interfaceSounds = defaults.interfaceSounds
            next.soundVolume = defaults.soundVolume
            next.quietLaunch = defaults.quietLaunch
        case .look:
            next.colorThemeID = defaults.colorThemeID
            ThemeStore.shared.apply(id: defaults.colorThemeID)
            next.wallpaperID = defaults.wallpaperID
            next.settingsWallpaperID = defaults.settingsWallpaperID
            next.keepWallpaperOnGames = defaults.keepWallpaperOnGames
            next.backgroundSizing = defaults.backgroundSizing
            next.wallpaperBrightness = defaults.wallpaperBrightness
            next.backgroundShade = defaults.backgroundShade
            next.readableText = defaults.readableText
            next.animatedBackground = defaults.animatedBackground
            next.showClock = defaults.showClock
            next.reduceMotion = defaults.reduceMotion
            viewModel.iconAppearanceMode = .auto
        case .games:
            resetNotice = "Cloud sync kept"
            next.launchStyle = defaults.launchStyle
            next.launchMotion = defaults.launchMotion
            next.launchShade = defaults.launchShade
            next.surprisePool = defaults.surprisePool
            let rumble = next.gameDefaults.rumble
            let gain = next.gameDefaults.rumbleGain
            next.gameDefaults = defaults.gameDefaults
            // Rumble lives under Controllers.
            next.gameDefaults.rumble = rumble
            next.gameDefaults.rumbleGain = gain
        case .controllers:
            GameControllerService.shared.deadzone = 0.35
            next.gameDefaults.rumble = defaults.gameDefaults.rumble
            next.gameDefaults.rumbleGain = defaults.gameDefaults.rumbleGain
        case .library:
            resetNotice = "Sources folder kept"
            next.notifyPortingEnds = defaults.notifyPortingEnds
            viewModel.libraryFolder = URL(fileURLWithPath: viewModel.defaultInstallPath)
                .appendingPathComponent("Applications")
            viewModel.loadLibrary()
        case .search, .changed, .engine, .storage, .about:
            break
        }
        settings.settings = next
        SoundEffectService.shared.play(.focus)
    }

    private func moveFocus(by delta: Int) {
        switch focusArea {
        case .sidebar:
            let all = SettingsSection.allCases
            section = all.stepped(from: section, delta) ?? section
            SoundEffectService.shared.play(.focus)
        case .rows:
            rowFocus.move(by: delta, count: rowActions.count)
        }
    }

    private func moveSideways(_ delta: Int) {
        switch focusArea {
        case .sidebar:
            if delta > 0 { enterRows() }
        case .rows:
            if let cycle = focusedRow?.cycle, focusedRow?.isEnabled == true {
                cycle(delta)
                SoundEffectService.shared.play(.focus)
            } else if delta < 0 {
                leaveRows()
            }
        }
    }

    /// Arrows, Return/Space, Esc and X, like the other screens' monitors. Typing in a field keeps its keys.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard case .settings = router.route,
                  !viewModel.isUpdateOfferOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !router.isMenuPresented,
                  !viewModel.showSetupCheck,
                  !showingControls, !viewModel.isEditingSteamGridDBKey,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  viewModel.gameWithInstallFailure == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let typing = window.firstResponder is NSText
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125:
                if typing {
                    // Down from the Search field goes to its results.
                    window.makeFirstResponder(nil)
                    enterRows()
                    return nil
                }
                action = .navigateDown
            case 123:
                if typing { return event }
                action = .navigateLeft
            case 124:
                if typing { return event }
                action = .navigateRight
            case 36, 76:
                if typing { return event }
                action = .confirm
            case 49:
                if typing { return event }
                action = .confirm
            case 53:
                if typing { window.makeFirstResponder(nil) }
                action = .cancel
            case 7:                                     // X
                if typing { return event }
                action = .secondaryAction
            default:
                return event
            }
            handleGamepad(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleGamepad(_ action: GamepadAction) {
        // The key dialog takes the controller while it is open.
        if viewModel.isEditingSteamGridDBKey { return }
        if showingControls {
            NotificationCenter.default.post(name: .nxControlsGamepadAction, object: action)
            return
        }
        switch action {
        case .navigateUp: moveFocus(by: -1)
        case .navigateDown: moveFocus(by: 1)
        case .navigateLeft: moveSideways(-1)
        case .navigateRight: moveSideways(1)
        case .confirm:
            if focusArea == .sidebar {
                enterRows()
            } else if let row = focusedRow, row.isEnabled {
                SoundEffectService.shared.play(.click)
                row.activate()
            }
        case .cancel:
            handleBack()
        case .secondaryAction:
            resetSection()
        case .menu:
            router.isMenuPresented = true
        default:
            break
        }
    }

    private func handleBack() {
        if focusArea == .rows {
            leaveRows()
        } else {
            router.back()
        }
    }
}
