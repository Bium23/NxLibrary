import SwiftUI
import NXLibraryCore

extension SetupCheckView {
    /// The shell sends every controller action (and the keys, mapped) here while
    /// the Setup check is up.
    func handle(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: navigate(.left)
        case .navigateRight: navigate(.right)
        case .navigateUp: navigate(.up)
        case .navigateDown: navigate(.down)
        case .confirm: activate()
        case .cancel:
            if isFirstRun { shake() } else { close() }
        default: break
        }
    }

    func move(to next: SetupFocus) {
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    /// The first card that needs something, else Continue; once, when the cards arrive.
    func placeInitialFocus() {
        guard !focusPlaced, !items.isEmpty else { return }
        focusPlaced = true
        if let index = items.firstIndex(where: { $0.isRequired && $0.state != .ready }) { focus = .card(index) }
    }

    private func navigate(_ direction: MoveDirection) {
        switch focus {
        case .card(let index):
            if let next = SetupGrid.move(from: index, direction, rowCounts: rows) {
                move(to: .card(next))
            } else if direction == .down {
                // Onto the nearer button.
                move(to: SetupGrid.offset(of: index, rowCounts: rows) < 0 ? .installAll : .carryOn)
            }
        case .installAll, .carryOn:
            switch direction {
            case .left where focus == .carryOn: move(to: .installAll)
            case .right where focus == .installAll: move(to: .carryOn)
            case .up:
                guard let last = rows.indices.last else { return }
                let start = rows.prefix(last).reduce(0, +)
                let x: Double = focus == .installAll ? -0.5 : 0.5
                let nearest = (start..<(start + rows[last])).min {
                    abs(SetupGrid.offset(of: $0, rowCounts: rows) - x) < abs(SetupGrid.offset(of: $1, rowCounts: rows) - x)
                }
                if let nearest { move(to: .card(nearest)) }
            default: break
            }
        }
    }

    func activate() {
        switch focus {
        case .card(let index):
            guard items.indices.contains(index) else { return }
            let item = items[index]
            guard item.state != .working, item.actionTitle != nil || item.state == .needsYou else {
                shake()
                return
            }
            SoundEffectService.shared.play(.click)
            setup.activate(item.id)
        case .installAll:
            guard !setup.missingAutomatic.isEmpty, !setup.installAllRunning else {
                shake()
                return
            }
            SoundEffectService.shared.play(.click)
            setup.installAll()
        case .carryOn:
            if isFirstRun && viewModel.requiresGameAppsFolderChoice {
                if let index = items.firstIndex(where: { $0.id == .library }) { move(to: .card(index)) }
                shake()
                return
            }
            SoundEffectService.shared.play(.click)
            if isFirstRun { viewModel.completeSetup() } else { close() }
        }
    }

    func close() {
        viewModel.showSetupCheck = false
    }

    func shake() {
        SoundEffectService.shared.play(.error)
        withAnimation(.linear(duration: 0.3)) { shakes += 1 }
    }
}
