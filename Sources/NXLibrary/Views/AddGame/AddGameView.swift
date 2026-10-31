import SwiftUI
import AppKit
import NXLibraryCore

/// Add game, in Game options' manner: the home stays behind, blurred and lightly
/// shaded, and a centred column (1040u) holds the step's title and glass rows.
/// It grows out of Spotlight's Add game card (or the porting tile) and rises
/// from the centre otherwise; Reduce motion fades only.
///
/// Input: Up/Down move along the rows (the list follows the focus), Left/Right
/// change a switch or a choice, A runs the row, B (or Esc) steps back: out of a
/// field or a dialog, then a step, then closes. During a porting Esc closes at
/// once and the porting goes on. Nothing in the column takes key focus, so a
/// local monitor maps the keys (as Game options does); the controller arrives
/// through `.nxAddGameGamepadAction`. Files can be dropped anywhere on it.
public struct AddGameView: View {
    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    private let showsHints: Bool
    private let artwork: ArtworkStore?

    @State private var confirmDiscard = false
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    /// The porting step's actions, published by its view.
    @State var actions: [AddGameAction] = []
    @State var actionsStep = 0
    @State private var focusedID: String?
    @State private var keyMonitor: Any?
    @State private var shown = false
    /// The window frame it grows from or shrinks into; nil rises from the centre.
    @State private var anchor: CGRect?
    @State private var closing = false
    @State private var dropTargeted = false
    @FocusState private var editing: String?

    public init(viewModel: AppViewModel, router: AppRouter, artwork: ArtworkStore? = nil, showsHints: Bool = true) {
        self.viewModel = viewModel
        self.router = router
        self.artwork = artwork
        self.showsHints = showsHints
    }

    private var isSelene: Bool { ThemeStore.shared.palette.id == SelenePaletteCatalog.defaultID }

