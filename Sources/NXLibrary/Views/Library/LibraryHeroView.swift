import SwiftUI
import AppKit
import NXLibraryCore

struct LibraryHeroView: View {
    let game: PortedGame
    let presentation: LibraryPresentation
    let heroImage: NSImage?
    let logoImage: NSImage?
    let metrics: SeleneLayoutMetrics
    let size: CGSize
    let showClock: Bool
    let readiness: Bool
    let focusArea: LibraryFocusArea
    let actionIndex: Int
    let readableText: Bool
    let backgroundShade: Double
    let contentTopInset: CGFloat
    let showsDetails: Bool
    let reduceMotion: Bool
    let heroKey: String
    let onPlay: () -> Void
    let onDetails: () -> Void
    let onOptions: () -> Void

    init(game: PortedGame,
         presentation: LibraryPresentation,
         heroImage: NSImage?,
         logoImage: NSImage? = nil,
         metrics: SeleneLayoutMetrics,
         size: CGSize,
         showClock: Bool,
         readiness: Bool,
         focusArea: LibraryFocusArea,
         actionIndex: Int,
         readableText: Bool,
         backgroundShade: Double,
         contentTopInset: CGFloat,
         showsDetails: Bool,
         reduceMotion: Bool,
         heroKey: String,
         onPlay: @escaping () -> Void,
         onDetails: @escaping () -> Void,
         onOptions: @escaping () -> Void) {
        self.game = game
        self.presentation = presentation
        self.heroImage = heroImage
        self.logoImage = logoImage
        self.metrics = metrics
        self.size = size
        self.showClock = showClock
        self.readiness = readiness
        self.focusArea = focusArea
        self.actionIndex = actionIndex
        self.readableText = readableText
        self.backgroundShade = backgroundShade
        self.contentTopInset = contentTopInset
        self.showsDetails = showsDetails
        self.reduceMotion = reduceMotion
        self.heroKey = heroKey
        self.onPlay = onPlay
        self.onDetails = onDetails
        self.onOptions = onOptions
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackground
                .brightness(artBrightness)
                .overlay(Color.black.opacity(shadeWashOpacity))
                .overlay { scrims.opacity(readableText ? 1 : 0.80) }

            SeleneTheme.topScrim
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                if logoImage == nil, !presentation.eyebrow.isEmpty && !presentation.title.lowercased().hasPrefix(presentation.eyebrow.lowercased()) {
                    Text(presentation.eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .foregroundColor(SeleneTheme.ink.opacity(0.78))
                        .shadow(color: .black.opacity(0.85), radius: 6, y: 1)
                        .padding(.bottom, 9)
                }

                if let logoImage {
                    Image(nsImage: logoImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 440, maxHeight: 135, alignment: .leading)
                        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 3)
                        .padding(.bottom, 6)
                } else {
                    Text(displayTitle)
                        .font(.system(size: metrics.heroTitleSize, weight: .bold))
                        .tracking(-1.6)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: 720, alignment: .leading)
                        .shadow(color: .black.opacity(0.85), radius: 10, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.50), radius: 24, x: 0, y: 6)
                }

                chips
                    .padding(.top, logoImage != nil ? 10 : 15)

                actions
                    .padding(.top, 22)

                if showsDetails {
                    metadata
                        .padding(.top, 24)

                    if !presentation.summary.isEmpty {
                        Text(presentation.summary)
                            .font(.system(size: 12.5))
                            .foregroundColor(SeleneTheme.ink.opacity(0.88))
                            .lineSpacing(2)
                            .lineLimit(3)
                            .frame(maxWidth: 580, alignment: .leading)
                            .padding(.top, 16)
                            .shadow(color: .black.opacity(0.85), radius: 6, x: 0, y: 2)
                    }
                }

                warnings
                    .padding(.top, 12)
            }
            .padding(.leading, metrics.margin)
            .padding(.top, contentTopInset)
            .opacity(1)
            .offset(y: showsDetails ? 0 : 8)
            .allowsHitTesting(true)

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(readiness ? SeleneTheme.success : SeleneTheme.untested)
                                .frame(width: 6, height: 6)
                                .shadow(color: (readiness ? SeleneTheme.success : SeleneTheme.untested).opacity(0.7),
                                        radius: 6)
                            Text(readiness ? "Ready" : "Setup needed")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.3)
                                .textCase(.uppercase)
                                .foregroundColor(SeleneTheme.ink.opacity(0.66))
                        }
                        if showClock {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(context.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SeleneTheme.ink.opacity(0.86))
                            }
                        }
                    }
                    .padding(.trailing, metrics.margin)
                    .padding(.top, 22)
                    .shadow(color: .black.opacity(0.65), radius: 6, y: 1)
                }
                Spacer()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private var scrims: some View {
        ZStack {
            SeleneTheme.heroAmbientVignette
            SeleneTheme.heroLeftScrim
            SeleneTheme.heroBottomScrim
        }
    }

    private var shade: Double {
        min(max(backgroundShade, 0), 1)
    }

    private var shadeDelta: Double {
        shade - BackgroundShade.balanced.heroScrimOpacity
    }

    /// The balanced shade is the untouched baseline. Lighter settings lift the
    /// art; deeper settings add a soft black wash on top of it.
    private var artBrightness: Double {
        shadeDelta < 0 ? min(0.08, -shadeDelta * 0.25) : 0
    }

    private var shadeWashOpacity: Double {
        shadeDelta > 0 ? min(0.18, shadeDelta * 0.85) : 0
    }

    @ViewBuilder
    private var heroBackground: some View {
        ZStack {
            if let heroImage {
                Image(nsImage: heroImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .id(heroKey)
                    .transition(.opacity)
            } else {
                fallbackBackground
                    .id("fallback-\(game.id.uuidString)")
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.30), value: heroKey)
    }

    private var fallbackBackground: some View {
        ZStack {
            Image(nsImage: GameIconProvider.icon(for: game))
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .blur(radius: 42)
                .scaleEffect(1.18)
                .opacity(0.86)
            SeleneTheme.scrim.opacity(0.40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var chips: some View {
        HStack(spacing: 7) {
            ForEach(presentation.genres, id: \.self) { genre in
                chip(genre)
            }
            if let publisher = presentation.publisher {
                chip(publisher)
            }
            if let year = presentation.releaseYear {
                chip(year, monospaced: true)
            }
        }
    }

    private func chip(_ value: String, monospaced: Bool = false) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .medium,
                          design: monospaced ? .monospaced : .default))
            .foregroundColor(SeleneTheme.ink.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35))
            .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.24), lineWidth: 1))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.50), radius: 4, y: 1)
    }

    private var metadata: some View {
        HStack(alignment: .top, spacing: 30) {
            metadataItem("Play time", presentation.playtime)
            metadataItem("Last played", presentation.lastPlayed)
            metadataItem("Platform", presentation.platform)
            metadataItem("Released", presentation.releaseYear ?? "—")
        }
    }

    private func metadataItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.ink.opacity(0.65))
                .shadow(color: .black.opacity(0.85), radius: 4, y: 1)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.96))
                .shadow(color: .black.opacity(0.85), radius: 6, y: 1)
        }
        .frame(minWidth: 68, alignment: .leading)
    }

    private var isPlayable: Bool {
        game.isPlayableLocally
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                    Text("Play")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(isPlayable
                                 ? SeleneTheme.scrim
                                 : SeleneTheme.ink.opacity(0.62))
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(isPlayable
                            ? SeleneTheme.focus
                            : SeleneTheme.ink.opacity(0.10))
                .overlay(Capsule().strokeBorder(
                    SeleneTheme.ink.opacity(isPlayable ? 0 : 0.16),
                    lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .seleneRowFocus(focusArea == .actions && actionIndex == 0, radius: 22)
            .accessibilityLabel("Play \(game.name)")
            .accessibilityHint(isPlayable
                               ? "Launch the game"
                               : "Not built yet. Open Game options to build it.")

            Button(action: onDetails) {
                Text("Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.90))
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(SeleneTheme.glass.opacity(0.55))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.22), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .seleneRowFocus(focusArea == .actions && actionIndex == 1, radius: 22)
            .accessibilityLabel("Details for \(game.name)")

            Button(action: onOptions) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.88))
                    .frame(width: 44, height: 44)
                    .background(SeleneTheme.scrim.opacity(0.32))
                    .overlay(Circle().strokeBorder(SeleneTheme.ink.opacity(0.20), lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .seleneRowFocus(focusArea == .actions && actionIndex == 2, radius: 22)
            .accessibilityLabel("Game options")
        }
    }

    private var warnings: some View {
        HStack(spacing: 12) {
            if !isPlayable {
                HStack(spacing: 6) {
                    Label("Not built yet · open Game options to build",
                          systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SeleneTheme.untested.opacity(0.86))
                    SeleneInfoTip("This game has been added to your library catalog, but its native macOS app has not been compiled yet. Click the ellipsis (...) button to open Game options and build it.")
                }
            } else if presentation.sourcesDetached {
                HStack(spacing: 6) {
                    Label("Sources detached · playable", systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(SeleneTheme.untested.opacity(0.86))
                    SeleneInfoTip("The original ROM files (NSP/XCI) were moved or detached. The compiled macOS app in ~/Applications and all your save files remain fully playable.")
                }
            }
            if !game.toolchain.verified {
                HStack(spacing: 5) {
                    Text("Untested toolchain")
                        .font(.system(size: 9, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundColor(SeleneTheme.untested.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SeleneTheme.untested.opacity(0.10))
                        .overlay(Capsule().strokeBorder(SeleneTheme.untested.opacity(0.22), lineWidth: 1))
                        .clipShape(Capsule())
                    SeleneInfoTip("This build was compiled with the untested-toolchain override. Gameplay works, but graphical artifacts could occur on non-certified Metal compiler versions.")
                }
            }
        }
    }

    private var displayTitle: String {
        if !presentation.eyebrow.isEmpty {
            let prefixColon = presentation.eyebrow + ": "
            if presentation.title.hasPrefix(prefixColon) {
                return String(presentation.title.dropFirst(prefixColon.count))
            }
            let prefixDash = presentation.eyebrow + " – "
            if presentation.title.hasPrefix(prefixDash) {
                return String(presentation.title.dropFirst(prefixDash.count))
            }
        }
        return presentation.title
    }
}
