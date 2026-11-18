import Foundation

/// The app's visible name and the one User-Agent every web request sends. The public project page
/// is the contact Wikidata asks clients for; no personal data goes in it.
public enum AppIdentity {
    public static let name = "Arcane"
    /// The name players knew before Arcane; only the one-time welcome says it.
    public static let formerName = "NX Library"
    /// The module that ports games to the Mac. A name, like the app's, so it is never translated.
    public static let portingName = "Porting"
    public static let projectPage = "https://github.com/Bium23/NxLibrary"

    /// The running app's version, "0" when the bundle has none (tests, command-line runs).
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public static func userAgent(version: String = AppIdentity.version) -> String {
        "\(name)/\(version) (macOS; +\(projectPage))"
    }
}
