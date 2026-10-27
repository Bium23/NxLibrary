import Foundation
import Combine

public final class AppSettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet { save() }
    }

    public private(set) var loadError: String?
    public let fileURL: URL
    private let fileManager: FileManager
    private var isLoading = false

    public init(fileURL: URL = AppSettingsStore.defaultURL(),
                fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.settings = AppSettings()
        load()
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NXLibrary/settings.json")
    }

    public func save() {
        guard !isLoading else { return }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(settings)
            let temp = fileURL.appendingPathExtension("tmp")
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
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
            loadError = error.localizedDescription
        }
    }
}
