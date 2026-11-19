import SwiftUI

/// Moves a block as one while something above it glides.
///
/// SwiftUI hands an animated offset down to each leaf view (text, image, star), and a leaf animates its whole
/// frame with the animation of the latest change that touches it. A change made in another animation during a
/// glide (a fade, a fan, an image arriving) re-times those leaves, and they run ahead of or behind the rest:
/// Spotlight's page, on the first descent from the row, under the fades of its own blocks (maintainer's report,
/// 16 Nov 2026).
///
/// A geometry group resolves the glide once for the block and passes each leaf a still position inside it.
struct GlideGroup: ViewModifier {
    func body(content: Content) -> some View {
        content.geometryGroup()
    }
}
