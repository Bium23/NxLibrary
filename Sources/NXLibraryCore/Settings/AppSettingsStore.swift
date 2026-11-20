import Foundation
import Combine

public final class AppSettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            if settings.lastSelectedGameID != oldValue.lastSelectedGameID {
                lastSelectedGameID = settings.lastSelectedGameID
            }
            save()
        }
    }

    /// Navigation state. Publishing it as a settings change re-enters the view graph during a row move.
    public private(set) var lastSelectedGameID: UUID?

    public enum ErrorKind { case reading, writing }
    @Published public private(set) var loadError: String?
    public private(set) var errorKind: ErrorKind?
    public private(set) var recoveryFileURL: URL?
    public let fileURL: URL
    private let fileManager: FileManager
    private var isLoading = false
    // The main thread owns the snapshots and their revision. The writer serializes file replacement.
    private let writer = DispatchQueue(label: "local.nxlibrary.settings-write", qos: .utility)
    private var writeRevision = 0
    private var pendingSelectionWrite: DispatchWorkItem?
    private var needsRecoveryCopy = false

    public init(fileURL: URL = AppSettingsStore.defaultURL(),
                fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.settings = AppSettings()
        load()
    }

    public static func defaultURL() -> URL {
        AppData.supportRoot.appendingPathComponent("settings.json")
    }

    @discardableResult public func save() -> Bool {
        guard !isLoading else { return true }
        let revision = nextWriteRevision()
        let snapshot = snapshotForWrite()
        let outcome = writer.sync { write(snapshot) }
        publish(outcome, revision: revision)
        return outcome.error == nil
    }

    /// Update the restore choice without invalidating settings observers or writing on the animation thread.
    @MainActor public func rememberLastSelectedGame(_ id: UUID) {
        guard lastSelectedGameID != id else { return }
        lastSelectedGameID = id

        let revision = nextWriteRevision()
        let snapshot = snapshotForWrite()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let outcome = self.write(snapshot)
            DispatchQueue.main.async { [weak self] in self?.publish(outcome, revision: revision) }
        }
        pendingSelectionWrite = work
        writer.async(execute: work)
    }

    /// Quitting can overtake the queued write. Save the latest value before exiting.
    @MainActor public func flushPendingSelection() {
        if pendingSelectionWrite != nil { save() }
    }

    private func snapshotForWrite() -> AppSettings {
        var snapshot = settings
        snapshot.lastSelectedGameID = lastSelectedGameID
        return snapshot
    }

    private func nextWriteRevision() -> Int {
        pendingSelectionWrite?.cancel()
        pendingSelectionWrite = nil
        writeRevision += 1
        return writeRevision
    }

    private func write(_ snapshot: AppSettings) -> (recovery: URL?, error: Error?) {
        var recovery: URL?
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            recovery = try preserveUnreadableFile()
            let data = try JSONEncoder().encode(snapshot)
            let temp = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".settings-\(UUID()).tmp")
            defer { try? fileManager.removeItem(at: temp) }
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
            return (recovery, nil)
        } catch {
            return (recovery, error)
        }
    }

    private func publish(_ outcome: (recovery: URL?, error: Error?), revision: Int) {
        if let copied = outcome.recovery { recoveryFileURL = copied }
        guard writeRevision == revision else { return }
        pendingSelectionWrite = nil
        if let error = outcome.error {
            errorKind = .writing
            loadError = error.localizedDescription
        } else {
            errorKind = nil
            if loadError != nil { loadError = nil }
        }
    }

    public func dismissError() {
        errorKind = nil
        loadError = nil
    }

    private func preserveUnreadableFile() throws -> URL? {
        guard needsRecoveryCopy else { return nil }
        let copy = fileURL.deletingLastPathComponent()
            .appendingPathComponent("settings.unreadable-\(UUID()).json")
        try fileManager.copyItem(at: fileURL, to: copy)
        needsRecoveryCopy = false
        return copy
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try Data(contentsOf: fileURL)
            settings = try JSONDecoder().decode(AppSettings.self, from: data)
            loadError = nil
        } catch {
            settings = AppSettings()
            needsRecoveryCopy = true
            recoveryFileURL = try? preserveUnreadableFile()
            errorKind = .reading
            loadError = error.localizedDescription
        }
    }
}
