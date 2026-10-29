import SwiftUI
import AppKit
import NXLibraryCore

enum SettingsFocusArea { case sidebar, rows }

struct SettingsRowAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    /// Value rows step with Left/Right; nil rows hand Left back to the groups.
    let cycle: ((Int) -> Void)?
    let activate: () -> Void

    init(id: String, title: String, isEnabled: Bool = true,
         cycle: ((Int) -> Void)? = nil, activate: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.cycle = cycle
        self.activate = activate
    }

    /// A value row: A steps forward, Left/Right step either way.
    static func value(_ id: String, _ title: String, cycle: @escaping (Int) -> Void) -> SettingsRowAction {
        SettingsRowAction(id: id, title: title, cycle: cycle) { cycle(1) }
    }
}

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
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion
    @Environment(\.seleneCanvas) private var canvas
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
        .background(SeleneBackdrop())
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
        .sheet(isPresented: $showingControls) {
            ControlsView()
        }
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
                .environment(\.seleneFocusedRowTitle, focusArea == .rows ? focusedRowTitle : nil)
                .padding(.bottom, canvas.u(60))
            }
            .scrollIndicators(.hidden)
            .onChange(of: rowFocus.index) { _ in
                guard focusArea == .rows,
                      rowActions.indices.contains(rowFocus.index) else { return }
                let id = "selene-row-\(rowActions[rowFocus.index].title)"
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

    private var focusedRowTitle: String? { focusedRow?.title }

    private func updateActions(_ actions: [SettingsRowAction]) {
        // One focus slot per visible row. Secondary buttons in a row stay
        // pointer-reachable; the controller uses the row's primary action.
        var seen = Set<String>()
        rowActions = actions.filter { seen.insert($0.title).inserted }
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
        switch section {
        case .startUp:
            settings.settings.startOn = defaults.startOn
            settings.settings.restoreLastGame = defaults.restoreLastGame
            settings.settings.checkEngineAtLaunch = defaults.checkEngineAtLaunch
            settings.settings.refreshLibraryAtLaunch = defaults.refreshLibraryAtLaunch
            settings.settings.introAnimation = defaults.introAnimation
        case .navigation:
            settings.settings.showButtonHints = defaults.showButtonHints
            settings.settings.buttonNames = defaults.buttonNames
            settings.settings.viewButtonSwitches = defaults.viewButtonSwitches
        case .spotlight:
            settings.settings.spotlightCards = defaults.spotlightCards
            settings.settings.startingTab = defaults.startingTab
            settings.settings.spotlightOrder = defaults.spotlightOrder
        case .soundMusic:
            settings.settings.interfaceSounds = defaults.interfaceSounds
            settings.settings.soundVolume = defaults.soundVolume
            settings.settings.quietLaunch = defaults.quietLaunch
        case .look:
            settings.settings.colorThemeID = defaults.colorThemeID
            ThemeStore.shared.apply(id: defaults.colorThemeID)
            settings.settings.wallpaperID = defaults.wallpaperID
            settings.settings.backgroundSizing = defaults.backgroundSizing
            settings.settings.backgroundShade = defaults.backgroundShade
            settings.settings.readableText = defaults.readableText
            settings.settings.animatedBackground = defaults.animatedBackground
            settings.settings.showClock = defaults.showClock
            settings.settings.reduceMotion = defaults.reduceMotion
            viewModel.iconAppearanceMode = .auto
        case .games:
            settings.settings.launchStyle = defaults.launchStyle
            settings.settings.launchMotion = defaults.launchMotion
            settings.settings.launchShade = defaults.launchShade
            settings.settings.surprisePool = defaults.surprisePool
            let rumble = settings.settings.gameDefaults.rumble
            let gain = settings.settings.gameDefaults.rumbleGain
            settings.settings.gameDefaults = defaults.gameDefaults
            // Rumble lives under Controllers.
            settings.settings.gameDefaults.rumble = rumble
            settings.settings.gameDefaults.rumbleGain = gain
        case .controllers:
            GameControllerService.shared.deadzone = 0.35
            settings.settings.gameDefaults.rumble = defaults.gameDefaults.rumble
            settings.settings.gameDefaults.rumbleGain = defaults.gameDefaults.rumbleGain
        case .library:
            viewModel.libraryFolder = URL(fileURLWithPath: viewModel.defaultInstallPath)
                .appendingPathComponent("Applications")
            viewModel.loadLibrary()
        case .search, .changed, .engine, .storage, .about:
            break
        }
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
                  !router.isMenuPresented,
                  !showingControls,
                  viewModel.alertMessage == nil,
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
