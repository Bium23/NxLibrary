/// Shared folder wording for Setup, Settings and their pickers.
public enum GameFoldersCopy {
    public static let appsTitle = "Game apps"
    public static var appsAbout: String {
        L10n.text("Choose where to keep your game apps.")
    }
    public static var appsContents: String {
        L10n.text("Existing games and new builds.")
    }
    public static var appsPickerMessage: String {
        L10n.text("Choose where to keep your game apps. Put any existing nxnative games (.app) here. Change it later in Settings → Library.")
    }
    public static let sourcesTitle = "Game files"

    public static func sourceFormats(extractedFolders: Bool) -> String {
        L10n.text("NSP, XCI, NSZ and XCZ files") + (extractedFolders ? L10n.text(", or Switch 2 NUP files and extracted folders") : "")
    }

    public static func sourcesAbout(extractedFolders: Bool) -> String {
        L10n.format("Optional: %@ for building.", [String(describing: (sourceFormats(extractedFolders: extractedFolders)))])
    }

    public static func sourcesPickerMessage(extractedFolders: Bool) -> String {
        L10n.format("Choose a folder with your %@. Existing apps play without these files. Change it later in Settings → Library.", [String(describing: (sourceFormats(extractedFolders: extractedFolders)))])
    }
}
