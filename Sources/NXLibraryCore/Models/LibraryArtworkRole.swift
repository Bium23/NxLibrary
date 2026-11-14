import Foundation

/// Layout roles stay separate from the provider. A square never requests/crops
/// the portrait cover; the renderer can keep the original Finder app artwork.
public enum LibraryArtworkRole: String, CaseIterable, Sendable {
    case square, cover, hero, logo
    public var slot: ArtworkSlot {
        switch self {
        case .square: return .icon
        case .cover: return .cover
        case .hero: return .background
        case .logo: return .logo
        }
    }
}
