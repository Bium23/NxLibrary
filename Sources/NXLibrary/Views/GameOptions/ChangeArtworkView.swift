import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore
import ArcanePorting

/// Game options → Edit details → Change artwork, after Playnite's artwork picker.
/// Tabs for Cover, Background, Icon and Logo; each shows Automatic, the player's
/// pick, a "Browse online" tile for LaunchBox and for SteamGridDB, then every image GameTDB,
/// Title DB, the Nintendo store and the online sources (`OnlineArtwork`: stores, databases,
/// wikis, Wallhaven) offer, with its size in pixels, and From file….
/// A choice is kept in `ArtworkPicks` and never overwritten by automatic art; Automatic takes it back.
/// A Steam game (`PersonalizationSubject`) gets Steam's own art for its AppID instead of the Switch
/// sources, keeps its choices in the Steam personal store and has no Mac app icon step.
///
/// Browsing a source replaces the grid with that source's images for the open tab, as the Theme screen browses
/// wallpaper sites: a search prefilled with the game's name, each image credited with its kind or author and its
/// full size. Only previews load; the full image downloads when chosen. SteamGridDB asks for the player's key first.
///
/// Input: arrows or the stick move in the grid (up from the first row reaches the search field while browsing),
/// L/R (Q/E) change the tab, A chooses, X opens the source's page while browsing, B (or Esc) goes back.
/// A click chooses.
struct ChangeArtworkView: View {
    @ObservedObject var viewModel: AppViewModel
    /// The game's app icon: its status line follows the icon being written.
    @ObservedObject var appIcon: AppIconModel
    /// The Nintendo store's data (`StoreMetadataModel`): descriptions, screenshots and names shown here.
    @ObservedObject var store: StoreMetadataModel
    let subject: PersonalizationSubject
    let onClose: () -> Void

    init(viewModel: AppViewModel, subject: PersonalizationSubject, onClose: @escaping () -> Void) {
        self.viewModel = viewModel
        _appIcon = ObservedObject(wrappedValue: viewModel.appIcon)
        _store = ObservedObject(wrappedValue: viewModel.store)
        self.subject = subject
        self.onClose = onClose
    }

    @ObservedObject private var picks = ArtworkPicks.shared
    @ObservedObject private var steamPicks = SteamPersonalizations.shared.artwork
    @State var slot: ArtworkSlot = .cover
    /// The focused tile; while browsing, -1 is the search field.
    @State var focus = 0
    /// Images found per slot, in the order the picker lists them, with small previews.
    @State var found: [ArtworkSlot: [Found]] = [:]
    @State var searching: Set<ArtworkSlot> = []
    @State var titleDB: TitleDBInfo?
    @State var titleDBLoaded = false
    /// Everything the online sources have for this game, every slot, looked up once.
    @State var online: [ArtworkCandidate]?
    @State var pickPreview: NSImage?
    @State var automaticIconPreview: NSImage?
    @State var automaticIconChecked = false
    @State var message: String?
    @State var keyMonitor: Any?

    // Browsing a source
    @State var browsing: ArtworkBrowseSource?
    /// SteamGridDB, waiting for its key dialog.
    @State var pendingBrowse: ArtworkBrowseSource?
    /// The name searched, and the field's text.
    @State var browseQuery = ""
    @State var browseDraft = ""
    /// Raised by every search, so an answer for an older one is dropped.
    @State var browseRound = 0
    @State var browseResult: ArtworkBrowseSource.Found?
    @State var browseItems: [ArtworkSlot: [Found]] = [:]
    @State var browseLoading: Set<ArtworkSlot> = []
    @State var downloading = false
    /// Image source and destination are independent; the same destination dialog is available for Automatic.
    @State var askAppIcon = false
    @State var editingIconLocation = false
    @State var appIconFocus: SeleneConfirmButton = .confirm
    /// The main grid's focus, restored on leaving a source.
    @State var mainFocus = 0
    @FocusState var fieldFocused: Bool

    @Environment(\.seleneCanvas) var canvas
    @Environment(\.seleneReduceMotion) var reduceMotion

    struct Found: Equatable {
        let order: Int
        let art: LoadedArtwork
        let preview: NSImage
    }

    enum Tile: Equatable {
        case automatic, yourPick, iconLocation, art(Found), browse(ArtworkBrowseSource), file
    }

