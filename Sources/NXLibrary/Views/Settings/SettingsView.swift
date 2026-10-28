import SwiftUI
import NXLibraryCore

enum SettingsFocusArea { case sidebar, rows }

struct SettingsRowAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    let activate: () -> Void

    init(id: String, title: String, isEnabled: Bool = true, activate: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.activate = activate
    }
}

public struct SettingsView: View {
    private let initialSection: SettingsSection
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var router: AppRouter
    @ObservedObject var artwork: ArtworkStore

    @State private var section: SettingsSection
    @State private var showingControls = false
    @State private var focus = FocusIndex()
    @State private var focusArea: SettingsFocusArea = .sidebar
    @State private var rowFocus = FocusIndex()
    @State private var rowActions: [SettingsRowAction] = []

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
        GeometryReader { geo in
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            VStack(spacing: 0) {
                header(metrics)
                HStack(alignment: .top, spacing: 42) {
                    SettingsSidebar(selection: $section)
                        .frame(width: metrics.sidebarWidth)
                    ScrollView {
                        SettingsSectionContent(
                            section: section,
                            viewModel: viewModel,
                            settings: settings,
                            artwork: artwork,
                            focusedRowTitle: focusArea == .rows ? focusedRowTitle : nil,
                            onViewControls: { showingControls = true },
                            onOpenConsole: { router.openConsole() },
                            onActions: updateActions
                        )
                        .padding(.bottom, 60)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, metrics.margin)
                .padding(.top, 24)
                if settings.settings.showButtonHints {
                    CommandBar([.init("B", "Back"), .init("A", "Select"), .init("Y", "Setup")])
                }
            }
        }
        .background(SeleneTheme.canvas)
        .onMoveCommand(perform: handleMove)
        .onExitCommand(perform: handleBack)
        .onChange(of: section) { value in
            if let index = SettingsSection.allCases.firstIndex(of: value) {
                focus.index = index
            }
            focusArea = .sidebar
            rowActions = []
            rowFocus = FocusIndex()
        }
        .onChange(of: initialSection) { value in
            section = value
        }
        .onAppear {
            if let index = SettingsSection.allCases.firstIndex(of: section) {
                focus.index = index
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSettingsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .sheet(isPresented: $showingControls) { ControlsView() }
    }

    private var focusedRowTitle: String? {
        guard !rowActions.isEmpty else { return nil }
        return rowActions[rowFocus.index].title
    }

    private var focusNote: String {
        if focusArea == .rows, let title = focusedRowTitle { return "Focused: \(title)" }
        return "Sidebar"
    }

    private func header(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Settings")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Everything NX Library needs, in one calm place.")
                    .font(.system(size: 13))
                    .foregroundColor(SeleneTheme.inkMuted)
            }
            Spacer()
            HStack(spacing: 14) {
                Text(focusNote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(focusArea == .rows ? SeleneTheme.accent : SeleneTheme.inkMuted)
                    .lineLimit(1)
                if canResetSection {
                    Button("Reset section") { resetSection() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.inkMuted)
                        .help("Restore the defaults for \(section.title) only.")
                        .accessibilityLabel("Reset \(section.title) section")
                }
                if settings.settings.showClock {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink.opacity(0.8))
                    }
                }
                Button { router.back() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(SeleneTheme.ink.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(SeleneTheme.ink.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 34)
        .padding(.bottom, 22)
    }

    private func updateActions(_ actions: [SettingsRowAction]) {
        rowActions = actions
        rowFocus.move(by: 0, count: actions.count)
    }

    private var canResetSection: Bool {
        switch section {
        case .general, .appearance, .library, .gameDefaults, .controllers: return true
        case .engineKeys, .storageLogs, .about: return false
        }
    }

    private func resetSection() {
        let defaults = AppSettings()
        switch section {
        case .general:
            settings.settings.restoreLastGame = defaults.restoreLastGame
            settings.settings.checkEngineAtLaunch = defaults.checkEngineAtLaunch
            settings.settings.refreshLibraryAtLaunch = defaults.refreshLibraryAtLaunch
        case .appearance:
            settings.settings.backgroundShade = defaults.backgroundShade
            settings.settings.readableText = defaults.readableText
            settings.settings.reduceMotion = defaults.reduceMotion
            settings.settings.showButtonHints = defaults.showButtonHints
            settings.settings.showClock = defaults.showClock
            viewModel.iconAppearanceMode = .auto
        case .library:
            viewModel.libraryFolder = URL(fileURLWithPath: viewModel.defaultInstallPath)
                .appendingPathComponent("Applications")
            viewModel.loadLibrary()
        case .gameDefaults:
            settings.settings.gameDefaults = defaults.gameDefaults
        case .controllers:
            GameControllerService.shared.deadzone = 0.35
            SoundEffectService.shared.volume = 0.28
            SoundEffectService.shared.isSoundEnabled = true
            settings.settings.gameDefaults.rumble = defaults.gameDefaults.rumble
            settings.settings.gameDefaults.rumbleGain = defaults.gameDefaults.rumbleGain
        case .engineKeys, .storageLogs, .about:
            break
        }
        SoundEffectService.shared.play(.focus)
    }

    private func moveFocus(by delta: Int) {
        switch focusArea {
        case .sidebar:
            focus.move(by: delta, count: SettingsSection.allCases.count)
            section = SettingsSection.allCases[focus.index]
        case .rows:
            rowFocus.move(by: delta, count: rowActions.count)
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up: moveFocus(by: -1)
        case .down: moveFocus(by: 1)
        case .left:
            if focusArea == .rows { focusArea = .sidebar }
        case .right:
            if focusArea == .sidebar, !rowActions.isEmpty { focusArea = .rows }
        default:
            break
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        switch action {
        case .navigateUp: moveFocus(by: -1)
        case .navigateDown: moveFocus(by: 1)
        case .navigateLeft:
            if focusArea == .rows { focusArea = .sidebar }
        case .navigateRight:
            if focusArea == .sidebar, !rowActions.isEmpty { focusArea = .rows }
        case .confirm:
            SoundEffectService.shared.play(.click)
            if focusArea == .sidebar {
                focusArea = .rows
            } else if !rowActions.isEmpty {
                let row = rowActions[rowFocus.index]
                if row.isEnabled { row.activate() }
            }
        case .cancel:
            handleBack()
        case .menu:
            router.isMenuPresented = true
        default:
            break
        }
    }

    private func handleBack() {
        if focusArea == .rows {
            focusArea = .sidebar
            SoundEffectService.shared.play(.focus)
        } else {
            router.back()
        }
    }
}
