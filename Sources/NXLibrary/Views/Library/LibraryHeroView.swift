import SwiftUI
import AppKit
import NXLibraryCore

struct LibraryHeroView: View {
    let game: PortedGame
    let presentation: LibraryPresentation
    let heroImage: NSImage?
    let metrics: SeleneLayoutMetrics
    let size: CGSize
    let showClock: Bool
    let readiness: Bool
    let onPlay: () -> Void
    let onDetails: () -> Void
    let onOptions: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
                .overlay(SeleneTheme.heroLeftScrim)
                .overlay(SeleneTheme.heroBottomScrim)
                .overlay(Color.black.opacity(0.14))

            VStack(alignment: .leading, spacing: 0) {
                if !presentation.eyebrow.isEmpty {
                    Text(presentation.eyebrow)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(2.4)
                        .textCase(.uppercase)
                        .foregroundColor(SeleneTheme.ink.opacity(0.68))
                        .padding(.bottom, 9)
                }

                Text(presentation.title)
                    .font(.system(size: metrics.heroTitleSize, weight: .bold))
                    .tracking(-1.6)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                    .frame(maxWidth: 720, alignment: .leading)
                    .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 4)

                chips
                    .padding(.top, 15)

                metadata
                    .padding(.top, 22)

                actions
                    .padding(.top, 21)

                warnings
                    .padding(.top, 14)
            }
            .padding(.leading, metrics.margin)
            .padding(.bottom, 248)

            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 14) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(readiness ? SeleneTheme.success : SeleneTheme.warning)
                                .frame(width: 6, height: 6)
                                .shadow(color: (readiness ? SeleneTheme.success : SeleneTheme.warning).opacity(0.7),
                                        radius: 6)
                            Text(readiness ? "Ready" : "Setup needed")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.3)
                                .textCase(.uppercase)
                                .foregroundColor(SeleneTheme.ink.opacity(0.56))
                        }
                        if showClock {
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(context.date.formatted(date: .omitted, time: .shortened))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(SeleneTheme.ink.opacity(0.82))
                            }
                        }
                    }
                    .padding(.trailing, metrics.margin)
                    .padding(.top, 26)
                }
                Spacer()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .clipped()
    }

    @ViewBuilder
    private var heroBackground: some View {
        if let heroImage {
            Image(nsImage: heroImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Image(nsImage: GameIconProvider.icon(for: game))
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 34)
                    .scaleEffect(1.25)
                SeleneTheme.canvas.opacity(0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    private var chips: some View {
        HStack(spacing: 7) {
            ForEach(presentation.genres, id: \.self) { genre in
                Text(genre)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.08))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.12), lineWidth: 1))
                    .clipShape(Capsule())
            }
            if let publisher = presentation.publisher {
                Text(publisher)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SeleneTheme.ink.opacity(0.64))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Capsule())
            }
            if let year = presentation.releaseYear {
                Text(year)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink.opacity(0.64))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
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
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.ink.opacity(0.42))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.94))
        }
        .frame(minWidth: 68, alignment: .leading)
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
                .foregroundColor(SeleneTheme.canvas)
                .padding(.horizontal, 24)
                .frame(height: 42)
                .background(SeleneTheme.focus)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDetails) {
                Text("Details")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.92))
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(SeleneTheme.ink.opacity(0.10))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.18), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onOptions) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.88))
                    .frame(width: 42, height: 42)
                    .background(SeleneTheme.ink.opacity(0.10))
                    .overlay(Circle().strokeBorder(SeleneTheme.ink.opacity(0.18), lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Game options")
        }
    }

    private var warnings: some View {
        HStack(spacing: 14) {
            if presentation.sourcesDetached {
                Label("Sources detached · playable", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SeleneTheme.warning.opacity(0.86))
            }
            if !game.toolchain.verified {
                Text("Untested toolchain")
                    .font(.system(size: 9, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundColor(SeleneTheme.warning.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SeleneTheme.warning.opacity(0.10))
                    .overlay(Capsule().strokeBorder(SeleneTheme.warning.opacity(0.22), lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
    }
}
