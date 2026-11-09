import SwiftUI
import NXLibraryCore

/// The frame Spotlight and Collection share, so what stays put between them sits
/// in the same place: the art (and any dimming) full bleed, the bottom fade, the
/// 1920 × 1080 stage centred across and pinned to the top (a taller window gives
/// its spare height to the bottom, never to a gap above the tabs), and the hints
/// on the window's bottom edge. The stage draws the top bar at its own (0, 0).
struct SeleneHomeChrome<Backdrop: View, Stage: View>: View {
    @Environment(\.seleneCanvas) private var canvas

    var leftHints: [HintItem]
    var rightHints: [HintItem]
    var rightReserve: [[String]] = []
    /// An overlay with its own hints is up (`AppRouter.overlayHasHints`).
    var hintsHidden = false
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var stage: () -> Stage

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop()
            SeleneBottomScrim()
            stage()
                .frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
                .offset(x: canvas.stageOrigin.x)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                SeleneHintsBar(left: leftHints, right: rightHints,
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18,
                               rightReserve: rightReserve)
            }
            .seleneOverlaidHints(hintsHidden)
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
    }
}

extension HintItem {
    /// Both home screens' left hints: the other screen (Hold: Search) and the Menu.
    static func homeGlobals(other: String, onOther: (() -> Void)? = nil, onMenu: (() -> Void)? = nil) -> [HintItem] {
        [HintItem(.view, other, glyph: .spotlight, hold: L10n.text("Hold: Search"), action: onOther),
         HintItem(.menu, L10n.text("Menu"), glyph: .menu, hold: L10n.text("Hold: Settings"), action: onMenu)]
    }
}

extension AppRouter {
    /// The control center, search, Game options, Add game or the console is up: each draws its own hints,
    /// so the screen's step aside instead of showing through.
    @MainActor
    func overlayHasHints(_ viewModel: AppViewModel) -> Bool {
        isMenuPresented || isSearchPresented || viewModel.gameForSettingsSheet != nil || route.isOverlay
    }
}

extension View {
    /// A screen's hints under an overlay that has its own: they sink a little and
    /// fade out as it opens, and come back the same way as it closes.
    func seleneOverlaidHints(_ hidden: Bool) -> some View {
        modifier(OverlaidHints(hidden: hidden))
    }
}

private struct OverlaidHints: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let hidden: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden && !reduceMotion ? canvas.u(12) : 0)
            .animation(SeleneTheme.cubicOut(0.3), value: hidden)
            .allowsHitTesting(!hidden)
    }
}
