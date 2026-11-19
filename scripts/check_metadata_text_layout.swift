import AppKit
import SwiftUI

// Offscreen geometry regression check. No UI automation or snapshots.
// xcrun swiftc Sources/NXLibrary/Views/Components/SeleneExpandableText.swift \
//   scripts/check_metadata_text_layout.swift -o /tmp/nxlibrary-text-layout
// /tmp/nxlibrary-text-layout
@main
struct TextRevealProbe {
    @MainActor static func main() {
        _ = NSApplication.shared
        let paragraph = "A long source description has paragraphs, punctuation, and explicit line breaks. Explore the world, restore what has been lost, and find a path through the mountains.\n\n"
        let full = String(repeating: paragraph, count: 30)
        let preview = String(full.prefix(240)) + "…"
        var checks = 0
        for width: CGFloat in [300, 720, 1040] {
            func height(_ expanded: Bool) -> CGFloat {
                autoreleasepool {
                    let view = SeleneExpandableText(text: full, preview: preview, expanded: expanded)
                        .font(.system(size: 15)).frame(width: width)
                    return NSHostingView(rootView: view).fittingSize.height
                }
            }
            let compact = height(false), expanded = height(true)
            let expectedCompact = NSHostingView(rootView: Text(preview).font(.system(size: 15)).frame(width: width)).fittingSize.height
            let expectedFull = NSHostingView(rootView: Text(full).font(.system(size: 15)).frame(width: width)).fittingSize.height
            precondition(expanded > compact * 5, "Probe must cover a row taller than the viewport")
            precondition(abs(compact - expectedCompact) < 1, "Collapsed row must fit the preview")
            precondition(abs(expanded - expectedFull) < 1, "Expanded row must fit all text")
            checks += 2
            print("width=\(Int(width)): preview=\(Int(compact))pt; full=\(Int(expanded))pt")
        }
        // Reusing a host after changing both width and content must not retain
        // measurements from the previous source or window size.
        let host = NSHostingView(rootView: SeleneExpandableText(text: full, preview: preview, expanded: true)
            .font(.system(size: 15)).frame(width: 300))
        let longHeight = host.fittingSize.height
        host.rootView = SeleneExpandableText(text: "Short source", preview: "Short source", expanded: true)
            .font(.system(size: 15)).frame(width: 720)
        precondition(host.fittingSize.height < longHeight / 5, "Changed content must invalidate its measurements")
        for reducedMotion in [false, true] {
            checkScroll(reducedMotion: reducedMotion)
        }
        print("PASS: \(checks) text endpoints, content changes, repeated focus and reduced motion. No windows displayed.")
    }
}

private final class ScrollProbeState: ObservableObject {
    @Published var focus = 0
    var frames: [Int: CGRect] = [:]
}
private struct RowFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private struct ScrollProbe: View {
    @ObservedObject var state: ScrollProbeState
    let reducedMotion: Bool
    private let full = String(repeating: "A long description about places and quests in the game.\n\n", count: 35)
    private var motion: Animation? { reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(0..<5) { index in
                        VStack(alignment: .leading) {
                            Text("SOURCE \(index)")
                            SeleneExpandableText(text: full, preview: String(full.prefix(240)) + "…", expanded: state.focus == index)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18).id(index)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: RowFrames.self, value: [index: geometry.frame(in: .named("list"))])
                        })
                    }
                }
                .coordinateSpace(name: "list")
                .onPreferenceChange(RowFrames.self) { state.frames = $0 }
                .animation(motion, value: state.focus)
            }
            .onChange(of: state.focus) { index in
                withAnimation(motion) { proxy.scrollTo(index, anchor: .top) }
            }
        }
        .font(.system(size: 15)).frame(width: 600, height: 500)
    }
}

@MainActor private func checkScroll(reducedMotion: Bool) {
    let state = ScrollProbeState()
    let host = NSHostingView(rootView: ScrollProbe(state: state, reducedMotion: reducedMotion))
    host.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.layoutIfNeeded()
    precondition(!window.isVisible)
    func scrollView(_ root: NSView) -> NSScrollView? {
        if let scroll = root as? NSScrollView { return scroll }
        return root.subviews.lazy.compactMap(scrollView).first
    }
    func settle() {
        for _ in 0..<25 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
    }
    settle()
    guard let scroll = scrollView(host), let document = scroll.documentView else {
        preconditionFailure("Scroll container did not initialise")
    }
    precondition(document.frame.height > 500)
    for focus in [1, 2, 1, 3, 0] {
        state.focus = focus
        settle()
        guard let target = state.frames[focus] else { preconditionFailure("Missing row geometry") }
        let expected = min(target.minY, max(0, document.frame.height - scroll.contentView.bounds.height))
        precondition(abs(scroll.contentView.bounds.minY - expected) < 2,
                     "Focus \(focus) must scroll to its final top, not the old expanded row position")
    }
    // An interrupted expansion must also settle on the last requested row.
    for focus in [4, 1, 3, 2] {
        state.focus = focus
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        host.layoutSubtreeIfNeeded()
    }
    settle()
    let expected = min(state.frames[2]!.minY, max(0, document.frame.height - scroll.contentView.bounds.height))
    precondition(abs(scroll.contentView.bounds.minY - expected) < 2, "Rapid focus changes must settle on the last row")
    print("scroll destinations and interruptions: PASS (reduced motion=\(reducedMotion))")
    window.contentView = nil
}
