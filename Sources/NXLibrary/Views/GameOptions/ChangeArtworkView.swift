import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers
import NXLibraryCore

/// Game options → Edit details → Change artwork, after Playnite's artwork picker.
/// Tabs for Cover, Background, Icon and Logo; each shows Automatic, the player's
/// pick, every image GameTDB, Title DB, the Nintendo store, Steam and Wikimedia
/// Commons offer (with its size in pixels), and From file…. A choice is kept in `ArtworkPicks` and never
/// overwritten by automatic art; Automatic takes it back.
///
/// Input: arrows or the stick move in the grid, L/R (Q/E) change the tab, A chooses,
/// B (or Esc) returns to Game options. A click chooses.
struct ChangeArtworkView: View {
    @ObservedObject var viewModel: AppViewModel
    let game: PortedGame
    let onClose: () -> Void

    @ObservedObject private var picks = ArtworkPicks.shared
    @State private var slot: ArtworkSlot = .cover
    @State private var focus = 0
    /// Images found per slot, in the order the picker lists them, with small previews.
    @State private var found: [ArtworkSlot: [Found]] = [:]
    @State private var searching: Set<ArtworkSlot> = []
    @State private var titleDB: TitleDBInfo?
    @State private var titleDBLoaded = false
    /// The same game on Steam, looked up once.
    @State private var steamAppID: Int?
    @State private var steamLoaded = false
    @State private var pickPreview: NSImage?
    @State private var message: String?
    @State private var keyMonitor: Any?

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    struct Found: Equatable {
        let order: Int
        let art: LoadedArtwork
        let preview: NSImage
    }

    enum Tile: Equatable {
        case automatic, yourPick, art(Found), file
    }

    private var titleKey: String { game.titleId ?? game.uniqueKey }
    private var hasPick: Bool { picks.url(titleID: titleKey, slot: slot) != nil }

    private var tiles: [Tile] {
        [.automatic] + (hasPick ? [.yourPick] : []) + (found[slot] ?? []).map(Tile.art) + [.file]
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
                .onTapGesture { close() }

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CHANGE ARTWORK")
                        .seleneFont(15, .semibold)
                        .foregroundColor(SeleneTheme.ink60)
                        .padding(.leading, canvas.u(8))
                    Text(game.name)
                        .seleneFont(40)
                        .foregroundColor(SeleneTheme.ink)
                        .lineLimit(1)
                        .padding(.leading, canvas.u(6))
                        .padding(.bottom, canvas.u(14))
                    tabs
                    status
                    grid
                }
                .frame(width: canvas.u(1240), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, canvas.u(90))
                .padding(.bottom, canvas.u(20))
                .contentShape(Rectangle())

                SeleneHintsBar(left: [HintItem(.b, "Back", action: close)],
                               right: [HintItem(.lb, "Previous"), HintItem(.rb, "Next"), HintItem(.a, "Choose")],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
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
        .task(id: "\(slot.rawValue)|\(picks.revision)") { await loadPickPreview() }
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

    @ViewBuilder
    private var status: some View {
        let text = message ?? (searching.contains(slot) ? "Looking on GameTDB, Title DB, the Nintendo store, Steam and Wikimedia Commons…"
                                : (found[slot]?.isEmpty ?? false) ? "Nothing found online. Choose a file instead." : nil)
        Text(text ?? " ")
            .seleneFont(14)
            .foregroundColor(SeleneTheme.ink60)
            .padding(.leading, canvas.u(10))
            .padding(.vertical, canvas.u(10))
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
            glyphFace(.restore)
        case .file:
            glyphFace(.folder)
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
            .aspectRatio(contentMode: slot == .logo ? .fit : .fill)
            .padding(slot == .logo ? canvas.u(18) : 0)
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
            case .cover: return ("Automatic", "GameTDB, or a composed cover")
            case .background: return ("Automatic", "The game's own art, then Title DB")
            case .icon: return ("Automatic", "The game's own icon")
            case .logo: return ("Automatic", "The store logo, then Steam")
            }
        case .yourPick:
            return ("Your pick", "Saved on this Mac")
        case .art(let item):
            return (item.art.candidate.source, item.art.resolution)
        case .file:
            return ("From file…", "PNG or JPEG")
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
        if !titleDBLoaded, let titleId = game.titleId {
            titleDB = await TitleDBInfo.fetch(titleID: titleId)
            titleDBLoaded = true
        }
        let metadata = viewModel.storeMetadata[game.id]
        let names = [game.name, metadata?.name, titleDB?.name].compactMap { $0 }
        let entries = slot == .cover ? await viewModel.boxArt.pickerEntries(names: names) : []
        if !steamLoaded {
            steamAppID = await SteamStoreArt.findAppID(names: names)
            steamLoaded = true
        }
        let commons = slot == .logo ? await CommonsLogos.find(names: names) : []
        let candidates = ArtworkCandidates.list(for: slot, entries: entries, titleDB: titleDB,
                                                storeHeader: metadata?.headerImageURL, storeImage: metadata?.imageURL,
                                                storeLogo: metadata?.logoURL, steamAppID: steamAppID,
                                                commonsLogos: commons)
        found[slot] = []
        await withTaskGroup(of: Found?.self) { group in
            for (order, candidate) in candidates.enumerated() {
                group.addTask {
                    guard let art = await ArtworkCandidates.load(candidate),
                          let preview = Self.thumbnail(art.data) else { return nil }
                    return Found(order: order, art: art, preview: preview)
                }
            }
            for await item in group {
                guard let item else { continue }
                var list = found[slot] ?? []
                list.append(item)
                list.sort { $0.order < $1.order }
                found[slot] = list
            }
        }
        // Left for another tab before it finished: search again on return.
        if Task.isCancelled { found[slot] = nil }
    }

