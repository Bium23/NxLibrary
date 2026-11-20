import Foundation

public enum TargetPlatform: String, Codable, CaseIterable, Identifiable {
    case macApp = "mac-app"

    public var id: String { rawValue }
    public var title: String { L10n.text("Mac App (.app)") }
    public var iconName: String { "macbook.gen2" }
    public var subtitle: String { L10n.text("Double-clickable native macOS app for Apple Silicon.") }
}
