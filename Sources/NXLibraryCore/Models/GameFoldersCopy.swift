/// Shared folder wording for Setup, Settings and their pickers.
public enum GameFoldersCopy {
    public static let appsTitle = "Game apps"
    public static let appsAbout = "Choose where to keep your game apps."
    public static let appsContents = "Existing games and new builds."
    public static let appsPickerMessage = "Choose where to keep your game apps. Put any existing nxnative games (.app) here. Change it later in Settings → Library."
    public static let sourcesTitle = "Game files"

    public static func sourceFormats(extractedFolders: Bool) -> String {
        "NSP, XCI, NSZ and XCZ files" + (extractedFolders ? " or extracted folders" : "")
    }

    public static func sourcesAbout(extractedFolders: Bool) -> String {
        "Optional: \(sourceFormats(extractedFolders: extractedFolders)) for building."
    }

    public static func sourcesPickerMessage(extractedFolders: Bool) -> String {
        "Choose a folder with your \(sourceFormats(extractedFolders: extractedFolders)). Existing apps play without these files. Change it later in Settings → Library."
    }
}
