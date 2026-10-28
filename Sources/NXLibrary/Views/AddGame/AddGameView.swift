import SwiftUI
import NXLibraryCore

public struct AddGameView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter

    private let showsHints: Bool

    @State private var showDiscardConfirmation = false
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
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            VStack(spacing: 0) {
                header(metrics)
                AddGameStepBar(step: viewModel.buildWizardStep)
                    .padding(.horizontal, metrics.margin)
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
                    .padding(.horizontal, metrics.margin)
                    .padding(.top, 18)
                    .padding(.bottom, 70)
                }
                .scrollIndicators(.hidden)
                if showsHints {
                    CommandBar(commandHints)
                }
            }
        }
        .background(SeleneTheme.canvas)
        .onMoveCommand(perform: handleMove)
        .onExitCommand(perform: handleBack)
        .onChange(of: viewModel.buildWizardStep) { step in
            stepFocus = FocusIndex(index: defaultFocus(for: step))
        }
        .onChange(of: viewModel.canAddSelectedGame) { canAdd in
            guard viewModel.buildWizardStep == 1 else { return }
            if canAdd, stepFocus.index == 0 {
                stepFocus.index = 1
            } else if !canAdd, stepFocus.index == 1 {
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
    }

    private var commandHints: [CommandHint] {
        switch viewModel.buildWizardStep {
        case 1:
            return [
                .init("B", "Back"),
                .init("A", viewModel.canAddSelectedGame ? "Continue" : "Choose folder")
            ]
        case 2:
            return [.init("B", "Back"), .init("A", "Select")]
        default:
            if viewModel.isBuilding {
                return [.init("A", "Select")]
            }
            return [.init("B", "Back"), .init("A", "Select")]
        }
    }

    private func defaultFocus(for step: Int) -> Int {
        switch step {
        case 1:
            return viewModel.canAddSelectedGame ? 1 : 0
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
        guard actionsStep == viewModel.buildWizardStep,
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
        if showDiscardConfirmation {
            showDiscardConfirmation = false
            return
        }
        guard !viewModel.isBuilding else { return }
        if viewModel.buildWizardStep > 1 {
            withAnimation(SeleneTheme.standard) {
                viewModel.goToWizardStep(viewModel.buildWizardStep - 1)
            }
        } else {
            requestClose()
        }
    }

    private func requestClose() {
        guard !viewModel.isBuilding else {
            router.back()
            return
        }
        if viewModel.selectedGameFolder != nil || !viewModel.selectedSources.isEmpty {
            showDiscardConfirmation = true
        } else {
            router.back()
        }
    }

    private func discardAndClose() {
        viewModel.selectedGameFolder = nil
        viewModel.appName = ""
        viewModel.bundleId = ""
        viewModel.resetWizard()
        router.back()
    }

    private func header(_ metrics: SeleneLayoutMetrics) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add a game")
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1.2)
                    .foregroundColor(SeleneTheme.ink)
                Text("Build a native Mac app from your own NSP, XCI or NSZ files.")
                    .font(.system(size: 13))
                    .foregroundColor(SeleneTheme.inkMuted)
            }
            Spacer()
            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Add Game")
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 34)
        .padding(.bottom, 20)
    }
}
