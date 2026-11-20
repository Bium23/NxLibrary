import Foundation
import Combine

/// The details a player can choose, field by field, in Change metadata.
public enum MetadataField: String, CaseIterable, Codable, Sendable {
    case description, genres, developer, publisher, releaseDate

    public var title: String {
        switch self {
        case .description: return L10n.text("Description")
        case .genres: return L10n.text("Genres")
        case .developer: return L10n.text("Developer")
        case .publisher: return L10n.text("Publisher")
        case .releaseDate: return L10n.text("Release date")
        }
    }
}

/// One value a source offers for a field. Genres are one comma-separated line.
public struct MetadataOption: Equatable, Hashable, Sendable {
    public let field: MetadataField
    /// "Nintendo store", "Title DB", "GameTDB", "IGDB".
    public let source: String
    public let value: String

    public init(field: MetadataField, source: String, value: String) {
        self.field = field
        self.source = source
        self.value = value
    }
}

/// The details a player chose, per title, in `metadata-picks.json`. They are laid
/// over the store's metadata wherever it shows, and never overwritten by a refresh.
public final class MetadataPicks: ObservableObject {
    public static let shared = MetadataPicks()

    public let directory: URL
    /// Bumps on every change, so screens redraw.
    @Published public private(set) var revision = 0
    package private(set) var table: [String: [String: String]]

    private var fileURL: URL { directory.appendingPathComponent("metadata-picks.json") }

    public init(directory: URL = AppData.supportRoot) {
        self.directory = directory
        let url = directory.appendingPathComponent("metadata-picks.json")
        table = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    public func value(titleID: String, field: MetadataField) -> String? {
        table[titleID]?[field.rawValue]
    }

    /// A blank value takes the pick back.
    public func set(_ value: String, titleID: String, field: MetadataField) {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return remove(titleID: titleID, field: field) }
        table[titleID, default: [:]][field.rawValue] = value
        changed()
    }

    public func remove(titleID: String, field: MetadataField) {
        table[titleID]?[field.rawValue] = nil
        if table[titleID]?.isEmpty == true { table[titleID] = nil }
        changed()
    }

    private func changed() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(table) { try? data.write(to: fileURL, options: .atomic) }
        revision += 1
    }
}
