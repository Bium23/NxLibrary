import SwiftUI
import NXLibraryCore

/// A soft black fade along the bottom of the window, so the button hints sit on
/// their own ground instead of on top of the art (and the page reads as going on).
/// Spans the whole window; place it under the stage.
struct SeleneBottomScrim: View {
    @Environment(\.seleneCanvas) private var canvas

    /// Shared with Settings: all screens place their hints this far from the window's bottom edge.
    static let hintsBottom: CGFloat = 48
    /// Clear space for the 30-unit badges, two-line home hints and breathing room above them.
    static let contentClearance: CGFloat = hintsBottom + 52

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.24), location: 0.45),
                .init(color: .black.opacity(0.50), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: canvas.u(260))
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
