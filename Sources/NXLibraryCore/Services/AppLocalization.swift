import Foundation
import Combine

/// The selected locale is captured by background work, while views observe changes on the main thread.
public final class AppLocalization: ObservableObject {
    public static let shared = AppLocalization()
    @Published public private(set) var context = AppLocale(language: .english, region: "US")

    public func configure(_ settings: AppSettings) {
        let next = AppLocale(language: settings.appLanguage, region: settings.appRegion)
        guard next != context else { return }
        L10n.setContext(next)
        context = next
    }
}

public enum L10n {
    private static let lock = NSLock()
    private static var selected = AppLocale(language: .english, region: "US")
    public static var context: AppLocale {
        lock.lock(); defer { lock.unlock() }
        return selected
    }
    public static func setContext(_ context: AppLocale) {
        lock.lock(); defer { lock.unlock() }
        selected = context
    }

    /// Installed apps find their resources before considering SwiftPM's development location.
    public static func resources(in app: URL? = nil) -> Bundle? {
        let root = app ?? Bundle.main.bundleURL
        for folder in [root.appendingPathComponent("Contents/Resources"), root] {
            if let bundle = Bundle(url: folder.appendingPathComponent("NXLibrary_NXLibraryCore.bundle")) { return bundle }
        }
        return app == nil ? Bundle.module : nil
    }

    private static func languageBundle(_ language: AppLanguage, in resources: Bundle) -> Bundle? {
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// At most one retained bundle per supported language; never cache interpolated user data or mutable copy.
    private static let defaultLanguageBundles: [AppLanguage: Bundle] = {
        guard let resources = resources() else { return [:] }
        var bundles: [AppLanguage: Bundle] = [:]
        for language in AppLanguage.allCases where language != .automatic {
            bundles[language] = languageBundle(language, in: resources)
        }
        return bundles
    }()

    public static func text(_ key: String, context: AppLocale? = nil, bundle: Bundle? = nil) -> String {
        let context = context ?? Self.context
        // Explicit test/import bundles must never reuse another bundle's resources.
        let localized: Bundle?
        if let bundle { localized = languageBundle(context.language, in: bundle) }
        else { localized = defaultLanguageBundles[context.language] }
        guard let localized else { return key }
        return localized.localizedString(forKey: key, value: key, table: "Localizable")
    }

    public static func format(_ key: String, _ arguments: [CVarArg], context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        return String(format: text(key, context: context), locale: context.formatLocale, arguments: arguments)
    }

    public static func count(_ key: String, _ count: Int, arguments: [CVarArg] = [], context: AppLocale? = nil) -> String {
        let context = context ?? Self.context
        return String(format: text(key, context: context), locale: context.formatLocale, arguments: [count] + arguments)
    }
}
