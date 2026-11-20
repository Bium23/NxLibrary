import Foundation

extension DevelopmentProfileImporter {
    /// The copy with the Porting checks.
    public init(fileManager: FileManager = .default) {
        self.init(fileManager: fileManager, checks: Self.portingChecks)
    }

    /// The legacy nxnative library (`library.json`) must still decode, and the catalog must decode with every known
    /// record kind and come from the copied library when it was imported from one.
    public static let portingChecks: [String: Check] = [
        "library.json": { data, _ in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            _ = try decoder.decode(LibraryFile.self, from: data)
        },
        "catalog.json": checkCatalog,
        "catalog.json.bak": checkCatalog,
    ]

    private static let checkCatalog: Check = { data, copy in
        let document = try CatalogStore.decode(data)
        try CatalogStore(directory: copy).validateImportedOrigin(document)
    }
}

extension AppData {
    /// Prepares the profile with the Porting checks.
    public static func prepare() throws {
        try prepare(checks: DevelopmentProfileImporter.portingChecks)
    }
}
