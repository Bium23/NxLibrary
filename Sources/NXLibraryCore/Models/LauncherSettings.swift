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

    public var id: String { env }

    private enum CodingKeys: String, CodingKey {
        case env, kind, section, label, note, options, min, max, step, on, off
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

    /// Whether the app's launcher.json lists this value for the setting (DM_FPS_TARGET 120). Apps without the file offer only the fixed UI.
    public static func offers(_ env: String, value: String, for appURL: URL) -> Bool {
        load(for: appURL)?.settings.first { $0.env == env }?.options?.contains { $0.value == value } ?? false
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
