import SwiftUI
import AppKit
import NXLibraryCore

/// Shared geometry preserves the established Spotlight and Collection layouts.
/// Provider loading and settings stay outside this purely visual component.
struct GameLogoArea: View {
    let title: String
    let logo: NSImage?
    var collection = false
    @Environment(\.seleneCanvas) private var canvas
    var body: some View {
        Group {
            if collection { collectionArea }
            else { spotlightArea }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityAddTraits(.isHeader)
    }
    private var spotlightArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let logo {
                Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: canvas.u(700), height: canvas.u(240), alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
                    .transition(.opacity)
            } else {
                Text(title).seleneFont(56).foregroundColor(SeleneTheme.ink).lineLimit(1).truncationMode(.tail)
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
            }
        }.frame(width: canvas.u(900), height: canvas.u(195), alignment: .bottomLeading)
    }
    private var collectionArea: some View {
        ZStack(alignment: .bottomLeading) {
            if let logo {
                Image(nsImage: logo).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(maxWidth: canvas.u(700), maxHeight: canvas.u(240), alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.35), radius: canvas.u(8))
            } else {
                Text(title).seleneFont(56).foregroundColor(SeleneTheme.ink).multilineTextAlignment(.leading)
                    .lineLimit(3).frame(maxHeight: canvas.u(220))
                    .shadow(color: .black.opacity(0.45), radius: canvas.u(6))
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: canvas.u(250), alignment: .bottomLeading)
    }
}
