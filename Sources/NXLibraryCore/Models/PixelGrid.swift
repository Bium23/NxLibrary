import CoreGraphics

/// Whole device pixels. A layer drawn through a filter is snapped to the pixel grid when it rests, but sampled at
/// its exact position while it scales: placed on the grid already, the two coincide and the end of a scale
/// animation doesn't jump (the Arcane orb, 16 Nov 2026).
public enum PixelGrid {
    /// `rect` (in points, in a space whose pixels are `scale` points apart, such as a window) with its origin and
    /// size rounded to whole pixels; unchanged for a non-positive scale.
    public static func align(_ rect: CGRect, scale: CGFloat) -> CGRect {
        guard scale > 0 else { return rect }
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return CGRect(x: snap(rect.minX), y: snap(rect.minY), width: snap(rect.width), height: snap(rect.height))
    }
}
