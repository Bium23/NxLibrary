import Foundation
import Combine

public final class AppSettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet { save() }
    }

    public enum ErrorKind { case reading, writing }
    @Published public private(set) var loadError: String?
    public private(set) var errorKind: ErrorKind?
    public private(set) var recoveryFileURL: URL?
    public let fileURL: URL
    private let fileManager: FileManager
    private var isLoading = false
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
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try preserveUnreadableFile()
            let data = try JSONEncoder().encode(settings)
            let temp = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".settings-\(UUID()).tmp")
            defer { try? fileManager.removeItem(at: temp) }
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
            errorKind = nil
            loadError = nil
            return true
        } catch {
            errorKind = .writing
            loadError = error.localizedDescription
            return false
        }
    }

    public func dismissError() {
        errorKind = nil
        loadError = nil
    }

    private func preserveUnreadableFile() throws {
        guard needsRecoveryCopy else { return }
        let copy = fileURL.deletingLastPathComponent()
            .appendingPathComponent("settings.unreadable-\(UUID()).json")
        try fileManager.copyItem(at: fileURL, to: copy)
        recoveryFileURL = copy
        needsRecoveryCopy = false
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
            try? preserveUnreadableFile()
            errorKind = .reading
            loadError = error.localizedDescription
        }
    }
}
