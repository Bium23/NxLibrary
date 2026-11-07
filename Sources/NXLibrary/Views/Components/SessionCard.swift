import AppKit
import SwiftUI
import NXLibraryCore

/// Holds the session card: the latest ended session waits until NX Library is in front, shows 1.8 s later for 8 s,
/// then leaves. A newer session replaces one still waiting or showing.
@MainActor
final class SessionCardPresenter: ObservableObject {
    static let delay: UInt64 = 1_800_000_000
    static let hold: UInt64 = 8_000_000_000

    @Published private(set) var shown: SessionSummary?
    private var pending: SessionSummary?
    private var task: Task<Void, Never>?

    /// A game closed; `enabled` is the Session card switch.
    func ended(_ summary: SessionSummary?, enabled: Bool) {
        guard enabled, let summary else { return }
        pending = summary
        if NSApp.isActive { schedule() }
    }

    /// NX Library came forward: a waiting card shows.
    func becameActive() {
        if pending != nil { schedule() }
    }

    /// The switch went off: nothing waiting or showing stays.
    func clear() {
        task?.cancel()
        task = nil
        pending = nil
        shown = nil
    }

    private func schedule() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.delay)
            guard let self, !Task.isCancelled, NSApp.isActive, let summary = self.pending else { return }
            self.pending = nil
            self.shown = summary
            SoundEffectService.shared.play(.success)
            try? await Task.sleep(nanoseconds: Self.hold)
            guard !Task.isCancelled else { return }
            self.shown = nil
        }
    }
}

/// Selene's session card: "Session ended", the game's name and this session · total on the left, the logo on the
/// right, the game's art faint behind. 640 × 128 units, top right; it takes no input.
struct SessionCardView: View {
    @Environment(\.seleneCanvas) private var canvas
    let summary: SessionSummary
    let game: PortedGame?
    let metadata: NintendoStoreMetadata?
    let artwork: ArtworkStore

    @State private var hero: NSImage?
    @State private var logo: NSImage?

    var body: some View {
        ZStack(alignment: .leading) {
            if let hero {
                Image(nsImage: hero)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: canvas.u(640), height: canvas.u(128))
                    .clipped()
                    .opacity(0.42)
                    // Faint on the right, gone under the words on the left.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0.15),
                                                 .init(color: .black, location: 0.85)],
                                         startPoint: .leading, endPoint: .trailing))
            }
            HStack(spacing: canvas.u(16)) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Session ended")
                        .seleneFont(15)
                        .foregroundColor(SeleneTheme.ink.opacity(0.62))
                    Text(summary.gameName)
                        .seleneFont(22, .semibold)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, canvas.u(2))
                        .padding(.bottom, canvas.u(8))
                    HStack(alignment: .lastTextBaseline, spacing: canvas.u(12)) {
                        figure(summary.thisSession, "this session")
                        Text("·")
                            .seleneFont(18)
                            .foregroundColor(SeleneTheme.ink.opacity(0.45))
                        figure(summary.total, "total")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let logo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: canvas.u(170), maxHeight: canvas.u(88))
                        .shadow(color: .black.opacity(0.6), radius: canvas.u(5))
                        .padding(.trailing, canvas.u(4))
                }
            }
            .padding(.leading, canvas.u(20))
            .padding(.trailing, canvas.u(18))
        }
        .frame(width: canvas.u(640), height: canvas.u(128))
        .background(Color(hex: ThemeStore.shared.palette.glass, opacity: 0.92))
        .clipShape(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
            .strokeBorder(SeleneTheme.ink.opacity(0.12), lineWidth: max(1, canvas.u(1))))
        .shadow(color: .black.opacity(0.45), radius: canvas.u(18))
        .environment(\.seleneMinimumFont, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session ended, \(summary.gameName): \(summary.thisSession) this session, \(summary.total) total")
        .task(id: summary.id) { await loadArt() }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: canvas.u(7)) {
            Text(value)
                .seleneFont(20, .semibold)
                .foregroundColor(SeleneTheme.ink)
            Text(label)
                .seleneFont(15)
                .foregroundColor(SeleneTheme.ink.opacity(0.6))
        }
        .lineLimit(1)
        .fixedSize()
    }

    /// The art the game's pages already loaded, else the same lookups they use.
    @MainActor
    private func loadArt() async {
        guard let game else { return }
        hero = GameArtLoader.shared.cachedHero(for: game)
        logo = GameArtLoader.shared.cachedLogo(for: game)
        if hero == nil {
            let loaded = await GameArtLoader.shared.hero(for: game, metadata: metadata, artwork: artwork)
            withAnimation(.easeOut(duration: 0.3)) { hero = loaded }
        }
        if logo == nil {
            let loaded = await GameArtLoader.shared.logo(for: game, metadata: metadata, artwork: artwork)
            withAnimation(.easeOut(duration: 0.3)) { logo = loaded }
        }
    }
}

/// The session card's place on the screen: 112 units from the top, 28 from the right, sliding in from the right with a
/// fade as Selene's cards do. It never takes clicks or focus.
struct SessionCardLayer: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var presenter: SessionCardPresenter
    let games: [PortedGame]
    let metadata: [UUID: NintendoStoreMetadata]
    let artwork: ArtworkStore

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let summary = presenter.shown {
                SessionCardView(summary: summary,
                                game: games.first { $0.id == summary.gameID },
                                metadata: metadata[summary.gameID],
                                artwork: artwork)
                    .id(summary.id)
                    .padding(.top, canvas.u(112))
                    .padding(.trailing, canvas.u(28))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: canvas.u(40))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.25), value: presenter.shown?.id)
    }
}
