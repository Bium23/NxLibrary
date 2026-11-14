import SwiftUI
import AppKit
import NXLibraryCore

public struct LaunchOverlayState: Equatable {
    public let game: PortedGame
    public var isReady = false

    public init(game: PortedGame, isReady: Bool = false) {
        self.game = game
        self.isReady = isReady
    }
}

/// Selene's launch screen: art and logo while the game starts, then fade to black and out
/// once the game's window is on screen (`LaunchReadinessProbe`).
struct LaunchScreenView: View {
    let state: LaunchOverlayState
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var artwork: ArtworkStore
    let settings: AppSettings
    let reduceMotion: Bool

    @Environment(\.seleneCanvas) private var canvas
    @State private var hero: NSImage?
    @State private var logo: NSImage?
    @State private var shown = false
    @State private var drift = false
    @State private var blackout = false
    @State private var leaving = false
    @State private var breathe = false

    private var game: PortedGame { state.game }

    private var shadeOpacity: Double {
        switch settings.launchShade {
        case .none: return 0
        case .soft: return 0.35
        case .dark: return 0.6
        }
    }

    private var showsArt: Bool {
        settings.launchStyle == .artAndLogo || settings.launchStyle == .artOnly
    }

    var body: some View {
        ZStack {
            Color.black
            if showsArt {
                art
            }
            centrePiece
            Color.black.opacity(blackout ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) { mark }
        .ignoresSafeArea()
        .opacity(shown && !leaving ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Starting %@", [String(describing: (game.name))]))
        .onAppear(perform: appear)
        .onChange(of: state.isReady) { ready in
            if ready { finish() }
        }
        .task(id: game.id) { await loadArt() }
    }

    private var art: some View {
        GeometryReader { geo in
            if let hero {
                Image(nsImage: hero)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .scaleEffect(drift ? 1.06 : 1.0)
                    .clipped()
                    .transition(.opacity)
            }
            Color.black.opacity(shadeOpacity)
        }
    }

    @ViewBuilder private var centrePiece: some View {
        switch settings.launchStyle {
        case .artOnly:
            EmptyView()
        case .artAndLogo, .logoOnBlack:
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: canvas.u(720), maxHeight: canvas.u(320))
                    .shadow(color: .black.opacity(0.5), radius: canvas.u(18))
            } else {
                title
            }
        case .minimal:
            title
        }
    }

    private var title: some View {
        Text(game.name)
            .seleneFont(34, .semibold)
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, canvas.u(120))
    }

    private var mark: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: canvas.u(56), height: canvas.u(56))
            .opacity(breathe ? 1 : 0.45)
            .padding(.trailing, canvas.u(64))
            .padding(.bottom, canvas.u(56))
            .accessibilityHidden(true)
    }

    private func appear() {
        hero = GameArtLoader.shared.cachedHero(for: game)
        logo = GameArtLoader.shared.cachedLogo(for: game)
        withAnimation(.easeOut(duration: 0.25)) { shown = true }
        if settings.launchMotion && !reduceMotion {
            withAnimation(.linear(duration: 20)) { drift = true }
        }
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        } else {
            breathe = true
        }
    }

    private func finish() {
        guard !leaving, !blackout else { return }
        withAnimation(.easeIn(duration: 0.3)) { blackout = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) { leaving = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if viewModel.launchOverlay?.game.id == game.id {
                    viewModel.dismissLaunchOverlay()
                }
            }
        }
    }

    @MainActor
    private func loadArt() async {
        let metadata = viewModel.storeMetadata[game.id]
        if hero == nil, showsArt {
            let loaded = await GameArtLoader.shared.hero(
                for: game, metadata: metadata, artwork: artwork, personalizations: viewModel.personalizations)
            withAnimation(.easeOut(duration: 0.3)) { hero = loaded }
        }
        if logo == nil, settings.launchStyle != .minimal, settings.launchStyle != .artOnly {
            let loaded = await GameArtLoader.shared.logo(
                for: game, metadata: metadata, artwork: artwork, personalizations: viewModel.personalizations)
            withAnimation(.easeOut(duration: 0.3)) { logo = loaded }
        }
    }
}
