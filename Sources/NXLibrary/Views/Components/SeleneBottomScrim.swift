import SwiftUI
import NXLibraryCore

/// A soft black fade along the bottom of the window, so the button hints sit on
/// their own ground instead of on top of the art (and the page reads as going on).
/// Spans the whole window; place it under the stage.
struct SeleneBottomScrim: View {
    @Environment(\.seleneCanvas) private var canvas

    /// Where the home screens set their hints, in Selene units from the window's bottom edge.
    static let hintsBottom: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LinearGradient(stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.12), location: 0.5),
                .init(color: .black.opacity(0.32), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: canvas.u(200))
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
