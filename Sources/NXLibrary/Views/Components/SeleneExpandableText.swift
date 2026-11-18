import SwiftUI

/// Keeps both text layouts alive while revealing the full description. Swapping
/// the string itself makes a long option row change height in a single frame.
struct SeleneExpandableText: View {
    let text: String
    let preview: String
    let expanded: Bool

    var body: some View {
        SeleneTextRevealLayout(expanded: expanded) {
            Text(preview).opacity(expanded ? 0 : 1)
            Text(text).opacity(expanded ? 1 : 0)
        }
        .clipped()
    }
}

/// Resolve the destination geometry immediately and let SwiftUI animate its
/// frames. Interpolating the layout's measurements would make scrollTo read a
/// moving target, particularly when the row above is simultaneously collapsing.
/// Both text children always receive their final width and unconstrained height.
private struct SeleneTextRevealLayout: Layout {
    let expanded: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let textProposal = ProposedViewSize(width: width, height: nil)
        guard subviews.count == 2 else { return .zero }
        let preview = subviews[0].sizeThatFits(textProposal)
        let full = subviews[1].sizeThatFits(textProposal)
        return CGSize(width: width ?? max(preview.width, full.width),
                      height: expanded ? full.height : preview.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for text in subviews {
            text.place(at: bounds.origin, anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
