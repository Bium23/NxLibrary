import Foundation
import AppKit
import GameController
import NXLibraryCore

public final class GameControllerService: ObservableObject {
    public static let shared = GameControllerService()
    
    @Published public var isGamepadConnected: Bool = false
    @Published public var activeControllerName: String = "No Gamepad Connected"
    @Published public var activeBrand: GamepadBrand = .generic
    /// SF Symbols names of the buttons behind each prompt, as the connected
    /// controller reports them (printed label, user remapping included).
    @Published public var buttonSymbols: [PromptButton: String] = [:]
    
    public var onAction: ((GamepadAction) -> Void)?

    private let deadzoneKey = "NXNative_ControllerDeadzone"
    @Published public var deadzone: Float = 0.35 {
        didSet {
            let clamped = min(max(deadzone, 0.10), 0.80)
            UserDefaults.standard.set(Double(clamped), forKey: deadzoneKey)
        }
    }

    public var navigationInterval: TimeInterval = 0.12
    private var isAppActive = true
    private var lastNavTime: TimeInterval = 0
    
    private init() {
        if UserDefaults.standard.object(forKey: deadzoneKey) != nil {
            deadzone = min(max(Float(UserDefaults.standard.double(forKey: deadzoneKey)), 0.10), 0.80)
        }
        setupObservers()
        refreshControllers()
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            self?.refreshControllers()
        }
        
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            self?.refreshControllers()
        }

        isAppActive = NSApplication.shared.isActive
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = true
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = false
        }
    }
    
    public func refreshControllers() {
        let controllers = GCController.controllers()
        guard let controller = controllers.first else {
            isGamepadConnected = false
            activeControllerName = "No Gamepad Connected"
            activeBrand = .generic
            buttonSymbols = [:]
            return
        }
        
        isGamepadConnected = true
        activeControllerName = controller.vendorName ?? "Gamepad"
        activeBrand = detectBrand(from: activeControllerName, category: controller.productCategory)
        
        bindController(controller)
    }
    
    private func detectBrand(from vendor: String, category: String) -> GamepadBrand {
        switch category {
        case GCProductCategoryDualSense, GCProductCategoryDualShock4: return .playstation
        case GCProductCategoryXboxOne: return .xbox
        default: break
        }
        let lower = (vendor + " " + category).lowercased()
        if lower.contains("switch") || lower.contains("joy-con") || lower.contains("nintendo") {
            return .nintendoSwitch
        } else if lower.contains("xbox") || lower.contains("microsoft") {
            return .xbox
        } else if lower.contains("dualsense") || lower.contains("dualshock") || lower.contains("sony") || lower.contains("playstation") {
            return .playstation
        }
        return .generic
    }
    
    private func bindController(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        
        // D-Pad
        gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.navigateUp) }
        }
        gamepad.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.navigateDown) }
        }
        gamepad.dpad.left.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.navigateLeft) }
        }
        gamepad.dpad.right.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.navigateRight) }
        }
        
        // Left Thumbstick Analog Navigation with Deadzone and Cooldown
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, xVal, yVal in
            guard let self = self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard now - self.lastNavTime > self.navigationInterval else { return }
            
            if xVal > self.deadzone {
                self.lastNavTime = now
                self.triggerAction(.navigateRight)
            } else if xVal < -self.deadzone {
                self.lastNavTime = now
                self.triggerAction(.navigateLeft)
            } else if yVal > self.deadzone {
                self.lastNavTime = now
                self.triggerAction(.navigateUp)
            } else if yVal < -self.deadzone {
                self.lastNavTime = now
                self.triggerAction(.navigateDown)
            }
        }
        
        // Face Buttons. The framework maps them by position (A = bottom); a Nintendo
        // controller prints B there, so confirm moves to the button printed A (right)
        // and the rest follow its labels, as on the console.
        let face = Self.faceButtons(gamepad, nintendo: activeBrand == .nintendoSwitch)
        face.confirm.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.confirm) }
        }
        face.cancel.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.cancel) }
        }
        face.secondary.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.secondaryAction) }
        }
        face.context.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.contextAction) }
        }
        buttonSymbols = Self.symbols(gamepad, face: face)
        
        // Shoulders: Tab Switching
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.tabPrevious) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.tabNext) }
        }
        
        // Menu / Options
        gamepad.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleHoldButton(.menu, pressed: pressed, tap: .menu, hold: .menuHold)
        }
        // View (Minus / Select / Share); not every controller has one.
        gamepad.buttonOptions?.pressedChangedHandler = { [weak self] _, _, pressed in
            self?.handleHoldButton(.view, pressed: pressed, tap: .view, hold: .viewHold)
        }

        // Triggers jump to the start / end of the list; R3 is a plain press.
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.jumpToStart) }
        }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.jumpToEnd) }
        }
        gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.rightStickPress) }
        }
    }
    
    private struct FaceButtons {
        let confirm, cancel, secondary, context: GCControllerButtonInput
    }

    /// Which element runs each face action. Only a Nintendo controller whose bottom
    /// button is printed B (position mapping) is swapped; one the system already
    /// maps by label keeps the plain A/B/X/Y.
    private static func faceButtons(_ pad: GCExtendedGamepad, nintendo: Bool) -> FaceButtons {
        if nintendo, pad.buttonA.unmappedSfSymbolsName?.hasPrefix("b.") == true {
            return FaceButtons(confirm: pad.buttonB, cancel: pad.buttonA,
                               secondary: pad.buttonY, context: pad.buttonX)
        }
        return FaceButtons(confirm: pad.buttonA, cancel: pad.buttonB,
                           secondary: pad.buttonX, context: pad.buttonY)
    }

    /// The glyph of the element behind each prompt; missing names fall back to the brand's table.
    private static func symbols(_ pad: GCExtendedGamepad, face: FaceButtons) -> [PromptButton: String] {
        let elements: [PromptButton: GCControllerElement?] = [
            .a: face.confirm, .b: face.cancel, .x: face.secondary, .y: face.context,
            .lb: pad.leftShoulder, .rb: pad.rightShoulder,
            .lt: pad.leftTrigger, .rt: pad.rightTrigger,
            .rs: pad.rightThumbstickButton, .view: pad.buttonOptions, .menu: pad.buttonMenu
        ]
        return elements.compactMapValues { $0?.sfSymbolsName }
    }

    private enum HoldButton: Hashable { case menu, view }
    private var holdDetectors: [HoldButton: HoldDetector] = [:]
    private var holdActions: [HoldButton: GamepadAction] = [:]
    private var holdTimer: Timer?

    /// Routes a button through a `HoldDetector`: release before the threshold is a
    /// tap; a 50 ms timer fires the hold while the button is still down.
    private func handleHoldButton(_ button: HoldButton, pressed: Bool,
                                  tap: GamepadAction, hold: GamepadAction) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            var detector = self.holdDetectors[button] ?? HoldDetector()
            if pressed {
                detector.press(at: now)
                self.holdActions[button] = hold
                self.holdDetectors[button] = detector
                self.startHoldTimer()
            } else {
                let result = detector.release(at: now)
                self.holdDetectors[button] = detector
                self.stopHoldTimerIfIdle()
                if result == .tap { self.triggerAction(tap) }
                else if result == .hold { self.triggerAction(hold) }
            }
        }
    }

    private func startHoldTimer() {
        guard holdTimer == nil else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            for (button, var detector) in self.holdDetectors where detector.isPressed {
                if detector.tick(at: now) == .hold, let action = self.holdActions[button] {
                    self.triggerAction(action)
                }
                self.holdDetectors[button] = detector
            }
            self.stopHoldTimerIfIdle()
        }
    }

    private func stopHoldTimerIfIdle() {
        guard !holdDetectors.values.contains(where: { $0.isPressed }) else { return }
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func triggerAction(_ action: GamepadAction) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isAppActive else { return }
            self.onAction?(action)
        }
    }
}
