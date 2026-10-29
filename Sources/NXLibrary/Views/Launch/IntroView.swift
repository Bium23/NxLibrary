import SwiftUI
import AppKit
import NXLibraryCore

/// The cold-launch intro: the app mark fades and grows in with the boot cue, holds, then fades out.
/// Any key, click or controller input skips it.
struct IntroView: View {
    let reduceMotion: Bool
    let onFinish: () -> Void

    @Environment(\.seleneCanvas) private var canvas
    @State private var markIn = false
    @State private var leaving = false
    @State private var finished = false
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            SeleneBackdrop()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: canvas.u(220), height: canvas.u(220))
                .scaleEffect(markIn || reduceMotion ? 1 : 0.92)
                .opacity(markIn ? 1 : 0)
                .accessibilityLabel("NX Library")
        }
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear(perform: start)
        .onDisappear(perform: removeKeyMonitor)
    }

    private func start() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
            skip()
            return nil
        }
        SoundEffectService.shared.play(.boot)
        withAnimation(.easeOut(duration: 0.8)) { markIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { fadeOut() }
    }

    /// Input during the intro ends it at once with the closing fade.
    func skip() { fadeOut() }

    private func fadeOut() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: 0.4)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard !finished else { return }
            finished = true
            removeKeyMonitor()
            onFinish()
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
