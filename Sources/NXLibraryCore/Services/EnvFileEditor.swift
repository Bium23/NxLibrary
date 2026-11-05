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
        var lines = text.components(separatedBy: newline)
        if lines.last == "" { lines.removeLast() }

        var output: [String] = []
        var placed = false
        for line in lines {
            guard lineKey(line) == key else { output.append(line); continue }
            if let value, !placed { output.append("\(key)=\(value)"); placed = true }
        }
        if let value, !placed { output.append("\(key)=\(value)") }

        let content = output.isEmpty ? "" : output.joined(separator: newline) + newline
        if content == text { return }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func lineKey(_ line: String) -> String? {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        guard !trimmed.hasPrefix("#"), let eq = trimmed.firstIndex(of: "="), eq != trimmed.startIndex else { return nil }
        return String(trimmed[..<eq]).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    }
}