    var hasPick: Bool { subject.artworkURL(slot) != nil }
    private var pickRevision: Int { picks.revision &+ steamPicks.revision }
    var switch2: Bool { subject.titleId?.hasPrefix("04") == true }
    /// The installed nxnative game: only it has a Mac app icon to change.
    var macApp: PortedGame? { subject.ported }
    var gameNames: [String] {
        let metadata = store.storeMetadata[subject.id]
        return [subject.name, metadata?.name, titleDB?.name].compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    var tiles: [Tile] {
        if browsing != nil { return (browseItems[slot] ?? []).map(Tile.art) }
        // The sources to browse come right after Automatic (and Your pick), so a search is one move away and never
        // waits for the found images to load; From file… ends the grid.
        return [.automatic] + (hasPick ? [.yourPick] : []) + (slot == .icon && macApp != nil ? [.iconLocation] : []) + ArtworkBrowseSource.allCases.map(Tile.browse)
            + (found[slot] ?? []).map(Tile.art) + [.file]
    }

    // MARK: - Geometry (Selene units)

    var columns: Int {
        switch slot {
        case .cover, .icon: return 6
        case .background, .logo: return 3
        }
    }

    var tileSize: CGSize {
        switch slot {
        case .cover: return CGSize(width: 160, height: 160 / BoxArt.aspectRatio)
        case .icon: return CGSize(width: 180, height: 180)
        case .background, .logo: return CGSize(width: 352, height: 198)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { back() }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(browsing.map { L10n.format("%@ · BROWSE ONLINE", [String(describing: $0.title.uppercased())]) } ?? L10n.text("CHANGE ARTWORK"))
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(subject.name)
                        .seleneFont(40)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .padding(.leading, canvas.u(6))
                        .padding(.bottom, canvas.u(14))
                    tabs
                    if browsing != nil {
                        searchField
                            .padding(.top, canvas.u(14))
                    }
                    status
                    grid
                }
                .frame(width: canvas.u(1240), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90))
                .padding(.bottom, canvas.u(20))
                .contentShape(Rectangle())

                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"), action: back)], right: rightHints,
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18,
                               rightReserve: [["Open page"], ["Previous"], ["Next"], ["Choose", "Search"]])
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .onReceive(NotificationCenter.default.publisher(for: .nxGameOptionsGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handleGamepad(action)
        }
        .task(id: slot) { await search(slot) }
        .task(id: browseTaskKey) { await browse() }
        .overlay {
            if viewModel.isEditingSteamGridDBKey {
                SteamGridDBKeyDialog(viewModel: viewModel, gamepad: .nxGameOptionsGamepadAction) { saved in
                    viewModel.isEditingSteamGridDBKey = false
                    let source = pendingBrowse
                    pendingBrowse = nil
                    if saved, let source { openBrowse(source) }
                }
            }
        }
        .task(id: "\(slot.rawValue)|\(pickRevision)") { await loadPickPreview() }
        .task(id: "icon|\(slot.rawValue)|\(pickRevision)") { await loadAutomaticIcon() }
        .overlay {
            if askAppIcon {
                ZStack {
                    SeleneTheme.scrim45.ignoresSafeArea()
                    SeleneConfirmDialog(title: L10n.text("Where should the icon appear?"),
                                        message: appIconMessage,
                                        confirmTitle: L10n.text("Use on the Mac"),
                                        cancelTitle: L10n.text("Only here"),
                                        focus: $appIconFocus,
                                        onCancel: { answerAppIcon(false) },
                                        onConfirm: { answerAppIcon(true) })
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: askAppIcon)
    }

    private var appIconMessage: String {
        let running = macApp.map { RunningGameMonitor.runningApplication(for: $0) != nil } ?? false
        return L10n.text("Only here changes the image inside Arcane. Use on the Mac also shows it in Finder and the Dock. Automatic uses the game's own icon, then an online image if available. Changing the image keeps this location choice.")
            + (running ? L10n.text(" It changes when the game quits.") : L10n.text(" A large game takes about a minute."))
    }

    func answerAppIcon(_ use: Bool) {
        SoundEffectService.shared.play(.click)
        askAppIcon = false
        if let macApp { appIcon.setUsesPickedAppIcon(use, for: macApp) }
    }

    /// Ask for every game, including NUPs, dumps and games not built yet.
    func iconPicked() {
        guard slot == .icon, let macApp else { return }
        editingIconLocation = false
        appIconFocus = appIcon.usesIconOnMac(for: macApp) ? .confirm : .cancel
        askAppIcon = true
    }

    private var rightHints: [HintItem] {
        let move = [HintItem(.lb, L10n.text("Previous")), HintItem(.rb, L10n.text("Next"))]
        guard browsing != nil else { return move + [HintItem(.a, L10n.text("Choose"))] }
        let page = browseResult?.page.map { url in HintItem(.x, L10n.text("Open page"), action: { NSWorkspace.shared.open(url) }) }
        let accept = focus < 0 ? HintItem(.a, L10n.text("Search"), action: { fieldFocused = true })
                               : HintItem(.a, L10n.text("Choose"), action: chooseFocused)
        return (page.map { [$0] } ?? []) + move + (downloading ? [] : [accept])
    }

    private var tabs: some View {
        HStack(spacing: canvas.u(8)) {
            ForEach(ArtworkSlot.allCases, id: \.self) { tab in
                Text(tab.title)
                    .seleneFont(17, .semibold)
                    .foregroundColor(tab == slot ? SeleneTheme.ink : SeleneTheme.ink60)
                    .padding(.horizontal, canvas.u(20))
                    .padding(.vertical, canvas.u(9))
                    .background(Capsule().fill(tab == slot ? SeleneTheme.glassSolid : Color.clear))
                    .contentShape(Capsule())
                    .onTapGesture { select(tab) }
                    .accessibilityAddTraits(tab == slot ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.leading, canvas.u(2))
    }

    /// The source's search, prefilled with the game's name; Return searches.
    private var searchField: some View {
        HStack(spacing: canvas.u(10)) {
            MaterialIconView(.search, size: 22).foregroundColor(SeleneTheme.ink60)
            TextField("", text: $browseDraft,
                      prompt: Text(L10n.format("Search %@", [String(describing: browsing?.title ?? "")])).foregroundColor(SeleneTheme.ink60))
                .textFieldStyle(.plain)
                .seleneFont(18)
                .foregroundColor(SeleneTheme.ink)
                .focused($fieldFocused)
                .onSubmit(submitSearch)
                .onExitCommand { fieldFocused = false }
        }
        .padding(.horizontal, canvas.u(16))
        .padding(.vertical, canvas.u(10))
        .background(Capsule().fill(SeleneTheme.glassSolid))
        .overlay(Capsule().strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
            .padding(canvas.u(-4))
            .opacity(focus < 0 ? 1 : 0))
        .frame(width: canvas.u(560))
        .padding(.leading, canvas.u(8))
        .onChange(of: fieldFocused) { _, focused in if focused { focus = -1 } }
    }

    @ViewBuilder
    private var status: some View {
        Text(message ?? (browsing.map(browseStatus) ?? mainStatus))
            .seleneFont(16)
            .foregroundColor(SeleneTheme.ink60)
            .lineLimit(1)
            .frame(height: canvas.u(22), alignment: .leading)
            .padding(.leading, canvas.u(10))
            .padding(.vertical, canvas.u(10))
    }

    private var mainStatus: String {
        if let appIcon = appIconStatus { return appIcon }
        return searching.contains(slot) ? L10n.text("Searching…") : (found[slot]?.isEmpty ?? false) ? L10n.text("No images found") : artworkLocation
    }

    /// On the Icon tab, how the game app's own icon change stands: signing a large app takes about a minute.
    private var appIconStatus: String? {
        guard slot == .icon, macApp != nil else { return nil }
        let progress = appIcon.appIconProgress[subject.id]
        if let progress {
            switch progress {
            case .searching, .updating, .failed: return progress.message
            default: break
            }
        }
        if !hasPick {
            if !automaticIconChecked { return AppIconProgress.searching.message }
            if automaticIconPreview == nil { return AppIconProgress.unavailable.message }
        }
        return progress == .unavailable ? nil : progress?.message
    }

    private func browseStatus(_ source: ArtworkBrowseSource) -> String {
        if downloading { return L10n.format("Downloading the full image from %@…", [String(describing: source.title)]) }
        guard let result = browseResult else { return L10n.format("Searching %@ for “%@”…", [String(describing: source.title), String(describing: browseQuery)]) }
        guard result.page != nil else {
            return L10n.format("%@ has no %@ called “%@”", [String(describing: source.title), String(describing: source == .launchBox && subject.steam == nil ? L10n.text("Switch game") : "game"), String(describing: browseQuery)])
        }
        if browseLoading.contains(slot) && (browseItems[slot] ?? []).isEmpty { return L10n.text("Loading…") }
        if (browseItems[slot] ?? []).isEmpty {
            return L10n.format("%@ has no %@ for “%@”", [String(describing: source.title), String(describing: slot.title.lowercased()), String(describing: browseQuery)])
        }
        return L10n.format("%@ · “%@” · full size downloads when you choose", [String(describing: source.title), String(describing: browseQuery)])
    }

    private var artworkLocation: String {
        switch slot {
        case .cover: return L10n.text("Collection · Suggestions")
        case .icon: return L10n.text("Game tiles")
        case .logo: return L10n.text("Library · Launch")
        case .background:
            return viewModel.settingsStore?.settings.keepWallpaperOnGames == true
                ? L10n.text("Details · Launch · Home: wallpaper") : L10n.text("Library · Launch")
        }
    }

    private var grid: some View {
        let tiles = self.tiles
        let rows = stride(from: 0, to: tiles.count, by: columns).map { Array($0..<min($0 + columns, tiles.count)) }
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: canvas.u(22)) {
                    ForEach(rows, id: \.self) { row in
                        HStack(alignment: .top, spacing: canvas.u(24)) {
                            ForEach(row, id: \.self) { index in
                                tileView(tiles[index], focused: index == focus)
                                    .id(index)
                                    .onTapGesture {
                                        focus = index
                                        choose(tiles[index])
                                    }
                            }
                        }
                    }
                }
                // Room inside the scroll's clip for the focused tile: it grows, its ring
                // sits 6 outside it and the ring's glow spreads further.
                .padding(.vertical, canvas.u(Self.ringRoom))
                .padding(.horizontal, canvas.u(Self.ringRoom))
            }
            .scrollIndicators(.hidden)
            // The room reaches past the column, so the tiles still line up with the title.
            .padding(.horizontal, canvas.u(8 - Self.ringRoom))
            .padding(.top, canvas.u(-Self.ringRoom / 2))
            .onChange(of: focus) { _, index in
                guard index >= 0 else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    /// Space kept round the grid for the focus ring and its glow.
    private static let ringRoom: CGFloat = 30

}
