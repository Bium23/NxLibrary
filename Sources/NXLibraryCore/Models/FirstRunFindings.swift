import Foundation

/// What the first launch finds already on the Mac, read only and without the network:
/// installed native Mac games in the default Steam folder and ported apps in the Game apps folder.
public struct FirstRunFindings: Equatable, Sendable {
    /// Ready Mac games in Steam; nil when Steam is absent, unreadable, read only in part, or the read was cancelled.
    public let steamGameCount: Int?
    public let portedAppCount: Int

    public init(steamGameCount: Int?, portedAppCount: Int) {
        self.steamGameCount = steamGameCount
        self.portedAppCount = portedAppCount
    }

    public var isEmpty: Bool { steamGameCount == nil && portedAppCount == 0 }

    /// Blocking; run it on a worker. Errors and partial scans count as nothing found, never as a failure.
    public static func read(steamRoot: URL, appsFolder: URL, cancelled: @escaping () -> Bool) -> FirstRunFindings {
        let steam = steamGameCount(root: steamRoot, cancelled: cancelled)
        guard !cancelled() else { return FirstRunFindings(steamGameCount: nil, portedAppCount: 0) }
        let ported = ImportService().scan(directories: [appsFolder]).count
        guard !cancelled() else { return FirstRunFindings(steamGameCount: nil, portedAppCount: 0) }
        return FirstRunFindings(steamGameCount: steam, portedAppCount: ported)
    }

    private static func steamGameCount(root: URL, cancelled: @escaping () -> Bool) -> Int? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let snapshot = try? SteamLibrarySource(root: root).scan(cancelled: cancelled),
              !cancelled(), snapshot.isComplete, !snapshot.libraries.isEmpty
        else { return nil }
        return snapshot.games.filter { $0.state == .nativeReady }.count
    }
}

/// Reads the findings once on a cancellable worker; only the latest request publishes.
@MainActor
public final class FirstRunFindingsReader: ObservableObject {
    @Published public private(set) var findings: FirstRunFindings?
    private var requestID = 0
    private var task: Task<Void, Never>?

    public init() {}

    public var isReading: Bool { task != nil }

    public func start(steamRoot: URL, appsFolder: URL) {
        cancel()
        let id = requestID
        let worker = Task.detached(priority: .userInitiated) {
            FirstRunFindings.read(steamRoot: steamRoot, appsFolder: appsFolder, cancelled: { Task.isCancelled })
        }
        task = Task { [weak self] in
            let result = await withTaskCancellationHandler(operation: { await worker.value },
                                                           onCancel: { worker.cancel() })
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            self.findings = result
            self.task = nil
        }
    }

    public func cancel() {
        requestID += 1
        task?.cancel()
        task = nil
    }
}
