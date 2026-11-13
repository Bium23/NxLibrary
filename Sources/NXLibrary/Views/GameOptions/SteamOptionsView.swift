import SwiftUI
import AppKit
import NXLibraryCore

/// A Steam game's Options, in Game options' look and input: the same dimmed screen,
/// centred column, glass rows and hints. Rows and copy come from `SteamOptionsPresentation`;
/// Edit details opens the shared Change artwork and Change metadata panels on the Steam
/// game's own picks. Every row acts on the record it was opened for, re-read from the catalog.
///
/// Input: Up/Down move (clamped), A activates, B (or Esc) leaves Edit details, then closes;
/// X and Menu close. A click activates; a click on the dimmed area steps back.
struct SteamOptionsView: View {
    @ObservedObject var viewModel: AppViewModel
    let game: CatalogGame
    let origin: GameOptionsOrigin
    let onClose: () -> Void
    let onMove: () -> Void

    @ObservedObject private var player = SteamPlayCoordinator.shared
    @State private var level: GameOptionsLevel = .main
    @State private var pickedRow: GameOptionsRow?
    @State private var artworkOpen = false
    @State private var metadataOpen = false
    @State private var keyMonitor: Any?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    /// The record as the catalog holds it now: Favorite and Hidden change it while open.
    private var current: CatalogGame {
        viewModel.catalogGames.first { $0.id == game.id } ?? game
    }

    private var application: CatalogNativeApplication? {
        current.steamGame?.installations.first { $0.availability == .available }?.primaryApplication
    }

    private var presentation: SteamOptionsPresentation {
        SteamOptionsPresentation(canPlay: player.canPlay(current), hasApp: application != nil)
    }

    private var rows: [GameOptionsRow] { presentation.focusableRows(level: level, origin: origin) }

    private var focusedRow: GameOptionsRow? {
        let rows = self.rows
        return GameOptionsFocus(row: pickedRow, in: rows).row(in: rows)
    }

    private var panelOpen: Bool { artworkOpen || metadataOpen }

