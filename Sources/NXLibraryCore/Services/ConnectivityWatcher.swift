import Foundation
import Network

/// Calls `onReturn` on the main queue when the Mac goes from offline to online, so work that met an outage (the
/// background description pass) resumes by itself. Starts on first use; it never reports the first reading.
public final class ConnectivityWatcher {
    private let monitor = NWPathMonitor()
    private let onReturn: @MainActor () -> Void
    private var started = false
    private var online: Bool?

    public init(onReturn: @escaping @MainActor () -> Void) {
        self.onReturn = onReturn
    }

    deinit { monitor.cancel() }

    /// Main queue only, like `onReturn`.
    public func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let now = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self else { return }
                let returned = Self.returned(previous: self.online, current: now)
                self.online = now
                if returned { MainActor.assumeIsolated { self.onReturn() } }
            }
        }
        monitor.start(queue: DispatchQueue(label: "Arcane.connectivity"))
    }

    /// True only for a change from offline to online; the first reading is never a return.
    public static func returned(previous: Bool?, current: Bool) -> Bool {
        previous == false && current
    }
}
