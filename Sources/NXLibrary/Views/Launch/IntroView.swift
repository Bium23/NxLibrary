import SwiftUI
import AppKit
import NXLibraryCore

extension Notification.Name {
    static let nxIntroSkip = Notification.Name("NXIntroSkip")
}

/// The cold-launch intro: the app mark fades and grows in with the boot cue, holds, then fades out.
/// Any key, click or controller input skips it.
struct IntroView: View {
    let settings: AppSettingsStore
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
            VStack(spacing: canvas.u(26)) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: canvas.u(220), height: canvas.u(220))
                    .accessibilityHidden(true)
                Text("NX Library")
                    .seleneFont(38, .semibold)
                    .tracking(canvas.u(-0.7))
                    .foregroundColor(SeleneTheme.ink)
            }
            .scaleEffect(markIn || reduceMotion ? 1 : 0.96)
            .opacity(markIn ? 1 : 0)
            .accessibilityElement(children: .combine)
        }
        .opacity(leaving ? 0 : 1)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear(perform: start)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxIntroSkip)) { _ in skip() }
        .task {
            do { try await Task.sleep(nanoseconds: 1_400_000_000) } catch { return }
            fadeOut()
        }
        .task(id: leaving) {
            guard leaving else { return }
            do { try await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 400_000_000) } catch { return }
            guard !finished else { return }
            finished = true
            removeKeyMonitor()
            onFinish()
        }
    }

    private func start() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { _ in
            skip()
            return nil
        }
        SoundEffectService.shared.bind(to: settings)
        SoundEffectService.shared.play(.boot)
        withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.6)) { markIn = true }
    }

    /// Input during the intro ends it at once with the closing fade.
    func skip() { fadeOut() }

    private func fadeOut() {
        guard !leaving else { return }
        withAnimation(.easeIn(duration: reduceMotion ? 0.15 : 0.4)) { leaving = true }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
