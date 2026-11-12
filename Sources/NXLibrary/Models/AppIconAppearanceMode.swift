import NXLibraryCore
import Foundation

public enum AppIconAppearanceMode: String, CaseIterable, Identifiable, Hashable {
    case auto = "Auto (System)"
    case light = "Light"
    case dark = "Dark"
    case mono = "Monochrome"
    
    public var id: String { rawValue }
    /// Light and Dark remain readable for existing preferences; today's artwork
    /// has one colour variant and one monochrome variant.
    public static let selectable: [Self] = [.auto, .mono]
    public var label: String { self == .mono ? L10n.text("Monochrome") : L10n.text("Color") }
}
