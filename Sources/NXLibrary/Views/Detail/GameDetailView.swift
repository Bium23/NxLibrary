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
    @State private var actionFocus = 0
    @Environment(\.seleneReduceMotion) private var environmentReduceMotion

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
                    content(metrics: metrics, geo: geo)
                        .padding(.horizontal, metrics.margin)
                        .padding(.top, 120)
                        .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)

                topBar(metrics: metrics)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .bottom) {
                if settings.settings.showButtonHints {
                    SeleneHintsBar(right: [
                        HintItem(.a, "Play"),
                        HintItem(.b, "Back"),
                        HintItem(.x, "Game options"),
                        HintItem(.y, "Rebuild")
                    ])
                }
            }
        }
        .onAppear {
            viewModel.loadStoreMetadata(for: game)
            metadata = viewModel.storeMetadata[game.id]
        }
        .onMoveCommand(perform: handleMove)
        .seleneActivationKeys(activateFocused)
        .onReceive(NotificationCenter.default.publisher(for: .nxDetailGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
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
                .background(SeleneTheme.scrim.opacity(0.45))
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

    private func content(metrics: SeleneLayoutMetrics, geo: GeometryProxy) -> some View {
        let p = presentation
        let wide = geo.size.width >= 1360
        let width = wide
            ? min(820, geo.size.width - metrics.margin * 2 - 396)
            : min(820, geo.size.width * 0.64)
        return HStack(alignment: .top, spacing: 36) {
            VStack(alignment: .leading, spacing: 0) {
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
                        .foregroundColor(p.canPlay ? SeleneTheme.scrim : SeleneTheme.ink.opacity(0.62))
                        .padding(.horizontal, 24)
                        .frame(height: 42)
                        .background(p.canPlay ? SeleneTheme.focus : SeleneTheme.ink.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!p.canPlay)
                    .seleneRowFocus(actionFocus == 0, radius: 100)

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
                            .seleneRowFocus(actionFocus == 1, radius: 100)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)

                metadataRow(p)
                    .padding(.top, 22)

                description(p, width: width)
                    .padding(.top, 20)

                if !wide {
                    BuildSourcesPanel(
                        presentation: p,
                        isRebuildFocused: actionFocus == 2,
                        onAttach: { viewModel.locateSources(for: game) },
                        onRebuild: rebuild,
                        onRevealLog: { viewModel.revealLog(for: game) }
                    )
                    .padding(.top, 22)

                    bottomCards(p, vertical: false)
                        .padding(.top, 14)
                }
            }
            .frame(width: width, alignment: .leading)

            if wide {
                VStack(spacing: 12) {
                    BuildSourcesPanel(
                        presentation: p,
                        isRebuildFocused: actionFocus == 2,
                        onAttach: { viewModel.locateSources(for: game) },
                        onRebuild: rebuild,
                        onRevealLog: { viewModel.revealLog(for: game) }
                    )
                    bottomCards(p, vertical: true)
                }
                .frame(width: 360)
            }

            Spacer(minLength: 0)
        }
    }

    private func chips(_ p: GameDetailPresentation) -> some View {
        HStack(spacing: 7) {
            ForEach(Array(p.genres.prefix(4)), id: \.self) { genre in
                Text(genre)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(SeleneTheme.ink.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(SeleneTheme.ink.opacity(0.07))
                    .overlay(Capsule().strokeBorder(SeleneTheme.ink.opacity(0.16), lineWidth: 1))
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
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(SeleneTheme.ink.opacity(0.58))
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
                        .foregroundColor(SeleneTheme.ink60)
                    if let search = viewModel.nintendoStoreSearchURL(for: game) {
                        Button("Search Nintendo Store") { viewModel.openURL(search) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(SeleneTheme.glyph)
                    }
                }
            } else {
                Text(p.description)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundColor(SeleneTheme.ink.opacity(0.72))
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: width, alignment: .leading)
                if p.description.count > 220 {
                    Button(expanded ? "Show less" : "Read more") {
                        withAnimation((settings.settings.reduceMotion || environmentReduceMotion)
                                      ? nil : SeleneTheme.quick) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
    }

    @ViewBuilder
    private func bottomCards(_ p: GameDetailPresentation, vertical: Bool) -> some View {
        if vertical {
            VStack(spacing: 12) {
                saveCard(p)
                appCard(p)
                storeCard(p)
            }
        } else {
            HStack(spacing: 12) {
                saveCard(p)
                appCard(p)
                storeCard(p)
            }
        }
    }

    private func saveCard(_ p: GameDetailPresentation) -> some View {
        detailCard(title: "SAVE FILES",
                   value: "Application Support",
                   subtitle: "Saves stay outside the app bundle.") {
            Button("Open folder") {
                viewModel.revealSaveFolder(URL(fileURLWithPath: p.savePath))
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(SeleneTheme.glyph)
        }
    }

    private func appCard(_ p: GameDetailPresentation) -> some View {
        detailCard(title: "APP BUNDLE",
                   value: game.url.lastPathComponent,
                   subtitle: p.size) {
            Button("Reveal") { viewModel.revealInFinder(url: game.url) }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(SeleneTheme.glyph)
        }
    }

    private func storeCard(_ p: GameDetailPresentation) -> some View {
        detailCard(title: "STORE & LINKS",
                   value: "Nintendo Store",
                   subtitle: p.description.isEmpty ? "No cached description." : "Description cached locally.") {
            HStack(spacing: 10) {
                if let store = p.storeURL {
                    Button("Store") { viewModel.openURL(store) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.glyph)
                }
                if let hltb = p.hltbURL {
                    Button("HowLongToBeat") { viewModel.openURL(hltb) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
    }

    private func detailCard<Actions: View>(title: String, value: String,
                                           subtitle: String,
                                           @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundColor(SeleneTheme.ink60)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(SeleneTheme.ink.opacity(0.88))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(SeleneTheme.ink.opacity(0.58))
                .lineLimit(1)
            actions()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SeleneTheme.glass.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: SeleneTheme.contentRadius, style: .continuous)
                .strokeBorder(SeleneTheme.ink15, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: SeleneTheme.contentRadius, style: .continuous))
    }

    private func moveFocus(by delta: Int) {
        let previous = actionFocus
        actionFocus = (actionFocus + delta + 3) % 3
        if actionFocus != previous {
            SoundEffectService.shared.play(.focus)
        }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        switch direction {
        case .left, .up: moveFocus(by: -1)
        case .right, .down: moveFocus(by: 1)
        default: break
        }
    }

    private func handleGamepad(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateUp: moveFocus(by: -1)
        case .navigateRight, .navigateDown: moveFocus(by: 1)
        case .confirm: activateFocused()
        case .cancel: router.back()
        case .secondaryAction: viewModel.gameForSettingsSheet = game
        case .contextAction: rebuild()
        case .menu: router.isMenuPresented = true
        default: break
        }
    }

    private func activateFocused() {
        switch actionFocus {
        case 0:
            guard presentation.canPlay else {
                SoundEffectService.shared.play(.error)
                return
            }
            SoundEffectService.shared.play(.click)
            viewModel.launchGame(game)
        case 1:
            SoundEffectService.shared.play(.click)
            viewModel.gameForSettingsSheet = game
        case 2:
            rebuild()
        default:
            break
        }
    }

    private func rebuild() {
        guard presentation.canRebuild else {
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        viewModel.startBuild(for: game)
        if viewModel.isBuilding {
            router.openAddGame()
        }
    }
}
