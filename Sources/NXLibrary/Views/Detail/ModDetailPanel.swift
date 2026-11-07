import SwiftUI
import AppKit
import NXLibraryCore

/// One GameBanana mod over the game's page: its images, author, version beside the game's, likes and downloads, the
/// description as plain text with Read more under it, then its files, one row each (Install / Update / Installed,
/// progress with Cancel, the failure with Retry), and Open on GameBanana. Up/Down move between rows, A activates,
/// B (Esc) closes; a click activates a row. Rows are listed by `ModDetailPanel.rows`, which the page's input uses
/// too. The column scrolls inside the panel when it is taller (Read more on a long description, a mod with many
/// files): the wheel or the trackpad moves it, Up and Down read what lies before the next row and keep the row in
/// focus in view (`TextScroll.step`), and its edges fade where there is more.
struct ModDetailPanel: View {
    @ObservedObject var model: GameBananaBandModel
    let mod: AvailableMod
    let game: PortedGame
    /// The installed copy of this mod, if any.
    let installed: ModRecord?
    @Binding var focus: Int
    @Binding var expanded: Bool
    @ObservedObject var scroll: DetailScroll
    let onClose: () -> Void

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion

    /// The whole description's height, one line's, and the whole column's.
    @State private var textHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    /// The panel's height at most; the column's window is this less the padding.
    private static let panelHeight: CGFloat = 980
    private static let padding: CGFloat = 40
    private static let columnWidth: CGFloat = 700
    /// Lines shown before Read more.
    private static let collapsedLines: CGFloat = 8
    private static let space = "ModDetailColumn"

    enum Row: Equatable {
        case readMore
        case file(Int)
        case openPage
    }

    /// Long descriptions get a Read more row.
    static func rows(for mod: AvailableMod) -> [Row] {
        (mod.description.count > 420 ? [.readMore] : []) + mod.files.map { .file($0.id) } + [.openPage]
    }

    var body: some View {
        ZStack {
            SeleneTheme.scrim65
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            HStack(alignment: .top, spacing: canvas.u(36)) {
                gallery
                column
            }
            .padding(canvas.u(Self.padding))
            .background(RoundedRectangle(cornerRadius: canvas.u(24), style: .continuous).fill(SeleneTheme.glassSolid))
            .frame(maxHeight: canvas.u(Self.panelHeight))
        }
        .animation(reduceMotion ? nil : SeleneTheme.quick, value: expanded)
    }

    // MARK: - Column

    /// The column's window: the whole column when it fits in the panel, else the panel's room.
    private var window: CGFloat {
        min(contentHeight, canvas.u(Self.panelHeight - 2 * Self.padding))
    }

