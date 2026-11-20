import Foundation

/// One lease covers a whole save operation or app installation, including duplicate library entries.
public final class SaveOperationGate {
    private let lock = NSLock()
    private var leases: [String: UUID] = [:]
    private var recovery: Set<String> = []
    private var appUpdate: UUID?
    public var onActivityChange: (() -> Void)?
    public init() {}
    public func begin(titleID: String, recovering: Bool = false) -> UUID? {
        lock.lock(); defer { lock.unlock(); onActivityChange?() }
        let key = titleID.uppercased()
        guard appUpdate == nil, leases[key] == nil, recovering || !recovery.contains(key) else { return nil }
        let token = UUID(); leases[key] = token; return token
    }
    public func end(titleID: String, token: UUID) {
        lock.lock(); defer { lock.unlock(); onActivityChange?() }
        let key = titleID.uppercased()
        if leases[key] == token { leases[key] = nil }
    }
    public func isBusy(titleID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let key = titleID.uppercased()
        return appUpdate != nil || leases[key] != nil || recovery.contains(key)
    }
    public func setRecoveryBlocked(_ blocked: Bool, titleID: String) {
        lock.lock(); defer { lock.unlock() }
        if blocked { recovery.insert(titleID.uppercased()) } else { recovery.remove(titleID.uppercased()) }
    }

    /// A blocked recovery without active I/O may need a newer app to resolve it.
    public var hasActiveOperations: Bool {
        lock.lock(); defer { lock.unlock() }
        return !leases.isEmpty
    }

    public func beginAppUpdate() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard appUpdate == nil, leases.isEmpty else { return nil }
        let token = UUID()
        appUpdate = token
        return token
    }

    public func endAppUpdate(token: UUID) {
        lock.lock(); defer { lock.unlock() }
        if appUpdate == token { appUpdate = nil }
    }
}
