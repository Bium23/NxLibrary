import Foundation

/// Ryujinx's numbered directories contain the filesystem bookkeeping and two trees.
/// The game reads the contents of the committed `0` tree, including all its slots.
enum RyujinxSaveFolder {
    static func payload(for selection: URL, titleID: String) throws -> URL {
        let librarySuffix = ["bis", "user", "save"]
        let selected = selection.standardizedFileURL
        guard Array(selected.pathComponents.suffix(3)) != librarySuffix else {
            throw SaveFailure.io("Choose the numbered Ryujinx folder for this game.")
        }
        var directory = selected
        while directory.path != "/" {
            let parent = directory.deletingLastPathComponent()
            if SaveLocation.validID(directory.lastPathComponent), Array(parent.pathComponents.suffix(3)) == librarySuffix {
                let metadata = directory.appendingPathComponent("ExtraData0")
                // Only unwrap a recognized container. Ordinary exports keep their own layout.
                guard SaveFiles.exists(metadata) else { return selected }
                try SaveFiles.safePath(metadata)
                guard let data = try? SaveFiles.readRegular(metadata, limit: 512), data.count == 512 else {
                    throw SaveFailure.io("Ryujinx save information could not be read. Close Ryujinx and choose the game folder again.")
                }
                let programID = data.withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(as: UInt64.self)) }
                guard programID == UInt64(titleID, radix: 16) else {
                    throw SaveFailure.io("This Ryujinx save belongs to a different game.")
                }
                return directory.appendingPathComponent("0")
            }
            directory = parent
        }
        return selected
    }
}
