import Foundation
import AppKit
import GameController
import NXLibraryCore

public final class GameControllerService: ObservableObject {
    public static let shared = GameControllerService()
    
    @Published public var isGamepadConnected: Bool = false
    @Published public var activeControllerName: String = "No Gamepad Connected"
    @Published public var activeBrand: GamepadBrand = .generic
    
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
            return
        }
        
        isGamepadConnected = true
        activeControllerName = controller.vendorName ?? "Gamepad"
        activeBrand = detectBrand(from: activeControllerName)
        
        bindController(controller)
    }
    
    private func detectBrand(from vendor: String) -> GamepadBrand {
        let lower = vendor.lowercased()
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
        
        // Face Buttons
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.confirm) }
        }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.cancel) }
        }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.secondaryAction) }
        }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.triggerAction(.contextAction) }
        }
        
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
