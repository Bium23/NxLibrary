import Foundation

/// What to do with a cheat file the player adds. File names follow the host's rules (hle_cheats.c name_hex16 /
/// name_is_build): the first 16 characters a hex build ID in any case, then "." or the end.
public enum CheatInstall {
    public enum Decision: Equatable {
        /// Named for this build.
        case install(CheatFile)
        /// The name says no build: ask before installing it as this build's.
        case confirmUnnamed(CheatFile)
        /// Named for another build (upper case).
        case otherBuild(String)
        /// Under another title ID in an SD-card tree (upper case).
        case otherTitle(String)
        /// Not a cheat file: one sentence.
        case refused(String)
    }

    public static func decide(fileName: String, data: Data, titleIDInPath: String?,
                              buildID: String, titleID: String) -> Decision {
        if data.count > CheatFile.maxBytes { return .refused("The file is larger than 4 MB, so it is not a cheat file.") }
        let bytes = CheatFile.normalized(data)
        if bytes.contains(0) || String(data: bytes, encoding: .utf8) == nil {
            return .refused("The file is not text, so it is not a cheat file.")
        }
        if let tree = titleIDInPath?.uppercased(), tree != titleID.uppercased() { return .otherTitle(tree) }
        let file = CheatFile.parse(bytes)
        let s = file.summary
        if s.cheats + s.alwaysOn == 0 { return .refused("The file holds no cheat.") }
        guard let named = build(inName: fileName) else { return .confirmUnnamed(file) }
        return named == buildID.uppercased() ? .install(file) : .otherBuild(named)
    }

    /// The build ID a file name holds, upper case; nil when its first 16 characters are not one.
    public static func build(inName name: String) -> String? {
        let chars = Array(name)
        guard chars.count >= 16, chars[..<16].allSatisfy(\.isHexDigit), chars.count == 16 || chars[16] == "." else { return nil }
        return String(chars[..<16]).uppercased()
    }

    /// The title ID of an SD-card tree a file sits in (`…/<title ID>/cheats/<file>`), upper case; nil otherwise.
    public static func titleID(inPath url: URL) -> String? {
        let parts = url.pathComponents
        guard parts.count >= 3, parts[parts.count - 2].lowercased() == "cheats" else { return nil }
        let tid = parts[parts.count - 3]
        return tid.count == 16 && tid.allSatisfy(\.isHexDigit) ? tid.uppercased() : nil
    }

    /// The .txt files of a dropped folder: its own, and those of atmosphere/contents/<tid>/cheats or
    /// contents/<tid>/cheats under it (the host's two tree layouts).
    public static func candidates(in folder: URL) -> [(url: URL, titleIDInPath: String?)] {
        let fm = FileManager.default
        func texts(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        var out = texts(folder).map { ($0, titleID(inPath: $0)) }
        for base in ["atmosphere/contents", "contents"] {
            let contents = folder.appendingPathComponent(base)
            let titles = ((try? fm.contentsOfDirectory(atPath: contents.path)) ?? []).sorted()
            for tid in titles where tid.count == 16 && tid.allSatisfy(\.isHexDigit) {
                out += texts(contents.appendingPathComponent(tid).appendingPathComponent("cheats")).map { ($0, tid.uppercased()) }
            }
        }
        return out.map { (url: $0.0, titleIDInPath: $0.1) }
    }
}
