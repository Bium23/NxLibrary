import SwiftUI
import NXLibraryCore

public struct AddGameView: View {
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    @Environment(\.seleneReduceMotion) private var reduceMotion

    private let showsHints: Bool

    @State private var showDiscardConfirmation = false
    @State private var showLeaveBuildConfirmation = false
    @State private var stepFocus = FocusIndex()
    @State private var actions: [AddGameAction] = []
    @State private var actionsStep: Int = 0

    public init(viewModel: AppViewModel, router: AppRouter, showsHints: Bool = true) {
        self.viewModel = viewModel
        self.router = router
        self.showsHints = showsHints
    }

    public var body: some View {
        GeometryReader { geo in
            let margin = canvas.u(120)
            VStack(spacing: 0) {
                header(margin)
                AddGameStepBar(step: viewModel.buildWizardStep)
                    .padding(.horizontal, margin)
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
                                focusedAction: stepFocus.index,
                                onActions: updateActions
                            )
                        }
                    }
                    .padding(.horizontal, margin)
                    .padding(.top, 18)
                    .padding(.bottom, 70)
                }
                .scrollIndicators(.hidden)
                if showsHints {
                    SeleneHintsBar(right: commandHints)
                }
            }
        }
        .background(SeleneTheme.scrim)
        .onMoveCommand(perform: handleMove)
        .onExitCommand(perform: handleBack)
        .seleneActivationKeys(confirmFocused)
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
        .confirmationDialog("Discard selected sources?",
                            isPresented: $showDiscardConfirmation,
                            titleVisibility: .visible) {
            Button("Discard", role: .destructive, action: discardAndClose)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("The files on disk are not changed.")
        }
        .confirmationDialog("Leave the build?",
                            isPresented: $showLeaveBuildConfirmation,
                            titleVisibility: .visible) {
            Button("Leave Add Game", role: .destructive, action: leaveActiveBuild)
            Button("Keep Watching", role: .cancel) {}
        } message: {
            Text("The build keeps running in the background. Open Console to follow it.")
        }
        .alert("Apple Command Line Tools", isPresented: $viewModel.showCltInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple's official installer dialog has opened on screen. Follow Apple's prompt, then re-check from Settings or Setup.")
        }
    }

    private var commandHints: [HintItem] {
        let backLabel: String
        if viewModel.isBuilding {
            backLabel = "Hide"
        } else if viewModel.buildWizardStep > 1 {
            backLabel = "Back"
        } else {
            backLabel = "Close"
        }
        if actionsStep == viewModel.buildWizardStep,
           actions.indices.contains(stepFocus.index) {
            return [HintItem(.b, backLabel), HintItem(.a, actions[stepFocus.index].title)]
        }
        return [HintItem(.b, backLabel), HintItem(.a, "Select")]
    }

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
        guard !showDiscardConfirmation, !showLeaveBuildConfirmation,
              actionsStep == viewModel.buildWizardStep,
              actions.indices.contains(stepFocus.index) else { return }
        let action = actions[stepFocus.index]
        guard action.isEnabled else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        action.perform()
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .up, .left: moveFocus(by: -1)
        case .down, .right: moveFocus(by: 1)
        default: break
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        if showLeaveBuildConfirmation {
            switch action {
            case .confirm:
                showLeaveBuildConfirmation = false
                leaveActiveBuild()
            case .cancel:
                showLeaveBuildConfirmation = false
            default:
                break
            }
            return
        }
        if showDiscardConfirmation {
            switch action {
            case .confirm:
                showDiscardConfirmation = false
                discardAndClose()
            case .cancel:
                showDiscardConfirmation = false
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
        if showLeaveBuildConfirmation {
            showLeaveBuildConfirmation = false
            return
        }
        if showDiscardConfirmation {
            showDiscardConfirmation = false
            return
        }
        if viewModel.isBuilding {
            requestClose()
            return
        }
        if viewModel.buildWizardStep > 1 {
            withAnimation(reduceMotion ? nil : SeleneTheme.standard) {
                viewModel.goToWizardStep(viewModel.buildWizardStep - 1)
            }
        } else {
            requestClose()
        }
    }

    private func requestClose() {
        if viewModel.isBuilding {
            showLeaveBuildConfirmation = true
            return
        }
        if viewModel.selectedGameFolder != nil || !viewModel.selectedSources.isEmpty {
            showDiscardConfirmation = true
        } else {
            viewModel.addGameDidLeave()
            router.back()
        }
    }

    private func leaveActiveBuild() {
        viewModel.addGameDidLeave()
        router.back()
    }

    private func discardAndClose() {
        viewModel.selectedGameFolder = nil
        viewModel.appName = ""
        viewModel.bundleId = ""
        viewModel.resetWizard()
        viewModel.addGameDidLeave()
        router.back()
    }

    private func header(_ margin: CGFloat) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a game")
                    .seleneFont(34, .bold)
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Build a native Mac app from your own NSP, XCI or NSZ files.")
                    .seleneFont(19)
                    .foregroundColor(SeleneTheme.ink60)
            }
            Spacer()
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .seleneFont(16, .bold)
                    .foregroundColor(SeleneTheme.ink.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Add Game")
        }
        .padding(.horizontal, margin)
        .padding(.top, 34)
        .padding(.bottom, 20)
    }
}
