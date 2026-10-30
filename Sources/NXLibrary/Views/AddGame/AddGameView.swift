import SwiftUI
import AppKit
import NXLibraryCore

/// Add game: a Selene glass panel (about three quarters of the window) over the
/// blurred home. It grows out of Spotlight's Add game card (or the porting tile)
/// and rises from the centre otherwise; Reduce motion fades only. No close
/// button: B or Esc steps back, out of a dialog, then a step, then closes.
/// During a porting Esc closes at once and the porting goes on; the panel
/// shrinks into the porting tile on the home.
///
/// Input: nothing in the panel takes key focus, so a local monitor maps the
/// arrows, Return/Space and Esc (as Game options does); the controller arrives
/// through `.nxAddGameGamepadAction`.
public struct AddGameView: View {
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @Environment(\.seleneReduceMotion) private var reduceMotion

    private let showsHints: Bool
    private let artwork: ArtworkStore?

    @State private var confirmDiscard = false
    @State private var confirmFocus: SeleneConfirmButton = .cancel
    @State private var stepFocus = FocusIndex()
    @State private var actions: [AddGameAction] = []
    @State private var actionsStep: Int = 0
    @State private var keyMonitor: Any?
    /// The panel is at rest; false while it grows in or shrinks away.
    @State private var shown = false
    /// The window frame it grows from or shrinks into; nil rises from the centre.
    @State private var anchor: CGRect?
    @State private var closing = false

    public init(viewModel: AppViewModel, router: AppRouter, artwork: ArtworkStore? = nil, showsHints: Bool = true) {
        self.viewModel = viewModel
        self.router = router
        self.artwork = artwork
        self.showsHints = showsHints
    }

