import Foundation

/// The player's picks laid over the Nintendo store's metadata.
extension MetadataPicks {
    public func applied(to metadata: NintendoStoreMetadata, titleID: String) -> NintendoStoreMetadata {
        guard let picks = table[titleID] else { return metadata }
        var result = metadata
        for (key, value) in picks {
            switch MetadataField(rawValue: key) {
            case .description:
                result.description = value
                result.descriptionLanguage = "custom"
            case .genres: result.genres = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case .developer: result.developers = [value]
            case .publisher: result.publishers = [value]
            case .releaseDate: result.releaseDate = value
            case nil: break
            }
        }
        return result
    }
}
