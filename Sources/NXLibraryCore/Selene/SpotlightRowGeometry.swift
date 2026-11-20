import CoreGraphics

/// Where Spotlight's tiles go, in Selene units (Main.xaml SeleneGameRow + SeleneTileStyle). Each item is
/// `1 + 174·s + 3` wide (item margin 1/3, tile host 174 = 160 + 2·7), where `s` is 1.3 for the selected tile and 1
/// otherwise; the selected tile grows through its frame so the neighbours move. The selection walks to the third
/// slot and then stays there while the row slides (HomeNav.AnchorSlot).
///
/// A tile's place on the screen is one camera, shared by the whole row, plus the tile's place in the row. Only the
/// camera slides, so the row moves as one piece: a tile made at the edge while the row is still gliding is carried
/// with its neighbours, instead of landing at its final place ahead of them and drifting back into line.
public enum SpotlightRowGeometry {
    public static let pitch: CGFloat = 178          // 1 + 174 + 3
    public static let host: CGFloat = 174           // 160 + 2 × 7
    public static let grow: CGFloat = 1.3
    public static let rowStart: CGFloat = 72        // 80 start padding − 8 (row margin −88 + side margin 80)
    /// Tiles made past each edge of the screen, for a row still gliding after quick presses.
    public static let spareTiles = 4

    /// The row's slide for scroll `offset` (`SpotlightState.scrollOffset`).
    public static func camera(offset: Int) -> CGFloat { -CGFloat(offset) * pitch }

    /// Left edge of item `index` (its 1u margin included) in the row: the items after the selection make room
    /// for it to grow.
    public static func place(of index: Int, selected: Int?) -> CGFloat {
        let base = rowStart + CGFloat(index) * pitch
        guard let selected, index > selected else { return base }
        return base + host * (grow - 1)
    }

    // MARK: - The glide

    // The row draws every tile and its camera from one value, the selection's position: an index, with fractions on
    // the way between two tiles. Glided as one value, a tile's place, its size and its neighbours' places move on
    // one clock. Glided apart (an offset, a scale, a camera), a tile's growth that began while the row was still
    // moving started a couple of frames after its slide, so it pulled away from the tile on its right and ran over
    // the one on its left during quick presses.

    /// No selection, as a position: an item just before the first, so every tile stands at its own place.
    public static let noSelection: CGFloat = -1

    /// How much of the selection's growth tile `index` has at `position`: all of it at the selection, shared by
    /// the two tiles a glide is between.
    public static func lens(of index: CGFloat, at position: CGFloat) -> CGFloat {
        max(0, 1 - abs(index - position))
    }

    /// The tile's scale at `position`: `grow` at the selection.
    public static func scale(of index: CGFloat, at position: CGFloat) -> CGFloat {
        1 + (grow - 1) * lens(of: index, at: position)
    }

    /// `place(of:selected:)` anywhere in the glide: a tile gives way by as much as the tiles before it have grown,
    /// so neighbours keep their gap wherever the glide is.
    public static func place(of index: CGFloat, at position: CGFloat) -> CGFloat {
        let grownBefore = unit(index - position) - unit(-position)
        return rowStart + index * pitch + host * (grow - 1) * grownBefore
    }

    /// `camera(offset:)` anywhere in the glide.
    public static func camera(at position: CGFloat) -> CGFloat {
        -max(0, position - CGFloat(SpotlightState.anchorSlot)) * pitch
    }

    private static func unit(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

    /// The items to make: from `spareTiles` beyond the `tilesLeftOfStage` left of the stage to `spareTiles` beyond
    /// the `tilesAcross` the window holds.
    public static func window(count: Int, offset: Int, tilesLeftOfStage: Int, tilesAcross: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let lower = max(0, offset - tilesLeftOfStage - spareTiles)
        let upper = min(count, offset + tilesAcross + spareTiles)
        return lower..<max(lower, upper)
    }
}
