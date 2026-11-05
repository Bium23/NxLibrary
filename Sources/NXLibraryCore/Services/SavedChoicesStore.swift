import Foundation

/// A game app's saved choices: `launcher.<env>` strings in its preferences domain, which nxnative's Mac launcher
/// reads at every start (docs/frontends.md, Saved choices).
public protocol SavedChoicesStore {
    func value(_ env: String, domain: String) -> String?
    /// Nil removes the choice.
    func set(_ value: String?, _ env: String, domain: String) throws
}

public enum SavedChoicesError: LocalizedError, Equatable {
    case notSaved(String)

    public var errorDescription: String? {
        switch self {
        case .notSaved(let domain): return "Could not save the choice in \(domain)."
        }
    }
}

public struct SystemSavedChoices: SavedChoicesStore {
    public init() {}

    static func key(_ env: String) -> CFString { "launcher.\(env)" as CFString }

    public func value(_ env: String, domain: String) -> String? {
        let app = domain as CFString
        // A choice the game's own window made since the last read is seen.
        CFPreferencesAppSynchronize(app)
        return CFPreferencesCopyAppValue(Self.key(env), app) as? String
    }

    public func set(_ value: String?, _ env: String, domain: String) throws {
        let app = domain as CFString
        CFPreferencesSetValue(Self.key(env), value as CFString?, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw SavedChoicesError.notSaved(domain)
        }
    }
}

/// For tests: domain → env → value.
public final class MemorySavedChoices: SavedChoicesStore {
    public var values: [String: [String: String]] = [:]

    public init() {}

    public func value(_ env: String, domain: String) -> String? { values[domain]?[env] }

    public func set(_ value: String?, _ env: String, domain: String) throws {
        values[domain, default: [:]][env] = value
        if values[domain]?.isEmpty == true { values[domain] = nil }
    }
}
