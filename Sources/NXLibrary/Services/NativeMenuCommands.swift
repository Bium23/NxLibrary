import AppKit
import SwiftUI

struct NativeMenuAvailability {
    var general = false
    var play = false
    var details = false
    var options = false
}

private struct NativeMenuAvailabilityKey: FocusedValueKey {
    typealias Value = NativeMenuAvailability
}

extension FocusedValues {
    var nxMenuAvailability: NativeMenuAvailability? {
        get { self[NativeMenuAvailabilityKey.self] }
        set { self[NativeMenuAvailabilityKey.self] = newValue }
    }
}

/// Native menus own input until tracking ends. Screen changes start on the following main-loop turn.
@MainActor
final class NativeMenuCommands: ObservableObject {
    static let shared = NativeMenuCommands()
    @Published private(set) var isTracking = false
    private var menus: Set<ObjectIdentifier> = []
    private var pending: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let menu = note.object as? NSMenu else { return }
                    if name == NSMenu.didBeginTrackingNotification { self.menus.insert(ObjectIdentifier(menu)) }
                    else { self.menus.remove(ObjectIdentifier(menu)) }
                    if self.menus.isEmpty, let action = self.pending {
                        self.pending = nil
                        self.enqueue(action)
                    } else { self.isTracking = !self.menus.isEmpty }
                }
            })
        }
    }

    func post(_ name: Notification.Name) {
        let action = { NotificationCenter.default.post(name: name, object: nil) }
        if !menus.isEmpty { pending = action }
        else { enqueue(action) }
    }

    private func enqueue(_ action: @escaping () -> Void) {
        isTracking = true
        DispatchQueue.main.async { [weak self] in
            action()
            guard let self else { return }
            self.isTracking = !self.menus.isEmpty
        }
    }
}
