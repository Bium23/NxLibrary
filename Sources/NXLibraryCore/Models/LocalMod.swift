import Foundation

/// One folder in a game's `mods` folder, as NX Library shows it.
public struct LocalMod: Equatable, Sendable {
    /// The folder's name: the mod's identity inside the game's mods folder.
    public let folderName: String
    public let folder: URL
    /// The RomFS tree the engine overlays; nil when the folder holds none ("not a mod").
    public let romfs: URL?
    public var isOn: Bool

    public init(folderName: String, folder: URL, romfs: URL?, isOn: Bool) {
        self.folderName = folderName
        self.folder = folder
        self.romfs = romfs
        self.isOn = isOn
    }
}
