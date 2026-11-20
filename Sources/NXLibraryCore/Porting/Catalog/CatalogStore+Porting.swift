import Foundation

/// The app's catalog store reads every kind it knows (`CatalogRecordKinds.standard`).
extension CatalogStore {
    public init(directory: URL) { self.init(directory: directory, kinds: .standard) }
    init(directory: URL, publication: CatalogPublication) { self.init(directory: directory, publication: publication, kinds: .standard) }
    public static func decode(_ data: Data) throws -> CatalogDocument { try decode(data, kinds: .standard) }
}