    public var body: some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            let size = CGSize(width: geo.size.width * 0.75, height: geo.size.height * 0.78)
            ZStack {
                SeleneTheme.scrim45
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { if !confirmDiscard { requestClose() } }
                    .opacity(shown ? 1 : 0)
                panel(size: size)
                    .scaleEffect(restScale(panel: size), anchor: .center)
                    .offset(restOffset(in: frame))
                    .opacity(shown ? 1 : 0)
                if showsHints {
                    VStack {
                        Spacer()
                        SeleneHintsBar(left: [HintItem(.b, backLabel)], right: commandHints)
                    }
                    .opacity(shown && !confirmDiscard ? 1 : 0)
                }
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
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: confirmDiscard)
        .onAppear(perform: appear)
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: viewModel.buildWizardStep) { step in
            stepFocus = FocusIndex(index: defaultFocus(for: step))
        }
        .onChange(of: viewModel.canAddSelectedGame) { canAdd in
            guard viewModel.buildWizardStep == 1 else { return }
            if canAdd, stepFocus.index == 0 {
                stepFocus.index = 2
            } else if !canAdd, stepFocus.index == 2 {
                stepFocus.index = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxAddGameGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
    }

    // MARK: - Panel

    private func panel(size: CGSize) -> some View {
        let radius = canvas.u(28)
        let margin = canvas.u(48)
        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, margin)
                .padding(.top, canvas.u(40))
            AddGameStepBar(step: viewModel.buildWizardStep)
                .padding(.horizontal, margin)
                .padding(.top, canvas.u(22))
            ScrollView {
                Group {
                    switch viewModel.buildWizardStep {
                    case 1:
                        AddGameStepOneView(
                            viewModel: viewModel,
                            focusedAction: stepFocus.index,
                            onActions: updateActions,
                            onClose: requestClose
                        )
                    case 2:
                        AddGameStepTwoView(
                            viewModel: viewModel,
                            router: router,
                            focusedAction: stepFocus.index,
                            onActions: updateActions
                        )
                    default:
                        AddGameStepThreeView(
                            viewModel: viewModel,
                            router: router,
                            artwork: artwork,
                            focusedAction: stepFocus.index,
                            onActions: updateActions
                        )
                    }
                }
                .padding(.horizontal, margin)
                .padding(.top, canvas.u(22))
                .padding(.bottom, canvas.u(40))
            }
            .scrollIndicators(.hidden)
            // The list fades out under the header instead of being cut.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: canvas.u(18))
                    Color.black
                }
            )
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(SeleneTheme.glassCard))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: max(1, canvas.u(1)))
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: canvas.u(40))
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: canvas.u(8)) {
            Text("Add a game")
                .seleneFont(34, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text("Build a native Mac app from your own NSP, XCI or NSZ files.")
                .seleneFont(17)
                .foregroundColor(SeleneTheme.ink60)
        }
    }

    // MARK: - Grow and shrink

    /// Away from rest: the anchor tile's size, or 94% from the centre. Reduce motion fades only.
    private func restScale(panel: CGSize) -> CGFloat {
        guard !shown, !reduceMotion else { return 1 }
        guard let anchor, panel.width > 0, panel.height > 0 else { return 0.94 }
        return max(0.05, min(anchor.width / panel.width, anchor.height / panel.height))
    }

    private func restOffset(in frame: CGRect) -> CGSize {
        guard !shown, !reduceMotion, let anchor else { return .zero }
        return CGSize(width: anchor.midX - frame.midX, height: anchor.midY - frame.midY)
    }

    private func appear() {
        installKeyMonitor()
        anchor = HomeAnchors.shared.frame(HomeAnchors.shared.openFrom)
        HomeAnchors.shared.openFrom = nil
        shown = false
        closing = false
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.86)) {
                shown = true
            }
        }
    }

    /// Shrinks into the porting tile (or the Add card it came from), then leaves.
    private func close(then finish: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        removeKeyMonitor()
        if let id = viewModel.portingGameID {
            router.requestSpotlightSelect(id)
            anchor = HomeAnchors.shared.frame(SpotlightItem.game(id).key)
        }
        let duration = reduceMotion ? 0.18 : 0.3
        withAnimation(.easeIn(duration: duration)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            finish()
        }
    }

    // MARK: - Hints

    private var backLabel: String {
        if viewModel.isBuilding { return "Hide" }
        return viewModel.buildWizardStep > 1 ? "Back" : "Close"
    }

    private var commandHints: [HintItem] {
        if actionsStep == viewModel.buildWizardStep,
           actions.indices.contains(stepFocus.index) {
            return [HintItem(.a, actions[stepFocus.index].title)]
        }
        return [HintItem(.a, "Select")]
    }

    // MARK: - Focus and actions

    private func defaultFocus(for step: Int) -> Int {
        switch step {
        case 1:
            return viewModel.canAddSelectedGame ? 2 : 0
        case 2:
            return viewModel.canStartBuild ? 1 : 0
        default:
            return 0
        }
    }

    private func updateActions(_ actions: [AddGameAction]) {
        self.actions = actions
        actionsStep = viewModel.buildWizardStep
        stepFocus.move(by: 0, count: actions.count)
    }

    private func moveFocus(by delta: Int) {
        guard !actions.isEmpty else { return }
        let previous = stepFocus.index
        stepFocus.move(by: delta, count: actions.count)
        if stepFocus.index != previous {
            SoundEffectService.shared.play(.focus)
        }
    }

    private func confirmFocused() {
        guard !confirmDiscard,
              actionsStep == viewModel.buildWizardStep,
              actions.indices.contains(stepFocus.index) else { return }
        let action = actions[stepFocus.index]
        guard action.isEnabled else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        // Out of the key event first: an open panel (Choose folder) runs its own loop.
        DispatchQueue.main.async { action.perform() }
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
                  NSApp.modalWindow == nil,
                  !(window.firstResponder is NSText) else { return event }
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
        switch action {
        case .navigateUp, .navigateLeft: moveFocus(by: -1)
        case .navigateDown, .navigateRight: moveFocus(by: 1)
        case .confirm: confirmFocused()
        case .cancel: handleBack()
        default: break
        }
    }

    private func handleBack() {
        if confirmDiscard {
            dismissDiscard()
            return
        }
        if viewModel.isBuilding {
            requestClose()
            return
        }
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
            // The porting goes on; the panel shrinks into its tile.
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
}
