import Foundation
import Combine

/// The details a player can choose, field by field, in Change metadata.
public enum MetadataField: String, CaseIterable, Codable, Sendable {
    case description, genres, developer, publisher, releaseDate

    public var title: String {
        switch self {
        case .description: return "Description"
        case .genres: return "Genres"
        case .developer: return "Developer"
        case .publisher: return "Publisher"
        case .releaseDate: return "Release date"
        }
    }
}

/// One value a source offers for a field. Genres are one comma-separated line.
public struct MetadataOption: Equatable, Hashable, Sendable {
    public let field: MetadataField
    /// "Nintendo store", "Title DB", "GameTDB".
    public let source: String
    public let value: String

    public init(field: MetadataField, source: String, value: String) {
        self.field = field
        self.source = source
        self.value = value
    }
}

public enum MetadataOptions {
    /// What the store (as NX Library already reads it), Title DB and GameTDB offer
    /// for `field`, in that order. A value already offered is not repeated.
    public static func list(for field: MetadataField, store: NintendoStoreMetadata?, titleDB: TitleDBInfo?,
                            gameTDB: [GameTDBEntry]) -> [MetadataOption] {
        var options: [MetadataOption] = []
        func add(_ source: String, _ value: String?) {
            let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty,
                  !options.contains(where: { $0.value.caseInsensitiveCompare(value) == .orderedSame }) else { return }
            options.append(MetadataOption(field: field, source: source, value: value))
        }
        func genres(_ list: [String]) -> String {
            list.map { $0.trimmingCharacters(in: .whitespaces).capitalized }.filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        switch field {
        case .description:
            add("Nintendo store", store?.description)
            add("Title DB", titleDB?.description)
            gameTDB.forEach { add("GameTDB", $0.synopsis) }
        case .genres:
            add("Nintendo store", store.map { genres($0.genres) })
            add("Title DB", titleDB.map { genres($0.categories) })
            gameTDB.forEach { add("GameTDB", genres($0.genres)) }
        case .developer:
            add("Nintendo store", store?.developers.joined(separator: ", "))
            add("Title DB", titleDB?.developer)
            gameTDB.forEach { add("GameTDB", $0.developer) }
        case .publisher:
            add("Nintendo store", store?.publishers.joined(separator: ", "))
            add("Title DB", titleDB?.publisher)
            gameTDB.forEach { add("GameTDB", $0.publisher) }
        case .releaseDate:
            add("Nintendo store", store?.releaseDate)
            add("Title DB", titleDB?.releaseDate)
            gameTDB.forEach { add("GameTDB", $0.releaseDate) }
        }
        return options
    }
}

/// The details a player chose, per title, in `metadata-picks.json`. They are laid
/// over the store's metadata wherever it shows, and never overwritten by a refresh.
public final class MetadataPicks: ObservableObject {
    public static let shared = MetadataPicks()

    public let directory: URL
    /// Bumps on every change, so screens redraw.
    @Published public private(set) var revision = 0
    private var table: [String: [String: String]]

    private var fileURL: URL { directory.appendingPathComponent("metadata-picks.json") }

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/NXLibrary")) {
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

    public func applied(to metadata: NintendoStoreMetadata, titleID: String) -> NintendoStoreMetadata {
        guard let picks = table[titleID] else { return metadata }
        var result = metadata
        for (key, value) in picks {
            switch MetadataField(rawValue: key) {
            case .description: result.description = value
            case .genres: result.genres = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case .developer: result.developers = [value]
            case .publisher: result.publishers = [value]
            case .releaseDate: result.releaseDate = value
            case nil: break
            }
        }
        return result
    }

    private func changed() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(table) { try? data.write(to: fileURL, options: .atomic) }
        revision += 1
    }
}
