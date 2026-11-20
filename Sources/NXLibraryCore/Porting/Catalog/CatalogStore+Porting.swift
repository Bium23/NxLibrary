import Foundation

/// The app's catalog store reads every kind it knows (`CatalogRecordKinds.standard`) and converts a first catalog from
/// nxnative's `library.json`.
extension CatalogStore {
    public init(directory: URL) { self.init(directory: directory, kinds: .standard, legacy: .nxnative) }
    init(directory: URL, publication: CatalogPublication) {
        self.init(directory: directory, publication: publication, kinds: .standard, legacy: .nxnative)
    }
    public static func decode(_ data: Data) throws -> CatalogDocument { try decode(data, kinds: .standard) }
}

extension CatalogLegacyImport {
    /// nxnative's library (`library.json` and its backup), with the Switch source switched on.
    public static let nxnative = Self(primary: "library.json", backup: "library.json.bak") { data, origin in
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try CatalogDocument.converting(decoder.decode(LibraryFile.self, from: data), origin: origin)
    }
}

extension CatalogDocument {
    public static func converting(_ legacy: LibraryFile, origin: CatalogLegacyOrigin = .absent) throws -> Self {
        guard legacy.schemaVersion == 1 else { throw CatalogModelError.unsupportedSchema(legacy.schemaVersion) }
        let result = Self(legacyOrigin: origin, sources: [.init(integration: .nxnative, isEnabled: true), .init(integration: .steam)],
                          games: legacy.games.map { .init(nxnative: $0) })
        try result.validate()
        return result
    }
}
