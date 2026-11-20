import Foundation

/// What the first launch finds already on the Mac, read only and without the network:
/// installed native Mac games in the chosen Steam folder and ported apps in the Game apps folder.
public struct FirstRunFindings: Equatable, Sendable {
    /// Ready Mac games in Steam; nil when Steam is absent, unreadable, read only in part, or the read was cancelled.
    public let steamGameCount: Int?
    public let portedAppCount: Int
    /// An error or partial read is not evidence that Steam or its games are absent.
    public let steamReadFailed: Bool

    public init(steamGameCount: Int?, portedAppCount: Int, steamReadFailed: Bool = false) {
        self.steamGameCount = steamGameCount
        self.portedAppCount = portedAppCount
        self.steamReadFailed = steamReadFailed
    }

    public var isEmpty: Bool { !steamReadFailed && steamGameCount == nil && portedAppCount == 0 }

    /// Blocking; run it on a worker. A failed/partial Steam scan can be retried without changing sources.
    /// `portedAppCount` counts the module's apps (Porting: `read(steamRoot:appsFolder:cancelled:)`).
    public static func read(steamRoot: URL, portedAppCount: () -> Int,
                            cancelled: @escaping () -> Bool) -> FirstRunFindings {
        let steam = readSteam(root: steamRoot, cancelled: cancelled)
        guard !cancelled() else { return FirstRunFindings(steamGameCount: nil, portedAppCount: 0) }
        let ported = portedAppCount()
        guard !cancelled() else { return FirstRunFindings(steamGameCount: nil, portedAppCount: 0) }
        return FirstRunFindings(steamGameCount: steam.count, portedAppCount: ported, steamReadFailed: steam.failed)
    }

    private static func readSteam(root: URL, cancelled: @escaping () -> Bool) -> (count: Int?, failed: Bool) {
        do {
            let metadata = try root.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
            guard metadata.isDirectory == true else { return (nil, true) }
        } catch let error as NSError {
            let missing = error.domain == NSCocoaErrorDomain
                && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code)
            return (nil, !missing)
        }
        guard let snapshot = try? SteamLibrarySource(root: root).scan(cancelled: cancelled),
              !cancelled(), snapshot.isComplete, !snapshot.libraries.isEmpty
        else { return (nil, true) }
        return (snapshot.games.filter { $0.state == .nativeReady }.count, false)
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

    public func start(steamRoot: URL, portedAppCount: @escaping @Sendable () -> Int) {
        cancel()
        findings = nil
        let id = requestID
        let worker = Task.detached(priority: .userInitiated) {
            FirstRunFindings.read(steamRoot: steamRoot, portedAppCount: portedAppCount, cancelled: { Task.isCancelled })
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
