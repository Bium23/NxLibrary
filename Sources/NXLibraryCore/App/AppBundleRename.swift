import Foundation

/// Gives a release copy still called "NX Library.app" its current name when the app quits.
/// Renaming while it runs would leave `Bundle.main` on the old path for the rest of the session,
/// so it happens only at quit, and only when nothing else is about to use that path.
public enum AppBundleRename {
    public static let oldName = "NX Library.app"
    public static var newName: String { "\(AppIdentity.name).app" }

    /// Where the bundle should go, or nil when it stays as it is: a development or translocated
    /// copy, an app busy updating, saving or relaunching itself, any other name, a read-only
    /// folder, or an "Arcane.app" already beside it.
    public static func target(bundleURL: URL, isRelease: Bool, isTranslocated: Bool, isBusy: Bool,
                              fileManager: FileManager = .default) -> URL? {
        guard isRelease, !isTranslocated, !isBusy else { return nil }
        let bundle = bundleURL.standardizedFileURL
        guard bundle.lastPathComponent == oldName else { return nil }
        let folder = bundle.deletingLastPathComponent()
        let target = folder.appendingPathComponent(newName)
        guard fileManager.isWritableFile(atPath: folder.path),
              !fileManager.fileExists(atPath: target.path) else { return nil }
        return target
    }

    /// One move within the same folder; a failure leaves the bundle where it was.
    public static func perform(bundleURL: URL, to target: URL, fileManager: FileManager = .default) throws {
        try fileManager.moveItem(at: bundleURL, to: target)
    }
}
