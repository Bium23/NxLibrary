import Foundation

/// Where the nxnative checkout is: `~/nxnative`, or the folder the player chose in Settings → Engine while that
/// folder exists.
public enum EngineLocation {
    public static func defaultFolder(home: URL) -> URL { home.appendingPathComponent("nxnative") }

    public static func folder(saved: String?, home: URL, fileManager: FileManager = .default) -> URL {
        var isDirectory: ObjCBool = false
        if let saved, !saved.isEmpty, fileManager.fileExists(atPath: saved, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: saved)
        }
        return defaultFolder(home: home)
    }

    /// The folder holds nxnative: its build script and `dm`.
    public static func isEngine(_ folder: URL, fileManager: FileManager = .default) -> Bool {
        fileManager.fileExists(atPath: folder.appendingPathComponent("scripts/build_ipa_from_nsp.py").path)
            && fileManager.fileExists(atPath: folder.appendingPathComponent("dm").path)
    }

    /// What to remember for a chosen folder: nil for the default one, so nothing is stored.
    public static func savedValue(for folder: URL, home: URL) -> String? {
        let path = folder.standardizedFileURL.path
        return path == defaultFolder(home: home).standardizedFileURL.path ? nil : path
    }
}

/// Where prod.keys is looked for when none is imported yet: Ryujinx's folder, the homebrew tools' `~/.switch`,
/// and first a folder the player chose.
public enum ProdKeysLocations {
    public struct Candidate: Equatable {
        public let path: String
        public let name: String
    }

    public static func candidates(home: URL, selected: URL?) -> [Candidate] {
        var list: [Candidate] = []
        if let selected {
            list.append(Candidate(path: selected.appendingPathComponent("system/prod.keys").path,
                                  name: "Selected Directory/system"))
            list.append(Candidate(path: selected.appendingPathComponent("prod.keys").path, name: "Selected Directory"))
        }
        let support = home.appendingPathComponent("Library/Application Support")
        list.append(Candidate(path: support.appendingPathComponent("Ryujinx/system/prod.keys").path,
                              name: "Ryujinx (App Support)"))
        list.append(Candidate(path: support.appendingPathComponent("ryujinx/system/prod.keys").path,
                              name: "Ryujinx (App Support)"))
        list.append(Candidate(path: home.appendingPathComponent(".switch/prod.keys").path, name: "Switch Homebrew"))
        return list
    }
}