    private func loadPickPreview() async {
        guard let url = picks.url(titleID: titleKey, slot: slot) else {
            pickPreview = nil
            return
        }
        pickPreview = await GameArtLoader.decode(at: url, maxPixelSize: 600)
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
            guard hasPick else { return }
            picks.remove(titleID: titleKey, slot: slot)
            applied()
        case .yourPick:
            SoundEffectService.shared.play(.click)
        case .art(let item):
            save(item.art.data)
        case .file:
            SoundEffectService.shared.play(.click)
            chooseFile()
        }
    }

    private func save(_ data: Data) {
        do {
            try picks.save(data, titleID: titleKey, slot: slot)
            applied()
            // The check moves to Your pick, second in the grid.
            focus = 1
        } catch {
            message = error.localizedDescription
            SoundEffectService.shared.play(.error)
        }
    }

    /// Screens reload their art from the new revision; decoded copies of the old art go.
    private func applied() {
        GameArtLoader.shared.forget(game)
        SoundEffectService.shared.play(.click)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a \(slot.title.lowercased()) for \(game.name)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            message = "That file could not be read."
            SoundEffectService.shared.play(.error)
            return
        }
        save(data)
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
        let next = ArtworkPickerFocus.moved(focus, by: direction, count: tiles.count, columns: columns)
        guard next != focus else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func close() {
        SoundEffectService.shared.play(.focus)
        onClose()
    }

    private func chooseFocused() {
        let tiles = self.tiles
        guard tiles.indices.contains(focus) else { return }
        choose(tiles[focus])
    }

    private func handleGamepad(_ action: GamepadAction) {
        switch action {
        case .navigateUp: move(.up)
        case .navigateDown: move(.down)
        case .navigateLeft: move(.left)
        case .navigateRight: move(.right)
        case .tabPrevious: select(ArtworkPickerFocus.slot(after: slot, by: -1))
        case .tabNext: select(ArtworkPickerFocus.slot(after: slot, by: 1))
        case .confirm: chooseFocused()
        case .cancel, .secondaryAction, .menu: close()
        default: break
        }
    }

    /// Arrows, Return/Space, Esc, and Q/E for the tabs (L and R on the keyboard).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.gameForSettingsSheet?.id == game.id,
                  let window = event.window, !window.isSheet, window.attachedSheet == nil,
                  NSApp.modalWindow == nil, !(window.firstResponder is NSText) else { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 126: move(.up)
            case 125: move(.down)
            case 123: move(.left)
            case 124: move(.right)
            case 12: select(ArtworkPickerFocus.slot(after: slot, by: -1))
            case 14: select(ArtworkPickerFocus.slot(after: slot, by: 1))
            case 36, 76, 49: chooseFocused()
            case 53: close()
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
