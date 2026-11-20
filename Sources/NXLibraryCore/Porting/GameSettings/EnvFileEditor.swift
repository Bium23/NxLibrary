import Foundation

/// Changes one variable of a game's `env.txt` and leaves every other line as it is: the player's own lines, comments,
/// their order and line endings. Keys are matched as the Mac launcher reads them (dm/mac/launcher.c `env_file`):
/// leading blanks skipped, `#` starts a comment, the key ends at `=` with trailing blanks trimmed.
public enum EnvFileEditor {
    /// `nil` removes every line for `key`; a value replaces the first line (later duplicates are dropped) or is
    /// appended. Written atomically. Removing from a missing file creates nothing.
    public static func set(_ key: String, to value: String?, in file: URL) throws {
        let fm = FileManager.default
        let existing = fm.fileExists(atPath: file.path) ? try String(contentsOf: file, encoding: .utf8) : nil
        if existing == nil && value == nil { return }
        let text = existing ?? ""
        let newline = text.contains("\r\n") ? "\r\n" : "\n"

        var output = ""
        var placed = false
        for (line, ending) in lines(of: text) {
            guard lineKey(line) == key else { output += line + ending; continue }
            if let value, !placed { output += "\(key)=\(value)" + (ending.isEmpty ? newline : ending); placed = true }
        }
        if let value, !placed {
            if let last = output.last, last != "\n" && last != "\r\n" { output += newline }
            output += "\(key)=\(value)" + newline
        }

        if output == text { return }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: file, atomically: true, encoding: .utf8)
    }

    /// Each line with its own ending ("\n", "\r\n", or "" for a last line without one), so a file that mixes
    /// endings keeps every line apart (the launcher splits on "\n").
    private static func lines(of text: String) -> [(String, String)] {
        var result: [(String, String)] = []
        var current = ""
        for character in text {
            if character == "\n" || character == "\r\n" {
                result.append((current, String(character)))
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append((current, "")) }
        return result
    }

    private static func lineKey(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "="), eq != trimmed.startIndex else { return nil }
        return String(trimmed[..<eq]).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }
}