    private var column: some View {
        let window = self.window
        let state = scroll.state
        let fade = min(canvas.u(40), window / 4)
        return Color.clear
            .frame(width: canvas.u(Self.columnWidth), height: window)
            .overlay(alignment: .topLeading) {
                content
                    .frame(width: canvas.u(Self.columnWidth), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    })
                    .offset(y: -state.offset)
            }
            // Where there is more, the edge fades; the sides leave room for a row's focus ring.
            .mask(
                VStack(spacing: 0) {
                    edge(fade, toward: .top, shown: !state.atTop)
                    Color.black
                    edge(fade, toward: .bottom, shown: !state.atBottom)
                }
                .padding(.horizontal, canvas.u(-12))
                .animation(.easeOut(duration: 0.2), value: state.atTop)
                .animation(.easeOut(duration: 0.2), value: state.atBottom)
            )
            .overlay(alignment: .topTrailing) { indicator(window: window, state: state) }
            .onPreferenceChange(ContentHeightKey.self) { height in
                if abs(height - contentHeight) > 0.5 { contentHeight = height }
            }
            .onPreferenceChange(RowFramesKey.self) { frames in
                scroll.rows = frames.keys.sorted().compactMap { frames[$0].map { $0.minY...$0.maxY } }
            }
            .onAppear { scroll.setLayout(content: contentHeight, visible: window) }
            .onChange(of: [contentHeight, window]) { sizes in scroll.setLayout(content: sizes[0], visible: sizes[1]) }
    }

    private var content: some View {
        let rows = Self.rows(for: mod)
        return VStack(alignment: .leading, spacing: canvas.u(12)) {
            Group {
                Text("GAMEBANANA MOD")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                Text(mod.name)
                    .seleneFont(36)
                    .foregroundColor(SeleneTheme.ink)
                    .lineLimit(2)
                authorLine
                Text(versionLine)
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink75)
                if let requirementsLine {
                    Text(requirementsLine)
                        .seleneFont(16)
                        .foregroundColor(SeleneTheme.ink75)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(mod.likes) likes · \(mod.downloads) downloads")
                    .seleneFont(15)
                    .foregroundColor(SeleneTheme.ink60)
            }
            .allowsHitTesting(false)
            if !mod.description.isEmpty {
                // Read more sits under the text it opens, apart from the files.
                VStack(alignment: .leading, spacing: canvas.u(4)) {
                    description
                    if let index = rows.firstIndex(of: .readMore) { rowButton(.readMore, at: index) }
                }
                .padding(.top, canvas.u(6))
            }
            VStack(alignment: .leading, spacing: canvas.u(8)) {
                Text(mod.files.count == 1 ? "FILE" : "FILES")
                    .seleneFont(15, .semibold)
                    .foregroundColor(SeleneTheme.ink60)
                    .padding(.leading, canvas.u(14))
                    .allowsHitTesting(false)
                ForEach(Array(rows.enumerated()).filter { $0.element != .readMore }, id: \.offset) { index, row in
                    rowButton(row, at: index)
                }
            }
            .padding(.top, canvas.u(22))
            Text("Mod data provided by GameBanana")
                .seleneFont(14)
                .foregroundColor(SeleneTheme.ink60)
                .padding(.top, canvas.u(6))
                .allowsHitTesting(false)
        }
        .coordinateSpace(name: Self.space)
    }

    /// A row: a click focuses and runs it. Rows scrolled out of the window take no clicks.
    private func rowButton(_ row: Row, at index: Int) -> some View {
        rowView(row, focused: focus == index)
            .contentShape(Rectangle())
            .onTapGesture {
                focus = index
                activate(row)
            }
            .allowsHitTesting(isInWindow(index))
            .background(GeometryReader { proxy in
                Color.clear.preference(key: RowFramesKey.self, value: [index: proxy.frame(in: .named(Self.space))])
            })
    }

    private func isInWindow(_ index: Int) -> Bool {
        guard scroll.rows.indices.contains(index) else { return true }
        let span = scroll.rows[index], state = scroll.state
        return span.upperBound > state.offset && span.lowerBound < state.offset + window
    }

    // MARK: - Description

    /// Eight lines, or after Read more all of it.
    private var descriptionHeight: CGFloat {
        TextScroll.windowHeight(text: textHeight, collapsed: lineHeight * Self.collapsedLines, expanded: expanded)
    }

    private var description: some View {
        let height = descriptionHeight
        let cut = !expanded && textHeight > height + 0.5
        return Color.clear
            .frame(width: canvas.u(Self.columnWidth), height: height)
            .overlay(alignment: .topLeading) {
                Text(mod.description)
                    .seleneFont(16)
                    .foregroundColor(SeleneTheme.ink82)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: canvas.u(Self.columnWidth), alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: TextHeightKey.self, value: proxy.size.height)
                    })
            }
            // Collapsed, the text fades out where it is cut.
            .mask(
                VStack(spacing: 0) {
                    Color.black
                    edge(min(canvas.u(40), height / 4), toward: .bottom, shown: cut)
                }
            )
            .background(alignment: .topLeading) {
                // One line, to measure.
                Text("Ag").seleneFont(16).hidden()
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: LineHeightKey.self, value: proxy.size.height)
                    })
            }
            .allowsHitTesting(false)
            .onPreferenceChange(TextHeightKey.self) { height in
                if abs(height - textHeight) > 0.5 { textHeight = height }
            }
            .onPreferenceChange(LineHeightKey.self) { height in
                if abs(height - lineHeight) > 0.5 { lineHeight = height }
            }
    }

    /// A fading edge of a mask: clear at the edge, when there is more that way.
    private func edge(_ height: CGFloat, toward side: VerticalEdge, shown: Bool) -> some View {
        ZStack {
            LinearGradient(colors: [.clear, .black], startPoint: side == .top ? .top : .bottom,
                           endPoint: side == .top ? .bottom : .top)
            Color.black.opacity(shown ? 0 : 1)
        }
        .frame(height: height)
    }

    /// A thin bar in the margin while the column is taller than its window: where you are in it.
    @ViewBuilder
    private func indicator(window: CGFloat, state: TextScroll) -> some View {
        let track = window
        let bar = state.content > 0 ? max(canvas.u(36), track * state.visible / state.content) : 0
        let travel = max(track - bar, 0)
        Capsule()
            .fill(SeleneTheme.ink25)
            .frame(width: canvas.u(4), height: bar)
            .offset(x: canvas.u(16), y: state.reach > 0 ? travel * state.offset / state.reach : 0)
            .opacity(state.canScroll ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: state.canScroll)
            .allowsHitTesting(false)
    }

    private var gallery: some View {
        let images = Array(mod.images.prefix(4))
        return VStack(alignment: .leading, spacing: canvas.u(12)) {
            GameBananaImageView(url: images.first ?? mod.thumbnailURL, maxPixelSize: 1200)
                .frame(width: canvas.u(560), height: canvas.u(315))
                .clipShape(RoundedRectangle(cornerRadius: canvas.u(16), style: .continuous))
            if images.count > 1 {
                HStack(spacing: canvas.u(12)) {
                    ForEach(images.dropFirst(), id: \.self) { url in
                        GameBananaImageView(url: url, maxPixelSize: 500)
                            .frame(width: canvas.u(178), height: canvas.u(100))
                            .clipShape(RoundedRectangle(cornerRadius: canvas.u(10), style: .continuous))
                    }
                }
            }
        }
    }

    private var authorLine: some View {
        HStack(spacing: canvas.u(10)) {
            if let avatar = mod.avatarURL {
                GameBananaImageView(url: avatar, maxPixelSize: 96)
                    .frame(width: canvas.u(28), height: canvas.u(28))
                    .clipShape(Circle())
            }
            Text("by \(mod.author)")
                .seleneFont(18, .medium)
                .foregroundColor(SeleneTheme.ink)
        }
    }

    private var versionLine: String {
        let date = mod.updated.formatted(date: .abbreviated, time: .omitted)
        var parts = [mod.version.isEmpty ? "Updated \(date)" : "Version \(mod.version) · Updated \(date)"]
        if let version = game.versionString, !version.isEmpty { parts.append("Your game: \(version)") }
        return parts.joined(separator: "   ")
    }

    /// The author's requirements (game versions, other mods), so a mismatch shows before the download.
    private var requirementsLine: String? {
        guard !mod.requirements.isEmpty else { return nil }
        let names = mod.requirements.map { $0.isOptional ? "\($0.name) (recommended)" : $0.name }
        return "Requires: " + names.joined(separator: " · ")
    }

    // MARK: - Rows

    private struct RowText {
        var icon: MaterialIcon
        var title: String
        var detail: String?
        var action: String?
        var progress: Double?
        var message: String?
        var enabled = true
        /// Read more: a lighter row under the text, its chevron down (up once open).
        var compact = false
        var iconTurn: Double = 0
    }

    private func describe(_ row: Row) -> RowText {
        switch row {
        case .readMore:
            return RowText(icon: .chevron, title: expanded ? "Show less" : "Read more", action: nil,
                           compact: true, iconTurn: expanded ? -90 : 90)
        case .openPage:
            return RowText(icon: .link, title: "Open on GameBanana", detail: "Every file, comments and credits")
        case .file(let id):
            guard let file = mod.files.first(where: { $0.id == id }) else { return RowText(icon: .puzzle, title: "") }
            let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
            let date = file.dateAdded.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
            var text = RowText(icon: .puzzle, title: file.name, detail: size + date)
            // Only the file being installed shows the install; the others wait for it to end.
            let state = model.installState(mod: mod.id, file: file.id)
            switch state {
            case .downloading(let fraction):
                text.action = "Cancel"
                text.progress = fraction
                return text
            case .installing:
                text.action = "Installing…"
                text.enabled = false
                return text
            case .failed(let message):
                text.message = message
            case .done(let message):
                text.message = message
            case nil:
                break
            }
            if installed?.gameBananaFileID == file.id {
                text.action = "Installed"
                text.enabled = false
            } else if case .failed = state {
                text.action = "Retry"
            } else {
                text.action = installed == nil ? "Install" : "Update"
                text.enabled = !model.isInstalling(mod.id)
            }
            return text
        }
    }

    private func rowView(_ row: Row, focused: Bool) -> some View {
        let text = describe(row)
        return VStack(alignment: .leading, spacing: canvas.u(6)) {
            HStack(spacing: canvas.u(14)) {
                MaterialIconView(text.icon, size: 22)
                    .foregroundColor(SeleneTheme.ink75)
                    .rotationEffect(.degrees(text.iconTurn))
                VStack(alignment: .leading, spacing: canvas.u(2)) {
                    Text(text.title)
                        .seleneFont(text.compact ? 16 : 17, .medium)
                        .foregroundColor(text.compact ? SeleneTheme.ink82 : SeleneTheme.ink)
                        .lineLimit(1)
                    if let detail = text.detail {
                        Text(detail).seleneFont(14).foregroundColor(SeleneTheme.ink60).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let action = text.action {
                    Text(action)
                        .seleneFont(15, .semibold)
                        .foregroundColor(text.enabled ? SeleneTheme.ink : SeleneTheme.ink60)
                        .padding(.horizontal, canvas.u(14))
                        .padding(.vertical, canvas.u(6))
                        .background(Capsule().fill(text.enabled ? SeleneTheme.glass : Color.clear))
                }
            }
            if let progress = text.progress {
                ProgressView(value: progress).progressViewStyle(.linear).tint(SeleneTheme.focus)
            }
            if let message = text.message {
                Text(message)
                    .seleneFont(14, .medium)
                    .foregroundColor(SeleneTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, canvas.u(14))
        .padding(.vertical, canvas.u(text.compact ? 6 : 10))
        .background(RoundedRectangle(cornerRadius: canvas.u(12), style: .continuous)
            .fill(focused ? SeleneTheme.glass : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(14), style: .continuous)
            .strokeBorder(SeleneTheme.focus, lineWidth: canvas.u(2.5))
            .padding(canvas.u(-3))
            .opacity(focused ? 1 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text.title, text.detail, text.action, text.message].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    /// A row's action: shared with the page's controller handling.
    func activate(_ row: Row) {
        Self.activate(row, mod: mod, installed: installed, model: model, expanded: $expanded)
    }

    @MainActor
    static func activate(_ row: Row, mod: AvailableMod, installed: ModRecord?, model: GameBananaBandModel,
                         expanded: Binding<Bool>) {
        switch row {
        case .readMore:
            SoundEffectService.shared.play(.click)
            expanded.wrappedValue.toggle()
        case .openPage:
            SoundEffectService.shared.play(.click)
            NSWorkspace.shared.open(mod.pageURL)
        case .file(let id):
            guard let file = mod.files.first(where: { $0.id == id }) else { return }
            switch model.installState(mod: mod.id, file: file.id) {
            case .downloading:
                SoundEffectService.shared.play(.focus)
                model.cancel(mod.id)
            case .installing:
                SoundEffectService.shared.play(.error)
            default:
                // One install at a time: another file waits for the one running.
                if model.isInstalling(mod.id) || installed?.gameBananaFileID == file.id {
                    SoundEffectService.shared.play(.error)
                } else {
                    SoundEffectService.shared.play(.click)
                    model.install(mod, file: file)
                }
            }
        }
    }
}

private struct TextHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LineHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Each row's frame in the column, by its index in `ModDetailPanel.rows`.
private struct RowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
