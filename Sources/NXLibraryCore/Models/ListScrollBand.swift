import CoreGraphics

/// A list scrolls only when the focused row leaves a comfortable band, and then just enough to put the row
/// on the band's nearer edge: moving inside the band leaves the list still, so it breathes instead of
/// following every press.
public enum ListScrollBand {
    /// The unit anchor (y) for `ScrollViewProxy.scrollTo` that sets the row on the nearer edge of
    /// `safeTop...safeBottom` (viewport coordinates), or nil when the row is already inside it.
    /// `scrollTo(_:anchor:)` lines up the row's anchor point with the viewport's, so the row's top lands
    /// at `anchor * (viewport - rowHeight)`.
    public static func anchor(rowTop: CGFloat, rowHeight: CGFloat, viewport: CGFloat,
                              safeTop: CGFloat, safeBottom: CGFloat) -> CGFloat? {
        let travel = viewport - rowHeight
        guard travel > 0 else { return 0 }
        let target: CGFloat
        if rowTop < safeTop {
            target = safeTop
        } else if rowTop + rowHeight > safeBottom {
            target = safeBottom - rowHeight
        } else {
            return nil
        }
        return min(max(target / travel, 0), 1)
    }
}
