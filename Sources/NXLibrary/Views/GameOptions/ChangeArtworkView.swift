import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

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
    let subject: PersonalizationSubject
    let onClose: () -> Void

    @ObservedObject private var picks = ArtworkPicks.shared
    @ObservedObject private var steamPicks = SteamPersonalizations.shared.artwork
    @State private var slot: ArtworkSlot = .cover
    /// The focused tile; while browsing, -1 is the search field.
    @State private var focus = 0
    /// Images found per slot, in the order the picker lists them, with small previews.
    @State private var found: [ArtworkSlot: [Found]] = [:]
    @State private var searching: Set<ArtworkSlot> = []
    @State private var titleDB: TitleDBInfo?
    @State private var titleDBLoaded = false
    /// Everything the online sources have for this game, every slot, looked up once.
    @State private var online: [ArtworkCandidate]?
    @State private var pickPreview: NSImage?
    @State private var automaticIconPreview: NSImage?
    @State private var automaticIconChecked = false
    @State private var message: String?
    @State private var keyMonitor: Any?

    // Browsing a source
    @State private var browsing: ArtworkBrowseSource?
    /// SteamGridDB, waiting for its key dialog.
    @State private var pendingBrowse: ArtworkBrowseSource?
    /// The name searched, and the field's text.
    @State private var browseQuery = ""
    @State private var browseDraft = ""
    /// Raised by every search, so an answer for an older one is dropped.
    @State private var browseRound = 0
    @State private var browseResult: ArtworkBrowseSource.Found?
    @State private var browseItems: [ArtworkSlot: [Found]] = [:]
    @State private var browseLoading: Set<ArtworkSlot> = []
    @State private var downloading = false
    /// Image source and destination are independent; the same destination dialog is available for Automatic.
    @State private var askAppIcon = false
    @State private var editingIconLocation = false
    @State private var appIconFocus: SeleneConfirmButton = .confirm
    /// The main grid's focus, restored on leaving a source.
    @State private var mainFocus = 0
    @FocusState private var fieldFocused: Bool

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    struct Found: Equatable {
        let order: Int
        let art: LoadedArtwork
        let preview: NSImage
    }

    enum Tile: Equatable {
        case automatic, yourPick, iconLocation, art(Found), browse(ArtworkBrowseSource), file
    }

    private var hasPick: Bool { subject.artworkURL(slot) != nil }
    private var pickRevision: Int { picks.revision &+ steamPicks.revision }
    private var switch2: Bool { subject.titleId?.hasPrefix("04") == true }
    /// The installed nxnative game: only it has a Mac app icon to change.
    private var macApp: PortedGame? { subject.ported }
    private var gameNames: [String] {
        let metadata = viewModel.storeMetadata[subject.id]
        return [subject.name, metadata?.name, titleDB?.name].compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    private var tiles: [Tile] {
        if browsing != nil { return (browseItems[slot] ?? []).map(Tile.art) }
        // The sources to browse come right after Automatic (and Your pick), so a search is one move away and never
        // waits for the found images to load; From file… ends the grid.
        return [.automatic] + (hasPick ? [.yourPick] : []) + (slot == .icon && macApp != nil ? [.iconLocation] : []) + ArtworkBrowseSource.allCases.map(Tile.browse)
            + (found[slot] ?? []).map(Tile.art) + [.file]
    }

    // MARK: - Geometry (Selene units)

    private var columns: Int {
        switch slot {
        case .cover, .icon: return 6
        case .background, .logo: return 3
        }
    }

    private var tileSize: CGSize {
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
                    Text(browsing.map { L10n.format("%@ · BROWSE ONLINE", [String(describing: ($0.title.uppercased()))]) } ?? L10n.text("CHANGE ARTWORK"))
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
        return L10n.text("Only here changes the image inside NX Library. Use on the Mac also shows it in Finder and the Dock. Automatic uses the game's own icon, then an online image if available. Changing the image keeps this location choice.")
            + (running ? L10n.text(" It changes when the game quits.") : L10n.text(" A large game takes about a minute."))
    }

    private func answerAppIcon(_ use: Bool) {
        SoundEffectService.shared.play(.click)
        askAppIcon = false
        if let macApp { viewModel.setUsesPickedAppIcon(use, for: macApp) }
    }

    /// Ask for every game, including NUPs, dumps and games not built yet.
    private func iconPicked() {
        guard slot == .icon, let macApp else { return }
        editingIconLocation = false
        appIconFocus = viewModel.usesIconOnMac(for: macApp) ? .confirm : .cancel
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
                      prompt: Text(L10n.format("Search %@", [String(describing: (browsing?.title ?? ""))])).foregroundColor(SeleneTheme.ink60))
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
        .onChange(of: fieldFocused) { focused in if focused { focus = -1 } }
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
        let progress = viewModel.appIconProgress[subject.id]
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
        if downloading { return L10n.format("Downloading the full image from %@…", [String(describing: (source.title))]) }
        guard let result = browseResult else { return L10n.format("Searching %@ for “%@”…", [String(describing: (source.title)), String(describing: (browseQuery))]) }
        guard result.page != nil else {
            return L10n.format("%@ has no %@ called “%@”", [String(describing: (source.title)), String(describing: (source == .launchBox && subject.steam == nil ? L10n.text("Switch game") : "game")), String(describing: (browseQuery))])
        }
        if browseLoading.contains(slot) && (browseItems[slot] ?? []).isEmpty { return L10n.text("Loading…") }
        if (browseItems[slot] ?? []).isEmpty {
            return L10n.format("%@ has no %@ for “%@”", [String(describing: (source.title)), String(describing: (slot.title.lowercased())), String(describing: (browseQuery))])
        }
        return L10n.format("%@ · “%@” · full size downloads when you choose", [String(describing: (source.title)), String(describing: (browseQuery))])
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
            .onChange(of: focus) { index in
                guard index >= 0 else { return }
                withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    /// Space kept round the grid for the focus ring and its glow.
    private static let ringRoom: CGFloat = 30

    // MARK: - Tiles

    private func tileView(_ tile: Tile, focused: Bool) -> some View {
        let size = CGSize(width: canvas.u(tileSize.width), height: canvas.u(tileSize.height))
        let radius = canvas.u(12)
        let face = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return VStack(alignment: .leading, spacing: canvas.u(8)) {
            ZStack(alignment: .topTrailing) {
                face.fill(SeleneTheme.glass)
                preview(tile, size: size)
                    .frame(width: size.width, height: size.height)
                    .clipShape(face)
                if isCurrent(tile) {
                    MaterialIconView(.check, size: 26)
                        .foregroundColor(SeleneTheme.focus)
                        .padding(canvas.u(4))
                        .background(Circle().fill(SeleneTheme.glassSolid))
                        .padding(canvas.u(8))
                }
            }
            .frame(width: size.width, height: size.height)
            // The ring sits 6 outside the tile, centred on it.
            .overlay(SeleneTileRing(cornerRadius: canvas.u(18), active: focused).padding(canvas.u(-6)))
            VStack(alignment: .leading, spacing: canvas.u(2)) {
                Text(caption(tile).title)
                    .seleneFont(14, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text(caption(tile).detail)
                    .seleneFont(13)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .lineLimit(1)
            .frame(width: size.width, alignment: .leading)
        }
        .scaleEffect(focused ? 1.04 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption(tile).title), \(caption(tile).detail)")
        .accessibilityAddTraits(isCurrent(tile) ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func preview(_ tile: Tile, size: CGSize) -> some View {
        switch tile {
        case .automatic:
            if slot == .icon, let automaticIconPreview { image(automaticIconPreview) }
            else { glyphFace(.restore) }
        case .iconLocation:
            glyphFace(.settings)
        case .file:
            glyphFace(.folder)
        case .browse:
            glyphFace(.language)
        case .yourPick:
            if let pickPreview { image(pickPreview) } else { glyphFace(.image) }
        case .art(let item):
            image(item.preview)
        }
    }

    /// Logos fit on the glass so their edges show; everything else fills the tile.
    private func image(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: fits(image) ? .fit : .fill)
            .padding(slot == .logo ? canvas.u(18) : 0)
    }

    /// Logos, and banners much wider than the tile (Steam's library hero), show whole instead of cropped.
    private func fits(_ image: NSImage) -> Bool {
        slot == .logo || (slot == .background && image.size.width > image.size.height * 2.2)
    }

        private func glyphFace(_ icon: MaterialIcon) -> some View {
        MaterialIconView(icon, size: 44)
            .foregroundColor(SeleneTheme.ink60)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(_ tile: Tile) -> (title: String, detail: String) {
        switch tile {
        case .automatic:
            switch slot {
            case _ where subject.steam != nil: return (L10n.text("Automatic"), steamAutomatic)
            case .cover: return (L10n.text("Automatic"), L10n.text("GameTDB, or a composed cover"))
            case .background: return (L10n.text("Automatic"), L10n.text("The game's own art, then Title DB"))
            case .icon: return (L10n.text("Automatic"), L10n.text("The game's own icon, then Title DB"))
            case .logo: return (L10n.text("Automatic"), L10n.text("The store logo, then Steam"))
            }
        case .yourPick:
            return (L10n.text("Your pick"), L10n.text("Saved on this Mac"))
        case .iconLocation:
            return (L10n.text("Icon location"), macApp.map(viewModel.usesIconOnMac) == true ? L10n.text("Use on the Mac") : "Only here")
        case .art(let item):
            return (item.art.candidate.source, item.art.resolution)
        case .browse(let source):
            let keyless = source.needsKey && !viewModel.hasSteamGridDBKey
            return (source.title, keyless ? L10n.text("Browse online · add your key") : "Browse online")
        case .file:
            return (L10n.text("From file…"), L10n.text("PNG or JPEG"))
        }
    }

    /// What Automatic shows for a Steam game in this tab.
    private var steamAutomatic: String {
        switch slot {
        case .cover: return L10n.text("Steam’s library cover")
        case .background: return L10n.text("Screen-shaped art, then Steam")
        case .icon: return L10n.text("The Mac app’s own icon")
        case .logo: return L10n.text("Steam’s logo")
        }
    }

    private func isCurrent(_ tile: Tile) -> Bool {
        switch tile {
        case .automatic: return !hasPick
        case .yourPick: return true
        default: return false
        }
    }

    // MARK: - Loading

    /// Lists the slot's candidates and loads them all at once; each shows as it arrives.
    private func search(_ slot: ArtworkSlot) async {
        guard found[slot] == nil, !searching.contains(slot) else { return }
        searching.insert(slot)
        defer { searching.remove(slot) }
        if !titleDBLoaded, let titleId = subject.titleId {
            titleDB = await TitleDBInfo.fetch(titleID: titleId)
            titleDBLoaded = true
        }
        let metadata = viewModel.storeMetadata[subject.id]
        let names = gameNames
        var candidates: [ArtworkCandidate]
        found[slot] = []
        if let steam = subject.steam, let appID = subject.steamAppID {
            // Steam's own art for this AppID shows at once; the online sources take seconds and follow it.
            let screenshots = SteamGameFacts.shared.metadata(for: steam)?.screenshots ?? []
            let own = ArtworkCandidates.steamList(for: slot, appID: appID, screenshots: screenshots)
            await collect(own, slot: slot, from: 0)
            guard !Task.isCancelled else { found[slot] = nil; return }
            if online == nil { online = await OnlineArtwork.find(names: names) }
            candidates = ArtworkCandidates.steamList(for: slot, appID: appID, screenshots: screenshots, online: online ?? [])
            await collect(Array(candidates.dropFirst(own.count)), slot: slot, from: own.count)
        } else {
            let entries = slot == .cover ? await viewModel.boxArt.pickerEntries(names: names) : []
            if online == nil { online = await OnlineArtwork.find(names: names) }
            candidates = ArtworkCandidates.list(for: slot, entries: entries, titleDB: titleDB,
                                                storeHeader: metadata?.headerImageURL, storeImage: metadata?.imageURL,
                                                storeLogo: metadata?.logoURL, online: online ?? [])
            await collect(candidates, slot: slot, from: 0)
        }
        if slot == .icon, !Task.isCancelled,
           let titleID = subject.titleId,
           let url = await AppViewModel.automaticIconArtwork.automaticIcon(titleID: titleID, name: subject.name),
           AppViewModel.automaticIconArtwork.automaticIconSource(titleID: titleID) == "Switch Icon Showdown",
           let data = try? Data(contentsOf: url), let size = ArtworkCandidates.pixelSize(of: data),
           let preview = await GameArtLoader.decode(at: url, maxPixelSize: 600), !Task.isCancelled {
            let candidate = ArtworkCandidate(slot: .icon, source: "Switch Icon Showdown", url: url)
            let art = LoadedArtwork(candidate: candidate, data: data, pixelWidth: size.width, pixelHeight: size.height)
            found[slot, default: []].append(Found(order: candidates.count, art: art, preview: preview))
        }
        // Left for another tab before it finished: search again on return.
        if Task.isCancelled { found[slot] = nil }
    }

    /// Adds the candidates' previews to the slot as they arrive, in list order after `offset`.
    private func collect(_ candidates: [ArtworkCandidate], slot: ArtworkSlot, from offset: Int) async {
        for await item in Self.previews(of: candidates) {
            var list = found[slot] ?? []
            list.append(Found(order: item.order + offset, art: item.art, preview: item.preview))
            list.sort { $0.order < $1.order }
            found[slot] = list
        }
    }

    /// Downloads each candidate's preview at once and yields those that are images, as they arrive.
    private static func previews(of candidates: [ArtworkCandidate]) -> AsyncStream<Found> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Found?.self) { group in
                    for (order, candidate) in candidates.enumerated() {
                        group.addTask {
                            guard let art = await ArtworkCandidates.load(candidate),
                                  let preview = thumbnail(art.data) else { return nil }
                            return Found(order: order, art: art, preview: preview)
                        }
                    }
                    for await item in group {
                        if let item { continuation.yield(item) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var browseTaskKey: String {
        guard let browsing else { return "" }
        return "\(browsing.rawValue)|\(browseRound)|\(slot.rawValue)"
    }

    /// Searches the source once per name, then loads the open tab's previews.
    private func browse() async {
        guard let source = browsing else { return }
        let round = browseRound
        if browseResult == nil {
            let key = source.needsKey ? SteamGridDBKey().load() : nil
            let result = await source.search(browseQuery, gameNames: gameNames, switch2: switch2, computer: subject.steam != nil, key: key)
            guard round == browseRound, browsing == source, !Task.isCancelled else { return }
            browseResult = result
        }
        let slot = self.slot
        guard browseItems[slot] == nil, !browseLoading.contains(slot), let result = browseResult else { return }
        browseLoading.insert(slot)
        defer { browseLoading.remove(slot) }
        browseItems[slot] = []
        for await item in Self.previews(of: result.candidates.filter { $0.slot == slot }) {
            guard round == browseRound, browsing == source else { return }
            var list = browseItems[slot] ?? []
            list.append(item)
            list.sort { $0.order < $1.order }
            browseItems[slot] = list
        }
        if Task.isCancelled, round == browseRound { browseItems[slot] = nil }
    }

    private func loadPickPreview() async {
        guard let url = subject.artworkURL(slot) else {
            pickPreview = nil
            return
        }
        pickPreview = await GameArtLoader.decode(at: url, maxPixelSize: 600)
    }

    private func loadAutomaticIcon() async {
        guard slot == .icon else { return }
        automaticIconChecked = false
        let url: URL?
        if let macApp { url = await viewModel.automaticIconURL(for: macApp) }
        else if let steam = subject.steam { url = SteamArtworkRequest(game: steam, role: .square).automaticLocalURL }
        else { url = nil }
        let preview: NSImage?
        if let url { preview = await GameArtLoader.decode(at: url, maxPixelSize: 600) }
        else { preview = nil }
        guard !Task.isCancelled else { return }
        automaticIconPreview = preview
        automaticIconChecked = true
    }

    nonisolated private static func thumbnail(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 600
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    // MARK: - Choosing

    private func choose(_ tile: Tile) {
        message = nil
        switch tile {
        case .automatic:
            guard hasPick || slot == .icon else { return }
            if hasPick {
                do { try subject.removeArtwork(slot) } catch {
                    message = error.localizedDescription
                    SoundEffectService.shared.play(.error)
                    return
                }
            }
            applied()
            if slot == .icon, let macApp { viewModel.appIconPickChanged(for: macApp, removed: true) }
        case .iconLocation:
            guard let macApp else { return }
            editingIconLocation = true
            appIconFocus = viewModel.usesIconOnMac(for: macApp) ? .confirm : .cancel
            askAppIcon = true
            SoundEffectService.shared.play(.click)
        case .yourPick:
            SoundEffectService.shared.play(.click)
        case .art(let item):
            if browsing != nil { chooseBrowsed(item) } else { save(item.art.data) }
        case .browse(let source):
            SoundEffectService.shared.play(.click)
            mainFocus = focus
            if source.needsKey && !viewModel.hasSteamGridDBKey {
                pendingBrowse = source
                viewModel.isEditingSteamGridDBKey = true
            } else {
                openBrowse(source)
            }
        case .file:
            SoundEffectService.shared.play(.click)
            chooseFile()
        }
    }

    /// Downloads the full image, saves it and returns to the grid with it as Your pick.
    private func chooseBrowsed(_ item: Found) {
        guard !downloading, let source = browsing else { return }
        downloading = true
        SoundEffectService.shared.play(.click)
        Task { @MainActor in
            let data = await ArtworkCandidates.chosenData(item.art)
            downloading = false
            guard browsing == source else { return }
            guard let data else {
                message = L10n.format("The full image could not be downloaded from %@. Try again.", [String(describing: (source.title))])
                SoundEffectService.shared.play(.error)
                return
            }
            closeBrowse()
            save(data)
        }
    }

    private func save(_ data: Data) {
        do {
            try subject.saveArtwork(data, slot: slot)
            applied()
            // The check moves to Your pick, second in the grid.
            focus = 1
            iconPicked()
        } catch {
            message = error.localizedDescription
            SoundEffectService.shared.play(.error)
        }
    }

    /// Screens reload their art from the new revision; decoded copies of the old art go.
    private func applied() {
        if let macApp { GameArtLoader.shared.forget(macApp) }
        SoundEffectService.shared.play(.click)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L10n.format("Choose a %@ for %@.", [String(describing: (slot.title.lowercased())), String(describing: (subject.name))])
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            message = L10n.text("That file could not be read.")
            SoundEffectService.shared.play(.error)
            return
        }
        save(data)
    }

    // MARK: - Browsing a source

    private func openBrowse(_ source: ArtworkBrowseSource) {
        browsing = source
        browseDraft = subject.name
        browseQuery = subject.name
        startBrowseSearch()
    }

    private func submitSearch() {
        let text = browseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { browseDraft = subject.name }
        fieldFocused = false
        SoundEffectService.shared.play(.click)
        let query = text.isEmpty ? subject.name : text
        guard query != browseQuery || browseResult?.page == nil else {
            focus = tiles.isEmpty ? -1 : 0
            return
        }
        browseQuery = query
        startBrowseSearch()
    }

    private func startBrowseSearch() {
        browseResult = nil
        browseItems = [:]
        browseLoading = []
        message = nil
        focus = 0
        browseRound += 1
    }

    private func closeBrowse() {
        browsing = nil
        browseResult = nil
        browseItems = [:]
        browseLoading = []
        downloading = false
        fieldFocused = false
        message = nil
        browseRound += 1
        focus = mainFocus
    }

    private func openPage() {
        guard browsing != nil, let page = browseResult?.page else { return }
        SoundEffectService.shared.play(.click)
        NSWorkspace.shared.open(page)
    }

    // MARK: - Input

    private func select(_ tab: ArtworkSlot) {
        guard tab != slot else { return }
        slot = tab
        focus = 0
        message = nil
        SoundEffectService.shared.play(.focus)
    }

    private func move(_ direction: ArtworkPickerFocus.Direction) {
        let count = tiles.count
        if browsing != nil {
            if focus < 0 {
                guard direction == .down, count > 0 else { return }
                fieldFocused = false
                focus = 0
                SoundEffectService.shared.play(.focus)
                return
            }
            if direction == .up, focus < columns {
                focus = -1
                SoundEffectService.shared.play(.focus)
                return
            }
        }
        let next = ArtworkPickerFocus.moved(focus, by: direction, count: count, columns: columns)
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    /// Back: out of the source, or out of the picker.
    private func back() {
        if browsing != nil {
            SoundEffectService.shared.play(.focus)
            closeBrowse()
        } else {
            close()
        }
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        onClose()
    }

    private func chooseFocused() {
        if browsing != nil, focus < 0 {
            fieldFocused = true
            return
        }
        let tiles = self.tiles
        guard tiles.indices.contains(focus) else { return }
        choose(tiles[focus])
    }

    private func handleGamepad(_ action: GamepadAction) {
        // The key dialog reads the controller itself.
        if viewModel.isEditingSteamGridDBKey { return }
        if askAppIcon {
            switch action {
            case .navigateLeft, .navigateRight:
                let next: SeleneConfirmButton = action == .navigateLeft ? .cancel : .confirm
                if appIconFocus != next {
                    appIconFocus = next
                    SoundEffectService.shared.play(.focus)
                }
            case .confirm: answerAppIcon(appIconFocus == .confirm)
            case .cancel:
                askAppIcon = false
                // Back dismisses the location question. A newly chosen image still follows the saved scope.
                if !editingIconLocation, let macApp { viewModel.appIconPickChanged(for: macApp, removed: false) }
                SoundEffectService.shared.play(.focus)
            default: break
            }
            return
        }
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .tabPrevious: select(ArtworkPickerFocus.slot(after: slot, by: -1))
        case .tabNext: select(ArtworkPickerFocus.slot(after: slot, by: 1))
        case .confirm: chooseFocused()
        case .secondaryAction: browsing != nil ? openPage() : close()
        case .cancel: back()
        case .menu: close()
        default: break
        }
    }

    /// Arrows, Return/Space, Esc, Q/E for the tabs (L and R on the keyboard) and X for the source's page.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.optionsGameID == subject.id, !viewModel.isEditingSteamGridDBKey,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            if askAppIcon {
                switch event.keyCode {
                case 123: handleGamepad(.navigateLeft)
                case 124: handleGamepad(.navigateRight)
                case 36, 76, 49: handleGamepad(.confirm)
                case 53: handleGamepad(.cancel)
                default: break
                }
                return nil
            }
            switch event.keyCode {
            case 126: move(.up)
            case 125: move(.down)
            case 123: move(.left)
            case 124: move(.right)
            case 12: select(ArtworkPickerFocus.slot(after: slot, by: -1))
            case 14: select(ArtworkPickerFocus.slot(after: slot, by: 1))
            case 7 where browsing != nil: openPage()
            case 36, 76, 49: chooseFocused()
            case 53: back()
            default: return event
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