    var body: some View {
        let p = presentation
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { back() }

            VStack(spacing: 0) {
                column(p)
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"))], right: [HintItem(.a, L10n.text("Select"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(panelOpen ? 0 : 1)
            .allowsHitTesting(!panelOpen)

            if artworkOpen {
                ChangeArtworkView(viewModel: viewModel, subject: PersonalizationSubject(steam: current)) { artworkOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }
            if metadataOpen {
                ChangeMetadataView(viewModel: viewModel, subject: PersonalizationSubject(steam: current)) { metadataOpen = false }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: panelOpen)
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .task(id: game.id) {
            // Change metadata's Automatic is the store's text; ask for it before the panel opens.
            await SteamGameFacts.shared.load(current, language: L10n.context.language)
        }
    }

    private func column(_ p: SteamOptionsPresentation) -> some View {
        let focused = focusedRow
        return VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("GAME OPTIONS"))
                .seleneFont(15, .semibold)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(8))
            Text(current.name)
                .seleneFont(40)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(6))
                .padding(.bottom, canvas.u(14))
            VStack(spacing: canvas.u(8)) {
                ForEach(Array(p.entries(level: level, origin: origin).enumerated()), id: \.offset) { _, entry in
                    entryView(entry, p, focused: focused)
                }
            }
            .padding(.top, canvas.u(6))
            .id(level)
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(90))
        .padding(.bottom, canvas.u(110))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func entryView(_ entry: GameOptionsEntry, _ p: SteamOptionsPresentation, focused: GameOptionsRow?) -> some View {
        switch entry {
        case .row(let row):
            SeleneOptionRow(icon: row.icon, title: row.title, about: p.about(row), focused: focused == row,
                            destructive: false, enabled: !p.isDimmed(row)) {
                trailing(row)
            }
            .contentShape(Rectangle())
            .onTapGesture { activate(row) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title)
            .accessibilityHint(p.about(row) ?? "")
            .accessibilityValue(row.isToggle ? (toggleValue(row) ? "On" : "Off") : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate(row) }
        case .heading(let text):
            Text(L10n.text(text))
                .seleneFont(17, .semibold)
                .foregroundColor(SeleneTheme.ink75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, canvas.u(26))
                .padding(.top, canvas.u(16))
        case .note, .gap:
            EmptyView()
        }
    }

    @ViewBuilder
    private func trailing(_ row: GameOptionsRow) -> some View {
        if row.isToggle {
            SeleneSwitch(isOn: .constant(toggleValue(row))).allowsHitTesting(false)
        } else if row.opensSubmenu {
            MaterialIconView(.chevron, size: 24).foregroundColor(SeleneTheme.ink60)
        } else {
            EmptyView()
        }
    }

    private func toggleValue(_ row: GameOptionsRow) -> Bool {
        switch row {
        case .favorite: return current.isFavorite
        case .hidden: return current.isHidden
        default: return false
        }
    }

    // MARK: - Actions

    private func activate(_ row: GameOptionsRow) {
        pickedRow = row
        perform(row)
    }

    private func perform(_ row: GameOptionsRow) {
        let game = current
        switch row {
        case .play:
            guard presentation.canPlay else { SoundEffectService.shared.play(.error); return }
            SoundEffectService.shared.play(.click)
            onClose()
            SteamPlayCoordinator.shared.press(game)
        case .editDetails:
            SoundEffectService.shared.play(.click)
            pickedRow = presentation.focusableRows(level: .editDetails, origin: origin).first
            level = .editDetails
        case .move:
            SoundEffectService.shared.play(.click)
            onMove()
        case .favorite:
            SoundEffectService.shared.play(.click)
            viewModel.setCatalogFavorite(game)
        case .hidden:
            SoundEffectService.shared.play(.click)
            let hiding = !game.isHidden
            // Close only once the hidden flag is saved: a failed save leaves the game listed.
            if viewModel.setCatalogHidden(hiding, game: game), hiding { onClose() }
        case .showInFinder:
            guard let application else { SoundEffectService.shared.play(.error); return }
            SoundEffectService.shared.play(.click)
            viewModel.revealInFinder(url: application.url)
        case .changeArtwork:
            SoundEffectService.shared.play(.click)
            artworkOpen = true
        case .changeMetadata:
            SoundEffectService.shared.play(.click)
            metadataOpen = true
        case .storePage:
            guard let appID = game.steamGame?.appID, let url = URL(string: "https://store.steampowered.com/app/\(appID)/") else { return }
            SoundEffectService.shared.play(.click)
            viewModel.openURL(url)
        default:
            break
        }
    }

    // MARK: - Input

    private func moveFocus(by delta: Int) {
        let rows = self.rows
        let previous = focusedRow
        var focus = GameOptionsFocus(row: pickedRow, in: rows)
        focus.move(by: delta, count: rows.count)
        pickedRow = focus.row(in: rows)
        if focusedRow != previous { SoundEffectService.shared.play(.focus) }
    }

    private func back() {
        guard !panelOpen else { return }
        if level == .editDetails {
            level = .main
            pickedRow = .editDetails
            SoundEffectService.shared.play(.focus)
        } else {
            onClose()
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        // Change artwork and Change metadata read the same notifications while open.
        guard !panelOpen else { return }
        switch action {
        case .navigateUp: moveFocus(by: -1)
        case .navigateDown: moveFocus(by: 1)
        case .confirm: if let row = focusedRow { perform(row) }
        case .cancel: back()
        case .secondaryAction, .menu: onClose()
        default: break
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.optionsGameID == game.id,
                  !viewModel.isUpdateOfferOpen,
                  !NativeMenuCommands.shared.isTracking,
                  !panelOpen,
                  viewModel.alertMessage == nil, viewModel.settingsNotice == nil,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 126: moveFocus(by: -1)
            case 125: moveFocus(by: 1)
            case 36, 76, 49: if let row = focusedRow { perform(row) }
            case 53: back()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
