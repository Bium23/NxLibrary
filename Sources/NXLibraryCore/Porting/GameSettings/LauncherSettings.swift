import Foundation

public struct LauncherSettingOption: Decodable, Equatable, Identifiable {
    public var value: String
    public var label: String
    public var id: String { value }

    public init(value: String, label: String) {
        self.value = value
        self.label = label
    }
}

public struct LauncherSetting: Decodable, Equatable, Identifiable {
    public var env: String
    public var kind: String
    public var section: String
    public var label: String
    public var note: String?
    public var defaultValue: String?
    public var options: [LauncherSettingOption]?
    public var min: Double?
    public var max: Double?
    public var step: Double?
    public var on: String?
    public var off: String?
    /// "basic" for a setting the engine's window shows without More; nil otherwise.
    public var level: String?
    /// `ENV=value`: the setting is drawn only while that other setting has that value.
    public var needs: String?

    public var id: String { env }

    private enum CodingKeys: String, CodingKey {
        case env, kind, section, label, note, options, min, max, step, on, off, level, needs
        case defaultValue = "default"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        env = try container.decode(String.self, forKey: .env)
        kind = try container.decode(String.self, forKey: .kind)
        section = try container.decode(String.self, forKey: .section)
        label = try container.decode(String.self, forKey: .label)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        min = try container.decodeIfPresent(Double.self, forKey: .min)
        max = try container.decodeIfPresent(Double.self, forKey: .max)
        step = try container.decodeIfPresent(Double.self, forKey: .step)
        on = try container.decodeIfPresent(String.self, forKey: .on)
        off = try container.decodeIfPresent(String.self, forKey: .off)
        level = try container.decodeIfPresent(String.self, forKey: .level)
        needs = try container.decodeIfPresent(String.self, forKey: .needs)
        if let pairs = try container.decodeIfPresent([[String]].self, forKey: .options) {
            options = pairs.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return LauncherSettingOption(value: pair[0], label: pair[1])
            }
        } else {
            options = nil
        }
    }
}

public struct LauncherSettingsFile: Decodable, Equatable {
    public var game: String
    public var settings: [LauncherSetting]
}

// MARK: - The values a build takes

extension LauncherSetting {
    /// Whether this build takes `value`, as `dm/mac/launcher.c` checks a saved choice: one of a choice's options,
    /// a toggle's `on` or `off`, or a number in a range (no leading space, no hex, finite).
    public func accepts(_ value: String) -> Bool {
        switch kind {
        case "choice": return options?.contains { $0.value == value } ?? false
        case "toggle": return value == on || value == off
        case "range":
            guard let x = Self.number(value), let min, let max else { return false }
            return x >= min && x <= max
        default: return false
        }
    }

    /// The build's tested default; a range compares as a number ("1" is "1.0").
    public func isDefault(_ value: String) -> Bool {
        guard let defaultValue else { return false }
        if kind == "range", let x = Self.number(value), let d = Self.number(defaultValue) {
            return abs(x - d) < 1e-9
        }
        return value == defaultValue
    }

    /// A range value as the shortest decimal: 1 → "1", 0.45 → "0.45".
    public static func rangeString(_ x: Double) -> String {
        let rounded = (x * 1_000_000).rounded() / 1_000_000
        var text = String(format: "%.6f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// `needs` (`ENV=value`) against the values that apply now; true without one.
    public func needsSatisfied(_ values: [String: String]) -> Bool {
        guard let needs, let equals = needs.firstIndex(of: "=") else { return true }
        return values[String(needs[..<equals])] == String(needs[needs.index(after: equals)...])
    }

    static func number(_ text: String) -> Double? {
        guard let first = text.unicodeScalars.first, !CharacterSet.whitespacesAndNewlines.contains(first),
              !text.contains("x"), !text.contains("X"),
              let x = Double(text), x.isFinite else { return nil }
        return x
    }
}

public enum LauncherSettingsReader {
    /// The settings metadata a current nxnative Mac app carries. Apps built
    /// before this interface have no file and fall back to the fixed UI.
    public static func load(for appURL: URL) -> LauncherSettingsFile? {
        let url = appURL
            .appendingPathComponent("Contents/Resources/dm/launcher.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LauncherSettingsFile.self, from: data)
    }

    public static func supports(_ env: String, for appURL: URL) -> Bool {
        if let file = load(for: appURL) {
            return file.settings.contains { $0.env == env }
        }
        // Older builds have no launcher.json. The render-scale slider only
        // works when the rewriter emitted its stub.
        if env == "DM_RENDER_SCALE" {
            return hasRenderScaleFixup(appURL)
        }
        return true
    }

    public static func hasRenderScaleFixup(_ appURL: URL) -> Bool {
        let url = appURL
            .appendingPathComponent("Contents/Resources/dm/main.fixups.tsv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return text.split(separator: "\n").contains { $0.hasPrefix("# RENDER_SCALE") }
    }
}
