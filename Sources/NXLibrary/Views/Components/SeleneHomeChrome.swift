import SwiftUI

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
    /// Game options draws its own hints over the screen.
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
            .opacity(hintsHidden ? 0 : 1)
            .frame(width: canvas.size.width, height: canvas.size.height)
        }
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .clipped()
    }
}

extension HintItem {
    /// Both home screens' left hints: the other screen (Hold: Search) and the Menu.
    static func homeGlobals(other: String) -> [HintItem] {
        [HintItem(.view, other, glyph: .spotlight, hold: "Hold: Search"),
         HintItem(.menu, "Menu", glyph: .menu, hold: "Hold: Settings")]
    }
}
