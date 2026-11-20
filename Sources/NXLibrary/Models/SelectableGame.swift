import Foundation
import NXLibraryCore
import ArcanePorting

struct SelectableGame: Identifiable, Equatable {
    let id: String
    let name: String
    let titleId: String?
    var files: [GameFileItem]

    init(id: String, name: String, titleId: String?, files: [GameFileItem]) {
        self.id = id
        self.name = name
        self.titleId = titleId
        self.files = files
    }

    var totalSizeBytes: Int64 {
        SourceSelection.uniqueSize(files)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }

    var baseFile: GameFileItem? {
        files.first(where: { $0.type == .base })
    }

    var newestUpdate: GameFileItem? {
        files.filter { $0.type == .update }
            .max { lhs, rhs in
                Self.versionNumber(lhs.versionString) < Self.versionNumber(rhs.versionString)
            }
    }

    /// A base game, or an update of a NUP with no base game (the engine takes it as the whole game).
    var hasGame: Bool { SourceSelection.hasGame(files) }

    var isUpdateOnly: Bool { SourceSelection.isUpdateOnly(files) }

    private static func versionNumber(_ value: String?) -> Int {
        guard let value else { return -1 }
        let digits = value.lowercased().hasPrefix("v") ? String(value.dropFirst()) : value
        return Int(digits) ?? -1
    }

    var updateCount: Int {
        files.filter { $0.type == .update }.count
    }

    var dlcCount: Int {
        files.filter { $0.type == .dlc }.count
    }

    var summaryText: String {
        var parts: [String] = []
        if baseFile != nil { parts.append("Base") }
        if updateCount > 0 { parts.append("\(updateCount) Update" + (updateCount > 1 ? "s" : "")) }
        if dlcCount > 0 { parts.append("\(dlcCount) DLC" + (dlcCount > 1 ? "s" : "")) }
        return parts.joined(separator: ", ")
    }
}
