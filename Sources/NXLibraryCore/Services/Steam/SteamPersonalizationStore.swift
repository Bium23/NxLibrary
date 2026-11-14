import Foundation
import Combine

/// One manifest publishes a complete title draft. New image files are prepared
/// first; a failed manifest commit leaves every previous reference untouched.
public final class SteamPersonalizationStore: ObservableObject {
    private struct Entry: Codable { var fields: [String: String]; var art: [String: String] }
    @Published public private(set) var revision = 0
    private let directory: URL
    private let publish: (Data, URL) throws -> Void
    private let invalidManifest: Bool
    private var entries: [String: Entry]
    public init(directory: URL, publish: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.directory = directory; self.publish = publish
        let decoded = (try? InstallationFileSnapshot.read(at: directory.appendingPathComponent("personal.json"), maximumBytes: 16_777_216).data)
            .flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) }
        entries = decoded ?? [:]
        invalidManifest = FileManager.default.fileExists(atPath: directory.appendingPathComponent("personal.json").path) && decoded == nil
    }
    public func value(titleID: String, field: MetadataField) -> String? { entries[titleID]?.fields[field.rawValue] }
    public func url(titleID: String, slot: ArtworkSlot) -> URL? {
        guard let name = entries[titleID]?.art[slot.rawValue], name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return directory.appendingPathComponent("assets").appendingPathComponent(name)
    }
    public func save(fields: [MetadataField: String], images: [ArtworkSlot: Data], automatic: Set<ArtworkSlot>, titleID: String) throws {
        guard !invalidManifest else { throw URLError(.cannotParseResponse) }
        var draft = entries
        var entry = entries[titleID] ?? Entry(fields: [:], art: [:])
        var created: [URL] = []
        do {
            for (field, raw) in fields {
                guard raw.utf8.count <= 100_000 else { throw URLError(.dataLengthExceedsMaximum) }
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.fields[field.rawValue] = text.isEmpty ? nil : text
            }
            for (slot, data) in images {
                guard data.count <= 12_582_912,
                      let normalized = ArtworkStore.downsample(data, maxPixelSize: slot.kind.maxPixelSize, png: true) else { throw URLError(.cannotDecodeContentData) }
                let name = UUID().uuidString + ".png"
                let file = directory.appendingPathComponent("assets").appendingPathComponent(name)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try normalized.write(to: file, options: .atomic); created.append(file); entry.art[slot.rawValue] = name
            }
            for slot in automatic { entry.art[slot.rawValue] = nil }
            draft[titleID] = entry
            let data = try JSONEncoder().encode(draft)
            guard data.count <= 16_777_216 else { throw URLError(.dataLengthExceedsMaximum) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try publish(data, directory.appendingPathComponent("personal.json"))
        } catch {
            for file in created { try? FileManager.default.removeItem(at: file) }
            throw error
        }
        let retained = Set(draft.values.flatMap { $0.art.values })
        let old = Set(entries.values.flatMap { $0.art.values }).subtracting(retained)
        entries = draft; revision += 1
        // Only obsolete generated copies, after successful publication. Automatic
        // is removal of a manifest reference, so a file deletion cannot undo it.
        for name in old where name == URL(fileURLWithPath: name).lastPathComponent {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("assets").appendingPathComponent(name))
        }
    }
}
