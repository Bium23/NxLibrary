import Foundation
import Combine

public enum CatalogSourceStatus: Equatable, Sendable { case disabled, idle, scanning, ready, partial, cancelled, failed }

/// Source UI state and a cancellable reader. CatalogRepository alone owns the
/// persisted source configuration and game records; no competing catalog cache.
@MainActor
public final class CatalogSourcesModel: ObservableObject {
    public typealias Scanner = @Sendable (URL, @escaping () -> Bool) throws -> SteamLibrarySnapshot
    @Published public private(set) var configuration: CatalogSourceConfiguration
    @Published public private(set) var status: CatalogSourceStatus
    @Published public private(set) var observedGameCount = 0
    @Published public private(set) var reviewCount = 0
    @Published public private(set) var issues: [SteamScanIssue] = []
    @Published public private(set) var errorMessage: String?
    private let repository: CatalogRepository
    private let scanner: Scanner
    private let onCommit: (CatalogDocument) -> Void
    private var requestID = UUID()
    private var task: Task<Void, Never>?

    public init(repository: CatalogRepository, initialConfiguration: CatalogSourceConfiguration,
                scanner: @escaping Scanner = { root, cancelled in try SteamLibrarySource(root: root).scan(cancelled: cancelled) },
                onCommit: @escaping (CatalogDocument) -> Void) {
        self.repository = repository; configuration = initialConfiguration
        self.scanner = scanner; self.onCommit = onCommit
        status = initialConfiguration.isEnabled ? .idle : .disabled
    }
    public func startIfEnabled() { if configuration.isEnabled && status == .idle { refresh() } }
    public func configure(enabled: Bool, root: URL?) {
        invalidate()
        do {
            let document = try repository.configureSource(.steam, enabled: enabled, root: root)
            configuration = document.source(.steam)!
            errorMessage = nil; issues = []; observedGameCount = 0; reviewCount = 0
            status = enabled ? .idle : .disabled
            onCommit(document)
            if enabled { refresh() }
        } catch { failed(error) }
    }
    public func cancel() {
        invalidate()
        status = configuration.isEnabled ? .cancelled : .disabled
    }
    public func refresh() {
        invalidate()
        let expected: CatalogSourceConfiguration
        do {
            let current = try repository.load()
            guard let source = current.source(.steam), source.isEnabled, let _ = source.rootURL else {
                configuration = current.source(.steam) ?? .init(integration: .steam)
                status = .disabled
                onCommit(current)
                return
            }
            expected = source; configuration = source
        } catch { failed(error); return }
        let id = requestID
        status = .scanning; errorMessage = nil
        let scan = scanner, root = expected.rootURL!
        let worker = Task.detached(priority: .userInitiated) {
            try scan(root) { Task.isCancelled }
        }
        task = Task { [weak self] in
            do {
                let snapshot = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                let document = try self.repository.applySteam(snapshot, expectedSource: expected)
                self.configuration = document.source(.steam)!
                self.observedGameCount = Set(snapshot.games.map(\.appID)).count
                let seen = Set(snapshot.games.map(\.appID))
                self.reviewCount = document.games.compactMap(\.steamGame).filter {
                    seen.contains($0.appID) && (!$0.hasBeenRecognized || $0.needsInstallationReview)
                }.count
                self.issues = snapshot.issues
                self.status = snapshot.isComplete ? .ready : .partial
                self.task = nil
                self.onCommit(document)
            } catch {
                guard let self, self.requestID == id else { return }
                self.task = nil
                if error is CancellationError { self.status = .cancelled }
                else { self.failed(error) }
            }
        }
    }
    private func invalidate() {
        requestID = UUID(); task?.cancel(); task = nil
    }
    private func failed(_ error: Error) {
        // Publication uncertainty/stale config may have committed a newer
        // source. Read it, if possible, before presenting a recoverable error.
        if let actual = try? repository.load() {
            configuration = actual.source(.steam) ?? .init(integration: .steam)
            onCommit(actual)
        }
        errorMessage = error.localizedDescription; status = .failed
    }
}
