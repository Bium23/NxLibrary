import SwiftUI
import AppKit
import NXLibraryCore

/// Full-screen screenshot viewer (spec §6, Selene captures player): a 0.92
/// scrim, the image fitted, a "3 / 6" counter and hints. A pure view: the host
/// owns the state and routes input through `ScreenshotViewer.handle`. Present
/// it as an overlay inside the canvas root so the canvas scaling applies.
struct ScreenshotViewer: View {
    @Environment(\.seleneCanvas) private var canvas

    let titleID: String
    let urls: [URL]
    let state: ScreenshotViewerState
    let artwork: ArtworkStore
    let onClose: () -> Void

    @State private var images: [Int: NSImage] = [:]

    enum Outcome { case ignored, moved, close }

    /// Left/Right (and L/R) page, B closes; everything else is swallowed by the host.
    static func handle(_ action: GamepadAction, state: inout ScreenshotViewerState) -> Outcome {
        switch action {
        case .navigateLeft, .tabPrevious: return state.previous() ? .moved : .ignored
        case .navigateRight, .tabNext: return state.next() ? .moved : .ignored
        case .cancel: return .close
        default: return .ignored
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            if let image = images[state.index] {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, canvas.u(64))
                    .padding(.vertical, canvas.u(96))
                    .contentShape(Rectangle())
                    .onTapGesture {} // A click on the image keeps it open.
                    .id(state.index)
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(state.label)
                    .seleneFont(17)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.bottom, canvas.u(52))
                    .allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, "Back")],
                               right: [HintItem(.lb, "‹"), HintItem(.rb, "›")],
                               bottom: 40, leftInset: 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opacity animations always run, reduce motion or not.
        .animation(.easeOut(duration: 0.2), value: state.index)
        .animation(.easeOut(duration: 0.2), value: images.keys.sorted())
        .task(id: state.index) { await load(state.index) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot \(state.label)")
    }

    @MainActor
    private func load(_ index: Int) async {
        guard images[index] == nil, urls.indices.contains(index) else { return }
        guard let file = await artwork.screenshot(titleID: titleID, index: index, remoteURL: urls[index]),
              let decoded = await GameArtLoader.decode(at: file, maxPixelSize: 2560),
              !Task.isCancelled else { return }
        images[index] = decoded
    }
}
