import Foundation

/// A Switch game case's front: GameTDB's coverHQ is 1166 × 1888.
public enum BoxArt {
    public static let aspectRatio: CGFloat = 1166.0 / 1888.0
}

/// Geometry of the Collection cover row (Selene Main.xaml SeleneLibrary), in
/// Selene units. The selection walks to the anchor slot, then stays there and
/// the row slides.
public enum CollectionRow {
    public static let anchorSlot = 7
    /// A cover in Switch case proportions (`BoxArt`); the list itself is 400 high.
    public static let coverWidth: CGFloat = 172
    public static let coverHeight: CGFloat = 278
    public static let gap: CGFloat = 14
    public static let pitch: CGFloat = coverWidth + gap
    public static let bandHeight: CGFloat = 400
    /// The selected cover's growth (Selene's ListGameItemStyle focus scale, plus its ring margin).
    public static let selectedScale: CGFloat = 1.09

    /// How many covers have slid off to the left.
    public static func scrollOffset(selectedIndex: Int) -> Int {
        max(0, selectedIndex - anchorSlot)
    }
}
