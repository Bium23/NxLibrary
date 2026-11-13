import SwiftUI
import AppKit
import NXLibraryCore

struct CatalogSteamDetailsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettingsStore
    let game: CatalogGame
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @State private var metadata: SteamMetadata?
    @State private var editing = false
    @State private var gallery: Int?
    @ObservedObject private var picks = SteamPersonalizations.shared.metadata
    @State private var focus = 0
    @State private var keyMonitor: Any?
    private var installation: SteamCatalogInstallation? {
        let current = viewModel.catalogGames.first { $0.id == game.id }?.steamGame
        return current?.installations.first { $0.availability == .available } ?? current?.installations.first
    }
    private var status: String {
        if game.steamGame?.needsInstallationReview == true { return L10n.text("Needs review", context: localization) }
        switch installation?.availability {
        case .available: return L10n.text("Available on this Mac", context: localization)
        case .sourceUnavailable: return L10n.text("Source unavailable", context: localization)
        case .notDetected, .unavailable, nil: return L10n.text("Installation not detected", context: localization)
        case .requiresReview: return L10n.text("Needs review", context: localization)
        }
    }
    var body: some View {
        SeleneHomeChrome(leftHints: [HintItem(.b, L10n.text("Back", context: localization)) { router.back() }],
                         rightHints: [HintItem(.y, L10n.text("Game sources", context: localization)) { router.openSettings(.sources) }, HintItem(.a, L10n.text("Select", context: localization))],
                         hintsHidden: router.overlayHasHints(viewModel), backdrop: {
                             SteamBackdrop(game: game, shade: settings.settings.backgroundShade,
                                           showsArt: !settings.settings.keepWallpaperOnGames)
                         }, stage: {
            ScrollViewReader { proxy in
            ScrollView { LazyVStack(alignment: .leading, spacing: canvas.u(30)) {
                HStack(alignment: .top, spacing: canvas.u(44)) {
                    CatalogNativeArtwork(game: game).frame(width: canvas.u(240), height: canvas.u(240))
                        .clipShape(RoundedRectangle(cornerRadius: canvas.u(18)))
                    VStack(alignment: .leading, spacing: canvas.u(18)) {
                        SteamArtwork(game: game, slot: .logo).frame(width: canvas.u(340), height: canvas.u(80))
                        Text(game.name).seleneFont(40, .semibold).foregroundColor(SeleneTheme.ink).lineLimit(2)
                        HStack { SteamArtwork(game: game, slot: .icon).frame(width: canvas.u(32), height: canvas.u(32)); Text("Steam · Mac").seleneFont(18, .semibold).foregroundColor(SeleneTheme.ink60) }
                        Text(status).seleneFont(18).foregroundColor(SeleneTheme.ink60)
                        if let bytes = installation?.reportedSizeBytes {
                            Text(L10n.format("Size reported by Steam: %@", [seleneBytes(bytes)], context: localization))
                                .seleneFont(16).foregroundColor(SeleneTheme.ink60)
                        }
                    }
                }
                .id("top")
                HStack(spacing: canvas.u(14)) {
                    SelenePillButton(title: "Reveal in Finder", focused: focus == 0) { perform(0) }
                    SelenePillButton(title: game.isFavorite ? "Unfavorite" : "Favorite", focused: focus == 1) { perform(1) }
                    SelenePillButton(title: "Hide", focused: focus == 2) { perform(2) }
                    SelenePillButton(title: "Move in row", focused: focus == 3) { perform(3) }
                }
                HStack(spacing: canvas.u(14)) {
                    SelenePillButton(title: "Open in Steam", focused: focus == 4) { perform(4) }
                    SelenePillButton(title: "Personalize", focused: focus == 5) { perform(5) }
                }
                Group {
                    ForEach(MetadataField.allCases, id: \.self) { field in
                        if let value = fieldValue(field, metadata), !value.isEmpty {
                            VStack(alignment: .leading, spacing: canvas.u(8)) {
                                Text(field.title).seleneFont(16, .semibold).foregroundColor(SeleneTheme.ink60)
                                Text(value).seleneFont(19).foregroundColor(SeleneTheme.ink).textSelection(.enabled)
                            }
                        }
                    }
                    ForEach(Array((metadata?.screenshots ?? []).enumerated()), id: \.offset) { index, url in
                        Button { gallery = index } label: {
                            SteamArtwork(game: game, slot: .background, remote: url)
                                .frame(width: canvas.u(600), height: canvas.u(338))
                                .overlay(SeleneTileRing(cornerRadius: canvas.u(12), active: focus == index + 6))
                        }.buttonStyle(.plain).id(index + 6)
                    }
                }
                if let installation {
                    Text(L10n.text("Installation", context: localization)).seleneFont(17, .semibold).foregroundColor(SeleneTheme.ink)
                    Text(installation.contentURL.path).seleneFont(16).foregroundColor(SeleneTheme.ink60)
                        .lineLimit(3).textSelection(.enabled)
                }
                Color.clear.frame(height: canvas.u(80))
            }
            .padding(.horizontal, canvas.u(80)).padding(.top, canvas.u(130))
            .frame(maxWidth: .infinity, alignment: .leading)
            }.onChange(of: focus) { value in if value >= 6 { proxy.scrollTo(value, anchor: .center) } else { proxy.scrollTo("top", anchor: .top) } }
            }.frame(width: canvas.stageSize.width, height: canvas.size.height, alignment: .topLeading)
        })
        .task(id: "\(game.id)|\(localization.language.rawValue)") {
            metadata = nil; gallery = nil; focus = 0
            guard let id = game.steamGame?.appID else { return }
            let result = await SteamMetadataService.shared.metadata(appID: id, language: SteamMetadata.language(localization.language))
            guard !Task.isCancelled else { return }; metadata = result
        }
        .sheet(isPresented: $editing) { SteamPersonalizationEditor(game: game) }
        .overlay { if let index = gallery, let shots = metadata?.screenshots, shots.indices.contains(index) {
            ZStack {
                Color.black.opacity(0.96)
                VStack {
                    SteamArtwork(game: game, slot: .background, remote: shots[index]).aspectRatio(16/9, contentMode: .fit)
                    HStack {
                        Button("‹") { gallery = max(0, index - 1) }
                        Text("\(index + 1) / \(shots.count)")
                        Button("›") { gallery = min(shots.count - 1, index + 1) }
                        Button(L10n.text("Close", context: localization)) { gallery = nil }
                    }.padding()
                }.padding(50)
            }
        } }
        .onAppear(perform: installKeyboard)
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil }
        .onReceive(NotificationCenter.default.publisher(for: .nxDetailGamepadAction)) { note in
            guard router.route == .detail(game.id), !router.isMenuPresented, !router.isSearchPresented,
                  !router.isIntroShowing, !editing, viewModel.settingsNotice == nil, viewModel.alertMessage == nil,
                  !viewModel.showSetupCheck, !viewModel.isUpdateOfferOpen, NSApp.modalWindow == nil,
                  let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }
    private func perform(_ index: Int) {
        switch index {
        case 0:
            guard let location = installation?.contentURL, FileManager.default.fileExists(atPath: location.path) else {
                viewModel.showSettingsNotice(title: L10n.text("Installation not detected", context: localization), message: L10n.text("Refresh the Steam source or check the installation in Steam.", context: localization))
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([location])
        case 1: viewModel.setCatalogFavorite(game)
        case 2: if viewModel.setCatalogHidden(true, game: game) { router.showLibrary() }
        case 3:
            router.requestSpotlightMove(SpotlightItem.game(game.id).key)
            router.showLibrary()
        case 4: if let id = game.steamGame?.appID { NSWorkspace.shared.open(URL(string: "https://store.steampowered.com/app/\(id)/")!) }
        case 5: editing = true
        default: if let count = metadata?.screenshots.count, (0..<count).contains(index - 6) { gallery = index - 6 }
        }
    }
    private func fieldValue(_ field: MetadataField, _ data: SteamMetadata?) -> String? {
        if let value = picks.value(titleID: game.personalizationReference.key, field: field) { return value }
        switch field {
        case .description: return data?.description
        case .genres: return data?.genres.joined(separator: " · ")
        case .developer: return data?.developers.joined(separator: ", ")
        case .publisher: return data?.publishers.joined(separator: ", ")
        case .releaseDate: return data?.releaseDate
        }
    }
    private func handle(_ action: GamepadAction) {
        if let index = gallery {
            switch action {
            case .navigateLeft: gallery = max(0, index - 1)
            case .navigateRight: gallery = min((metadata?.screenshots.count ?? 1) - 1, index + 1)
            case .cancel, .confirm: gallery = nil
            default: break
            }
            return
        }
        switch action {
        case .navigateDown: focus = min(5 + (metadata?.screenshots.count ?? 0), focus < 4 ? focus + 4 : max(6, focus + 1))
        case .navigateUp: focus = focus >= 6 ? max(4, focus - 1) : max(0, focus - 4)
        case .navigateLeft: focus = max(0, focus - 1)
        case .navigateRight: focus = min(5 + (metadata?.screenshots.count ?? 0), focus + 1)
        case .confirm: perform(focus)
        case .cancel: router.back()
        case .contextAction: router.openSettings(.sources)
        default: break
        }
    }
    private func installKeyboard() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard router.route == .detail(game.id), !router.isMenuPresented, !router.isSearchPresented,
                  !router.isIntroShowing, !editing, !NativeMenuCommands.shared.isTracking,
                  viewModel.settingsNotice == nil, viewModel.alertMessage == nil,
                  !viewModel.isUpdateOfferOpen, !viewModel.showSetupCheck,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53 where gallery != nil: gallery = nil
            case 125: handle(.navigateDown)
            case 126: handle(.navigateUp)
            case 123: handle(.navigateLeft)
            case 124: handle(.navigateRight)
            case 36, 49: handle(.confirm)
            case 16: handle(.contextAction)
            default: return event
            }
            return nil
        }
    }
}