    public var body: some View {
        let rows = rows(for: viewModel.buildWizardStep)
        let focused = focusedRow(in: rows)
        return GeometryReader { geo in
            let frame = geo.frame(in: .global)
            ZStack {
                SeleneTheme.scrim45
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if !confirmDiscard { requestClose() } }
                    .opacity(shown ? 1 : 0)
                VStack(spacing: 0) {
                    column(rows, focused: focused)
                    if showsHints {
                        SeleneHintsBar(left: [HintItem(.b, backLabel)], right: [HintItem(.a, aLabel(focused))],
                                       bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
                            .opacity(confirmDiscard ? 0 : 1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(restScale(in: geo.size), anchor: .center)
                .offset(restOffset(in: frame))
                .opacity(shown ? 1 : 0)
                if confirmDiscard {
                    ZStack {
                        SeleneTheme.scrim45.ignoresSafeArea()
                        SeleneConfirmDialog(title: "Discard selected sources?",
                                            message: "The files on disk are not changed.",
                                            confirmTitle: "Discard",
                                            cancelTitle: "Keep editing",
                                            focus: $confirmFocus,
                                            onCancel: dismissDiscard,
                                            onConfirm: discardAndClose)
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted, perform: drop)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirmDiscard)
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: dropTargeted)
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.buildWizardStep) { step in
            editing = nil
            focusedID = defaultRowID(for: step)
        }
        .onChange(of: viewModel.canAddSelectedGame) { canAdd in
            guard viewModel.buildWizardStep == 1 else { return }
            if canAdd, focusedID == nil || focusedID == "choose" { focusedID = "continue" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxAddGameGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
    }

    // MARK: - Column

    private func column(_ rows: [AddGameRow], focused: AddGameRow?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ADD A GAME")
                .seleneFont(15, .semibold)
                .tracking(1.2)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.leading, canvas.u(8))
            Text(stepTitle)
                .seleneFont(40)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.leading, canvas.u(6))
            stepLine
                .padding(.leading, canvas.u(8))
                .padding(.top, canvas.u(4))
                .padding(.bottom, canvas.u(14))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: canvas.u(8)) {
                        if viewModel.buildWizardStep == 3 {
                            AddGameStepThreeView(viewModel: viewModel, router: router, artwork: artwork,
                                                 onActions: publish)
                                .padding(.bottom, canvas.u(12))
                        }
                        ForEach(rows) { row in
                            AddGameRowView(row: row, focused: row.id == focused?.id && !confirmDiscard,
                                           isSelene: isSelene, editing: $editing)
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { click(row) }
                        }
                    }
                    // The clip would shave the first row's focus border.
                    .padding(.top, canvas.u(6))
                    .padding(.horizontal, canvas.u(4))
                    .padding(.bottom, canvas.u(24))
                }
                .scrollIndicators(.hidden)
                // Rows fade under the title and into the hints instead of being cut.
                .mask(
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: canvas.u(10))
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: canvas.u(28))
                    }
                )
                .onChange(of: focused?.id) { id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : SeleneTheme.quick) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: canvas.u(1040), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, canvas.u(90))
        .padding(.bottom, canvas.u(24))
        .overlay(alignment: .top) {
            if dropTargeted {
                Text("Drop to add these files")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.onFocus)
                    .padding(.horizontal, canvas.u(18))
                    .frame(height: canvas.u(34))
                    .background(Capsule().fill(SeleneTheme.focus))
                    .padding(.top, canvas.u(40))
                    .transition(.opacity)
            }
        }
        // Clicks inside the column are not clicks on the shade; only the area outside closes.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var stepTitle: String {
        switch viewModel.buildWizardStep {
        case 1: return "Choose a game"
        case 2: return viewModel.selectedGame?.name ?? "Review"
        default:
            let id = viewModel.currentBuildGameID ?? viewModel.lastBuildGameID
            return viewModel.libraryGames.first { $0.id == id }?.name ?? "Porting"
        }
    }

    /// "Choose · Review · Porting", the current step in full ink.
    private var stepLine: some View {
        let step = viewModel.buildWizardStep
        return HStack(spacing: canvas.u(10)) {
            ForEach(Array(["Choose", "Review", "Porting"].enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Circle().fill(SeleneTheme.ink25).frame(width: canvas.u(4), height: canvas.u(4))
                }
                Text(title)
                    .seleneFont(15, index + 1 == step ? .semibold : .regular)
                    .foregroundColor(index + 1 == step ? SeleneTheme.ink : SeleneTheme.ink60)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step) of 3")
    }

    // MARK: - Focus

    private func focusedRow(in rows: [AddGameRow]) -> AddGameRow? {
        let focusable = rows.filter(\.focusable)
        if let id = focusedID, let row = focusable.first(where: { $0.id == id }) { return row }
        let preferred = defaultRowID(for: viewModel.buildWizardStep)
        return focusable.first { $0.id == preferred } ?? focusable.first
    }

    private func move(by delta: Int) {
        let focusable = rows(for: viewModel.buildWizardStep).filter(\.focusable)
        guard !focusable.isEmpty else { return }
        let currentID = focusedRow(in: focusable)?.id
        let current = focusable.firstIndex { $0.id == currentID } ?? 0
        let next = min(max(current + delta, 0), focusable.count - 1)
        focusedID = focusable[next].id
        if next != current { SoundEffectService.shared.play(.focus) }
    }

    private func horizontal(by delta: Int) {
        guard let row = focusedRow(in: rows(for: viewModel.buildWizardStep)) else { return }
        switch row.kind {
        case .toggle(let isOn):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            let value = delta > 0
            guard isOn.wrappedValue != value else { return }
            isOn.wrappedValue = value
            SoundEffectService.shared.play(.key)
        case .choice(let values, let index, let select):
            let next = min(max(index + delta, 0), values.count - 1)
            guard next != index else { return }
            select(next)
            SoundEffectService.shared.play(.key)
        default:
            break
        }
    }

    private func activate(_ row: AddGameRow) {
        switch row.kind {
        case .action(let perform):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            SoundEffectService.shared.play(.click)
            // Out of the key event first: an open panel (Choose folder) runs its own loop.
            DispatchQueue.main.async { perform() }
        case .toggle(let isOn):
            guard row.enabled else { return SoundEffectService.shared.play(.error) }
            isOn.wrappedValue.toggle()
            SoundEffectService.shared.play(.key)
        case .choice(let values, let index, let select):
            guard !values.isEmpty else { return }
            select((index + 1) % values.count)
            SoundEffectService.shared.play(.key)
        case .field:
            editing = row.id
            SoundEffectService.shared.play(.click)
        case .warning(let action):
            guard let action else { return }
            SoundEffectService.shared.play(.click)
            action()
        case .heading, .note:
            break
        }
    }

    private func click(_ row: AddGameRow) {
        guard row.focusable, !closing, !confirmDiscard else { return }
        focusedID = row.id
        activate(row)
    }

    private func publish(_ actions: [AddGameAction]) {
        self.actions = actions
        actionsStep = 3
    }

    // MARK: - Hints

    private var backLabel: String {
        if editing != nil { return "Done" }
        if viewModel.isBuilding { return "Hide" }
        return viewModel.buildWizardStep > 1 ? "Back" : "Close"
    }

    private func aLabel(_ row: AddGameRow?) -> String {
        guard let row else { return "Select" }
        switch row.kind {
        case .toggle: return "Switch"
        case .choice: return "Change"
        case .field: return editing == row.id ? "Done" : "Edit"
        case .action: return row.title
        default: return "Select"
        }
    }

    // MARK: - Grow and shrink

    /// Away from rest: toward the anchor tile, or 96% from the centre.
    private func restScale(in size: CGSize) -> CGFloat {
        guard !shown, !reduceMotion else { return 1 }
        guard let anchor, size.width > 0, size.height > 0 else { return 0.96 }
        return max(0.08, min(anchor.width / size.width, anchor.height / size.height) * 2)
    }

    private func restOffset(in frame: CGRect) -> CGSize {
        guard !shown, !reduceMotion, let anchor else { return .zero }
        return CGSize(width: anchor.midX - frame.midX, height: anchor.midY - frame.midY)
    }

    private func appear() {
        installKeyMonitor()
        anchor = HomeAnchors.shared.frame(HomeAnchors.shared.openFrom)
        HomeAnchors.shared.openFrom = nil
        focusedID = defaultRowID(for: viewModel.buildWizardStep)
        shown = false
        closing = false
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.88)) {
                shown = true
            }
        }
    }

    /// Shrinks into the porting tile (or the card it came from), then leaves.
    private func close(then finish: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        editing = nil
        removeKeyMonitor()
        if let id = viewModel.portingGameID {
            router.requestSpotlightSelect(id)
            anchor = HomeAnchors.shared.frame(SpotlightItem.game(id).key)
        }
        let duration = reduceMotion ? 0.18 : 0.3
        withAnimation(.easeIn(duration: duration)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish() }
    }

    // MARK: - Input

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.route == .addGame,
                  !router.isMenuPresented,
                  !closing,
                  viewModel.gameToClose == nil,
                  viewModel.gameToRemove == nil,
                  viewModel.alertMessage == nil,
                  let window = event.window,
                  !window.isSheet,
                  window.attachedSheet == nil,
                  NSApp.modalWindow == nil else { return event }
            // Typing in a field: Return, Tab and Esc end the editing; everything else types.
            if window.firstResponder is NSText {
                guard [36, 76, 48, 53].contains(event.keyCode) else { return event }
                editing = nil
                window.makeFirstResponder(nil)
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            guard modifiers.isEmpty else { return event }
            let action: GamepadAction
            switch event.keyCode {
            case 126: action = .navigateUp
            case 125: action = .navigateDown
            case 123: action = .navigateLeft
            case 124: action = .navigateRight
            case 36, 76, 49: action = .confirm
            case 53: action = .cancel
            default: return event
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
        guard !closing else { return }
        if confirmDiscard {
            switch action {
            case .navigateLeft, .navigateRight:
                let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
                if confirmFocus != next {
                    confirmFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm:
                SoundEffectService.shared.play(.click)
                confirmFocus == .confirm ? discardAndClose() : dismissDiscard()
            case .cancel:
                dismissDiscard()
            default:
                break
            }
            return
        }
        // A controller while a field is being typed in: A or B ends the editing.
        if editing != nil {
            if action == .cancel || action == .confirm {
                editing = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            return
        }
        switch action {
        case .navigateUp: move(by: -1)
        case .navigateDown: move(by: 1)
        case .navigateLeft: horizontal(by: -1)
        case .navigateRight: horizontal(by: 1)
        case .confirm:
            if let row = focusedRow(in: rows(for: viewModel.buildWizardStep)) { activate(row) }
        case .cancel: handleBack()
        default: break
        }
    }

    private func handleBack() {
        if confirmDiscard { return dismissDiscard() }
        if viewModel.isBuilding { return requestClose() }
        if viewModel.buildWizardStep > 1 {
            SoundEffectService.shared.play(.back)
            withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                viewModel.goToWizardStep(viewModel.buildWizardStep - 1)
            }
        } else {
            requestClose()
        }
    }

    private func requestClose() {
        if viewModel.isBuilding {
            // The porting goes on; the column shrinks into its tile.
            close { leave() }
            return
        }
        if viewModel.selectedGameFolder != nil || !viewModel.selectedSources.isEmpty {
            confirmFocus = .cancel
            confirmDiscard = true
            SoundEffectService.shared.play(.alert)
        } else {
            close { leave() }
        }
    }

    private func dismissDiscard() {
        confirmDiscard = false
        confirmFocus = .cancel
    }

    private func leave() {
        viewModel.addGameDidLeave()
        router.back()
    }

    private func discardAndClose() {
        dismissDiscard()
        close {
            viewModel.selectedGameFolder = nil
            viewModel.appName = ""
            viewModel.bundleId = ""
            viewModel.resetWizard()
            leave()
        }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard viewModel.buildWizardStep == 1, !viewModel.isBuilding else { return false }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { urls.append(url); group.leave() } } else { group.leave() }
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { viewModel.handleDroppedURLs(urls) }
        }
        return true
    }
}
