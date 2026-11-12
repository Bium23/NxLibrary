import SwiftUI
import AppKit
import NXLibraryCore

extension Notification.Name {
    static let nxIntroSkip = Notification.Name("NXIntroSkip")
}

/// The cold-launch intro: the backdrop's flow with the boot cue, held briefly, then faded out over the library.
/// No icon and no wordmark for now; a designed opening animation may replace it later.
/// Any key, click or controller input skips it.
struct IntroView: View {
    let settings: AppSettingsStore
    let reduceMotion: Bool
    let onFinish: () -> Void

    @State private var leaving = false
    @State private var finished = false
    @State private var keyMonitor: Any?

    var body: some View {
        ZStack {
            SeleneBackdrop()
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.text("NX Library"))
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
