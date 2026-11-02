/// Shared folder wording for Setup, Settings and their pickers.
public enum GameFoldersCopy {
    public static let appsTitle = "Game apps"
    public static let appsAbout = "Existing nxnative games (.app). New builds go to ~/Applications."
    public static let appsPickerMessage = "Choose the folder containing your nxnative games (.app). Change it later in Settings → Library. New builds go to ~/Applications."
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
