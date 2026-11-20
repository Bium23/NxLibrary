import Foundation

/// The values a Switch game's Change metadata offers, from the Nintendo store, Title DB and GameTDB.
public enum MetadataOptions {
    /// What the store (as Arcane already reads it), Title DB and GameTDB offer
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
