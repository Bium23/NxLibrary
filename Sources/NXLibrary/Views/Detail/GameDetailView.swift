import SwiftUI
import AppKit
import NXLibraryCore

struct GameDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var playSessions: PlaySessionStore
    @ObservedObject var artwork: ArtworkStore
    let game: PortedGame

    @State private var metadata: NintendoStoreMetadata?
    @State private var heroImage: NSImage?
    @State private var expanded = false

    private var presentation: GameDetailPresentation {
        GameDetailPresentation(
            game: game,
            metadata: metadata,
            totalPlaytime: playSessions.totalDuration(for: game.id),
            lastPlayed: playSessions.lastPlayed(for: game.id)
        )
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = SeleneLayoutMetrics(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                background(geo: geo)
                ScrollView {
                    content(metrics: metrics, width: min(760, geo.size.width * 0.58))
                        .padding(.leading, metrics.margin)
                        .padding(.top, 128)
                        .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)

                topBar(metrics: metrics)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .bottom) {
                if settings.settings.showButtonHints {
                    CommandBar([
                        .init("B", "Back"),
                        .init("Y", "Game options"),
                        .init("A", "Play"),
                        .init("X", "Rebuild")
                    ])
                }
            }
        }
        .onAppear {
            viewModel.loadStoreMetadata(for: game)
            metadata = viewModel.storeMetadata[game.id]
        }
        .onChange(of: viewModel.storeMetadata) { _ in
            metadata = viewModel.storeMetadata[game.id]
        }
        .task(id: game.id) {
            let meta = viewModel.storeMetadata[game.id]
            let remote = meta?.headerImageURL ?? meta?.imageURL
            let titleKey = game.titleId ?? game.uniqueKey
            let url = await artwork.fetch(titleID: titleKey, remoteURL: remote, kind: .hero)
            guard !Task.isCancelled else { return }
            heroImage = url.flatMap(NSImage.init(contentsOf:))
        }
    }

    private func background(geo: GeometryProxy) -> some View {
        ZStack {
            Group {
                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(nsImage: GameIconProvider.icon(for: game))
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 34)
                        .scaleEffect(1.2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(SeleneTheme.heroLeftScrim)
            .overlay(
                LinearGradient(colors: [.clear, .black.opacity(0.92)],
                               startPoint: .center, endPoint: .bottom)
            )
            .overlay(Color.black.opacity(0.10))
        }
    }

    private func topBar(metrics: SeleneLayoutMetrics) -> some View {
        HStack {
            Button {
                router.back()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Library")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(SeleneTheme.ink.opacity(0.78))
                .padding(.horizontal, 13)
                .frame(height: 32)
                .background(SeleneTheme.canvas.opacity(0.45))
                .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to library")

            Spacer()

            HStack(spacing: 14) {
                if settings.settings.showClock {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SeleneTheme.ink.opacity(0.8))
                    }
                }
            }
        }
        .padding(.horizontal, metrics.margin)
        .padding(.top, 34)
    }

    private func content(metrics: SeleneLayoutMetrics, width: CGFloat) -> some View {
        let p = presentation
        return VStack(alignment: .leading, spacing: 0) {
            if !p.eyebrow.isEmpty {
                Text(p.eyebrow)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundColor(SeleneTheme.ink.opacity(0.60))
                    .padding(.bottom, 8)
            }

            Text(p.title)
                .font(.system(size: 54, weight: .bold))
                .tracking(-1.4)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(2)
                .frame(maxWidth: width, alignment: .leading)

            chips(p)
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button {
                    viewModel.launchGame(game)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text("Play")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(SeleneTheme.canvas)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background(p.canPlay ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.16))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!p.canPlay)

                Button {
                    viewModel.gameForSettingsSheet = game
                } label: {
                    Text("Game options")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SeleneTheme.ink.opacity(0.9))
                        .padding(.horizontal, 20)
                        .frame(height: 42)
                        .background(SeleneTheme.ink.opacity(0.10))
                        .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.18), lineWidth: 1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 20)

            metadataRow(p)
                .padding(.top, 22)

            description(p, width: width)
                .padding(.top, 20)

            BuildSourcesPanel(
                presentation: p,
                onAttach: { viewModel.locateSources(for: game) },
                onRebuild: {
                    viewModel.startBuild(for: game)
                    router.openAddGame()
                },
                onRevealLog: { viewModel.revealLog(for: game) }
            )
            .padding(.top, 22)

            bottomCards(p)
                .padding(.top, 14)
        }
    }

    private func chips(_ p: GameDetailPresentation) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(p.genres.prefix(4)), id: \.self) { genre in
                Text(genre)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(genre == p.genres.first ? SeleneTheme.accent : SeleneTheme.ink.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((genre == p.genres.first ? SeleneTheme.accent : SeleneTheme.ink).opacity(0.08))
                    .overlay(Capsule().strokeBorder(
                        (genre == p.genres.first ? SeleneTheme.accent : SeleneTheme.ink).opacity(0.18),
                        lineWidth: 1))
                    .clipShape(Capsule())
            }
            if let publisher = p.publisher {
                Text(publisher)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(SeleneTheme.ink.opacity(0.62))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Capsule())
            }
            if let year = p.releaseYear {
                Text(year)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(SeleneTheme.ink.opacity(0.62))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.06))
                    .clipShape(Capsule())
            }
        }
    }

    private func metadataRow(_ p: GameDetailPresentation) -> some View {
        HStack(alignment: .top, spacing: 30) {
            detailMeta("Play time", p.playtime)
            detailMeta("Last played", p.lastPlayed)
            detailMeta("Version", p.version)
            detailMeta("Size", p.size)
        }
    }

    private func detailMeta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.ink.opacity(0.40))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.94))
        }
        .frame(minWidth: 64, alignment: .leading)
    }

    private func description(_ p: GameDetailPresentation, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if p.description.isEmpty {
                HStack(spacing: 10) {
                    Text("Store details unavailable.")
                        .font(.system(size: 12))
                        .foregroundColor(SeleneTheme.inkMuted)
                    if let search = viewModel.nintendoStoreSearchURL(for: game) {
                        Button("Search Nintendo Store") { viewModel.openURL(search) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.accent)
                    }
                }
            } else {
                Text(p.description)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundColor(SeleneTheme.ink.opacity(0.64))
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: width, alignment: .leading)
                if p.description.count > 220 {
                    Button(expanded ? "Show less" : "Read more") {
                        withAnimation(SeleneTheme.quick) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.accent)
                }
            }
        }
    }

    private func bottomCards(_ p: GameDetailPresentation) -> some View {
        HStack(spacing: 12) {
            detailCard(title: "SAVE FILES",
                       value: "Application Support",
                       subtitle: "Saves stay outside the app bundle.") {
                Button("Open folder") {
                    viewModel.revealSaveFolder(URL(fileURLWithPath: p.savePath))
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(SeleneTheme.accent)
            }

            detailCard(title: "APP BUNDLE",
                       value: game.url.lastPathComponent,
                       subtitle: p.size) {
                Button("Reveal") { viewModel.revealInFinder(url: game.url) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.accent)
            }

            detailCard(title: "STORE & LINKS",
                       value: "Nintendo Store",
                       subtitle: p.description.isEmpty ? "No cached description." : "Description cached locally.") {
                HStack(spacing: 10) {
                    if let store = p.storeURL {
                        Button("Store") { viewModel.openURL(store) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.accent)
                    }
                    if let hltb = p.hltbURL {
                        Button("HowLongToBeat") { viewModel.openURL(hltb) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: 760)
    }

    private func detailCard<Actions: View>(title: String, value: String,
                                           subtitle: String,
                                           @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.4)
                .foregroundColor(SeleneTheme.inkMuted)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundColor(SeleneTheme.ink.opacity(0.36))
                .lineLimit(1)
            actions()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.surface.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(SeleneTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
