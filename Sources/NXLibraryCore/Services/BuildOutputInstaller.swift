import Foundation

public enum BuildInstallError: Error, LocalizedError {
    case invalidApp(String)
    case replaceFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidApp(let p): return "The built app is invalid: \(p)"
        case .replaceFailed(let m): return "Could not replace the app: \(m)"
        }
    }
}

public enum BuildOutputInstaller {
    public static func install(tempApp: URL, finalApp: URL,
                               fileManager: FileManager = .default) throws {
        let plist = tempApp.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: plist.path) else {
            throw BuildInstallError.invalidApp(tempApp.path)
        }
        let parent = finalApp.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: finalApp.path) {
            let backup = parent.appendingPathComponent(finalApp.lastPathComponent + ".old")
            try? fileManager.removeItem(at: backup)
            try fileManager.moveItem(at: finalApp, to: backup)
            do {
                try fileManager.moveItem(at: tempApp, to: finalApp)
                try? fileManager.removeItem(at: backup)
            } catch {
                try? fileManager.moveItem(at: backup, to: finalApp)
                throw BuildInstallError.replaceFailed(error.localizedDescription)
            }
        } else {
            try fileManager.moveItem(at: tempApp, to: finalApp)
        }
    }
}
