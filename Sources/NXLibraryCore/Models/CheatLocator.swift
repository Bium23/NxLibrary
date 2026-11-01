import Foundation

/// Where a game's cheats live and which build they are for, read the way the game's own launcher and host read them
/// (nxnative dm/mac/launcher.c, dm/host/hle_cheats.c dm_cheats_init), so NX Library and the game see one folder.
public enum CheatLocator {
    /// `# BUILD_ID` in Contents/Resources/dm/main.fixups.tsv (the host's dm_main_build()): its first 16 hex digits,
    /// upper case, as cheat files are named; nil when the line is missing or shorter.
    public static func buildID(appURL: URL) -> String? {
        let url = appURL.appendingPathComponent("Contents/Resources/dm/main.fixups.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("# BUILD_ID") {
            let value = line.dropFirst("# BUILD_ID".count).trimmingCharacters(in: .whitespaces)
            let digits = value.prefix(16)
            guard digits.count == 16, digits.allSatisfy(\.isHexDigit) else { return nil }
            return digits.uppercased()
        }
        return nil
    }

    /// DMTitleID from the app's Info.plist (what its launcher reads), else `fallback`; upper case, as the host names
    /// its flag files. A declared but invalid ID is refused, rather than writing
    /// into the fallback game's data folder.
    public static func titleID(appURL: URL, fallback: String?) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        let info = (try? Data(contentsOf: plist))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
        let id = (info?["DMTitleID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        guard let id, validTitleID(id) else { return nil }
        return id.uppercased()
    }

    /// The folder the host reads: DM_CHEATS, else DM_ROOT + "/cheats", taken first-wins from the data folder's env.txt
    /// and then the app's (the launcher's env_file order), else the data folder the launcher gives DM_ROOT + "/cheats".
    /// Nil when an empty value leaves the host without a folder (cheats off in the game too).
    public static func folder(titleID: String, appURL: URL, home: URL) -> URL? {
        guard validTitleID(titleID) else { return nil }
        let support = home.appendingPathComponent("Library/Application Support/nxnative").appendingPathComponent(titleID)
        var env: [String: String] = [:]
        for file in [support.appendingPathComponent("env.txt"),
                     appURL.appendingPathComponent("Contents/Resources/dm/env.txt")] {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (key, value) in envLines(text) where env[key] == nil { env[key] = value }
        }
        if let cheats = env["DM_CHEATS"], !cheats.isEmpty { return path(cheats) }
        guard let root = env["DM_ROOT"] else { return support.appendingPathComponent("cheats") }
        return root.isEmpty ? nil : path(root).appendingPathComponent("cheats")
    }

    private static func validTitleID(_ id: String) -> Bool {
        id.utf8.count == 16 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    /// launcher.c env_file: KEY=VALUE lines, leading blanks and trailing blanks / line ends dropped, `#` a comment,
    /// the key's trailing blanks dropped, the value kept as written.
    static func envLines(_ text: String) -> [(String, String)] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            var line = Substring(raw)
            while let c = line.first, c == " " || c == "\t" { line = line.dropFirst() }
            while let c = line.last, c == "\r" || c == " " || c == "\t" { line = line.dropLast() }
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "="), eq != line.startIndex else { return nil }
            var key = line[..<eq]
            while let c = key.last, c == " " || c == "\t", key.count > 1 { key = key.dropLast() }
            return (String(key), String(line[line.index(after: eq)...]))
        }
    }

    /// A launched app's working directory is "/", so a relative value is taken from there.
    private static func path(_ value: String) -> URL {
        URL(fileURLWithPath: value, relativeTo: URL(fileURLWithPath: "/")).standardizedFileURL
    }
}
